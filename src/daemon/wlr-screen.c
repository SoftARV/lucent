#include "wlr-screen.h"

#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

#include "wlr-output-power-management-unstable-v1-client-protocol.h"

#define MAX_OUTPUTS 16

struct output {
    uint32_t global;
    struct wl_output *wl;
    struct zwlr_output_power_v1 *power;
    int mode;      // -1 unknown, 0 off, 1 on
    int usable;    // cleared by the failed event
};

struct _LucentWlr {
    struct wl_display *display;
    struct wl_registry *registry;
    struct zwlr_output_power_manager_v1 *manager;
    struct output outputs[MAX_OUTPUTS];
    int count;
};

// --- output power --------------------------------------------------------

static void power_mode (void *data, struct zwlr_output_power_v1 *power, uint32_t mode) {
    struct output *o = data;
    (void) power;
    o->mode = mode == ZWLR_OUTPUT_POWER_V1_MODE_ON ? 1 : 0;
}

static void power_failed (void *data, struct zwlr_output_power_v1 *power) {
    struct output *o = data;
    (void) power;

    // The output has no power control for us: unsupported, or another client
    // holds it exclusively. Not the same as the panel being lit, so it is
    // excluded from the verdict rather than counted as on.
    o->usable = 0;
    o->mode = -1;
}

static const struct zwlr_output_power_v1_listener power_listener = {
    .mode = power_mode,
    .failed = power_failed,
};

static void watch_output (LucentWlr *self, struct output *o) {
    if (!self->manager || o->power) {
        return;
    }
    o->power = zwlr_output_power_manager_v1_get_output_power (self->manager, o->wl);
    zwlr_output_power_v1_add_listener (o->power, &power_listener, o);
}

// --- registry ------------------------------------------------------------

static void global_add (void *data, struct wl_registry *registry, uint32_t name,
                        const char *interface, uint32_t version) {
    LucentWlr *self = data;
    (void) version;

    if (strcmp (interface, zwlr_output_power_manager_v1_interface.name) == 0) {
        self->manager = wl_registry_bind (registry, name,
                                          &zwlr_output_power_manager_v1_interface, 1);
        // Outputs can arrive before the manager does.
        for (int i = 0; i < self->count; i++) {
            watch_output (self, &self->outputs[i]);
        }
        return;
    }

    if (strcmp (interface, wl_output_interface.name) == 0 && self->count < MAX_OUTPUTS) {
        struct output *o = &self->outputs[self->count++];
        o->global = name;
        o->wl = wl_registry_bind (registry, name, &wl_output_interface, 1);
        o->mode = -1;
        o->usable = 1;
        watch_output (self, o);
    }
}

// A monitor can genuinely go away, and some compositors also drop and re-add
// one around a DPMS wake. Either way the power object dies with it.
static void global_remove (void *data, struct wl_registry *registry, uint32_t name) {
    LucentWlr *self = data;
    (void) registry;

    for (int i = 0; i < self->count; i++) {
        if (self->outputs[i].global != name) {
            continue;
        }

        if (self->outputs[i].power) {
            zwlr_output_power_v1_destroy (self->outputs[i].power);
        }
        wl_output_destroy (self->outputs[i].wl);

        self->outputs[i] = self->outputs[self->count - 1];
        self->count--;
        return;
    }
}

static const struct wl_registry_listener registry_listener = {
    .global = global_add,
    .global_remove = global_remove,
};

// --- connecting ----------------------------------------------------------

// The daemon is WantedBy=default.target and starts before the compositor, so
// uwsm finalizes WAYLAND_DISPLAY into the user manager's environment after
// this process already has its own. Measured: the unit went active at
// 02:50:18 and Hyprland started at 02:50:19, and the running daemon has
// XDG_RUNTIME_DIR with no WAYLAND_DISPLAY at all.
//
// So scanning is the mechanism, not a fallback. Reading WAYLAND_DISPLAY would
// work in every test run by hand and fail on every cold boot.
static struct wl_display *connect_any (void) {
    struct wl_display *display = wl_display_connect (NULL);
    if (display) {
        return display;
    }

    const char *dir = getenv ("XDG_RUNTIME_DIR");
    if (!dir) {
        return NULL;
    }

    DIR *dp = opendir (dir);
    if (!dp) {
        return NULL;
    }

    struct dirent *entry;
    while ((entry = readdir (dp))) {
        if (strncmp (entry->d_name, "wayland-", 8) != 0 || strstr (entry->d_name, ".lock")) {
            continue;
        }
        display = wl_display_connect (entry->d_name);
        if (display) {
            closedir (dp);
            return display;
        }
    }

    closedir (dp);
    return NULL;
}

LucentWlr *lucent_wlr_open (int *out_connected) {
    if (out_connected) {
        *out_connected = 0;
    }

    struct wl_display *display = connect_any ();
    if (!display) {
        return NULL;
    }

    if (out_connected) {
        *out_connected = 1;
    }

    LucentWlr *self = calloc (1, sizeof (LucentWlr));
    if (!self) {
        wl_display_disconnect (display);
        return NULL;
    }

    self->display = display;
    self->registry = wl_display_get_registry (display);
    wl_registry_add_listener (self->registry, &registry_listener, self);

    wl_display_roundtrip (display);   // globals
    wl_display_roundtrip (display);   // the mode event each power object sends

    // A compositor that does not implement the protocol is not a failure to
    // report, it is simply not this backend's desktop.
    if (!self->manager) {
        lucent_wlr_close (self);
        return NULL;
    }

    return self;
}

void lucent_wlr_close (LucentWlr *self) {
    if (!self) {
        return;
    }

    for (int i = 0; i < self->count; i++) {
        if (self->outputs[i].power) {
            zwlr_output_power_v1_destroy (self->outputs[i].power);
        }
        wl_output_destroy (self->outputs[i].wl);
    }

    if (self->manager) {
        zwlr_output_power_manager_v1_destroy (self->manager);
    }
    if (self->registry) {
        wl_registry_destroy (self->registry);
    }

    wl_display_disconnect (self->display);
    free (self);
}

int lucent_wlr_fd (LucentWlr *self) {
    return wl_display_get_fd (self->display);
}

int lucent_wlr_dispatch (LucentWlr *self) {
    // Only ever called with the fd readable, so this does not block. Newly
    // arrived outputs need their get_output_power request sent.
    int read = wl_display_dispatch (self->display);
    wl_display_flush (self->display);
    return read;
}

int lucent_wlr_usable (LucentWlr *self) {
    for (int i = 0; i < self->count; i++) {
        if (self->outputs[i].usable && self->outputs[i].mode >= 0) {
            return 1;
        }
    }
    return 0;
}

int lucent_wlr_blanked (LucentWlr *self) {
    int seen = 0;

    for (int i = 0; i < self->count; i++) {
        struct output *o = &self->outputs[i];

        if (!o->usable || o->mode < 0) {
            continue;
        }
        if (o->mode == 1) {
            return 0;
        }
        seen = 1;
    }

    // No usable output is not a blanked session -- lucent_wlr_usable is what
    // the caller checks for that.
    return seen;
}
