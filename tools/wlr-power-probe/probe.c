// Stage 0 probe for docs/screen-follow-portability.md.
//
// Answers, on hardware, what the wlroots power protocol only promises on
// paper, before any of it is built into lucent-daemon:
//
//   1. does a client with NO surface receive mode events? The daemon has no
//      window and never will.
//   2. does the compositor broadcast when ANOTHER client causes the change?
//      On Omarchy the blank comes from omarchy-shell, not from us.
//   3. is the protocol refused to us because something else holds exclusive
//      control? That arrives as a `failed` event, not as a bind error.
//   4. can the socket be found with no WAYLAND_DISPLAY? The daemon's
//      environment has XDG_RUNTIME_DIR and nothing else.
//
// Deliberately read-only: it never calls set_mode, so it cannot be what
// turns a panel off.
//
//   gcc -o probe probe.c wlr-output-power-management-unstable-v1-protocol.c
//       $(pkg-config --cflags --libs wayland-client)

#include <dirent.h>
#include <poll.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-output-power-management-unstable-v1-client-protocol.h"

#define MAX_OUTPUTS 8

struct output {
    struct wl_output *wl;
    struct zwlr_output_power_v1 *power;
    uint32_t name;
    char label[64];
    int mode;
};

static struct output outputs[MAX_OUTPUTS];
static int output_count = 0;
static struct zwlr_output_power_manager_v1 *manager = NULL;
static struct timespec started;

static double elapsed (void) {
    struct timespec now;
    clock_gettime (CLOCK_MONOTONIC, &now);
    return (now.tv_sec - started.tv_sec) + (now.tv_nsec - started.tv_nsec) / 1e9;
}

static void say (const char *fmt, ...) {
    char stamp[32];
    time_t t = time (NULL);
    struct tm tm;
    localtime_r (&t, &tm);
    strftime (stamp, sizeof stamp, "%H:%M:%S", &tm);

    printf ("[%s  t+%6.2fs] ", stamp, elapsed ());

    va_list ap;
    va_start (ap, fmt);
    vprintf (fmt, ap);
    va_end (ap);

    printf ("\n");
    fflush (stdout);
}

// --- output power events -------------------------------------------------

static void power_mode (void *data, struct zwlr_output_power_v1 *power, uint32_t mode) {
    struct output *o = data;
    (void) power;

    const char *word = mode == ZWLR_OUTPUT_POWER_V1_MODE_ON  ? "ON"
                     : mode == ZWLR_OUTPUT_POWER_V1_MODE_OFF ? "OFF"
                     : "?";

    // The first event per object is the current state, sent on creation --
    // the protocol's own equivalent of Mutter's read_current().
    say ("MODE   %-10s -> %-3s %s", o->label, word,
         o->mode < 0 ? "(initial state on object creation)" : "(change)");

    o->mode = (int) mode;
}

static void power_failed (void *data, struct zwlr_output_power_v1 *power) {
    struct output *o = data;
    (void) power;

    // The interesting failure: something else may hold exclusive control.
    say ("FAILED %-10s -- no power control for this output "
         "(unsupported, or another client holds it exclusively)", o->label);
}

static const struct zwlr_output_power_v1_listener power_listener = {
    .mode = power_mode,
    .failed = power_failed,
};

// --- wl_output name ------------------------------------------------------

static void output_geometry (void *d, struct wl_output *o, int32_t x, int32_t y,
                             int32_t pw, int32_t ph, int32_t sp, const char *make,
                             const char *model, int32_t tr) {
    (void) d; (void) o; (void) x; (void) y; (void) pw; (void) ph;
    (void) sp; (void) make; (void) model; (void) tr;
}
static void output_mode_ev (void *d, struct wl_output *o, uint32_t f,
                            int32_t w, int32_t h, int32_t r) {
    (void) d; (void) o; (void) f; (void) w; (void) h; (void) r;
}
static void output_done (void *d, struct wl_output *o) { (void) d; (void) o; }
static void output_scale (void *d, struct wl_output *o, int32_t s) {
    (void) d; (void) o; (void) s;
}
static void output_name (void *data, struct wl_output *wl, const char *name) {
    struct output *o = data;
    (void) wl;
    snprintf (o->label, sizeof o->label, "%s", name);
}
static void output_description (void *d, struct wl_output *o, const char *desc) {
    (void) d; (void) o; (void) desc;
}

static const struct wl_output_listener output_listener = {
    .geometry = output_geometry,
    .mode = output_mode_ev,
    .done = output_done,
    .scale = output_scale,
    .name = output_name,
    .description = output_description,
};

// --- registry ------------------------------------------------------------

static void global_add (void *data, struct wl_registry *registry, uint32_t name,
                        const char *interface, uint32_t version) {
    (void) data;

    if (strcmp (interface, zwlr_output_power_manager_v1_interface.name) == 0) {
        manager = wl_registry_bind (registry, name,
                                    &zwlr_output_power_manager_v1_interface, 1);
        say ("BOUND  zwlr_output_power_manager_v1 (compositor advertises v%u)", version);
        return;
    }

    if (strcmp (interface, wl_output_interface.name) == 0 && output_count < MAX_OUTPUTS) {
        struct output *o = &outputs[output_count++];
        // v4 carries the name event; fall back cleanly on older compositors.
        uint32_t use = version < 4 ? version : 4;
        o->wl = wl_registry_bind (registry, name, &wl_output_interface, use);
        o->name = name;
        o->mode = -1;
        snprintf (o->label, sizeof o->label, "output-%u", name);
        if (use >= 4) {
            wl_output_add_listener (o->wl, &output_listener, o);
        }
    }
}

static void global_remove (void *data, struct wl_registry *r, uint32_t name) {
    (void) data; (void) r;
    say ("GLOBAL removed: %u (a DPMS wake can show up here as remove+add)", name);
}

static const struct wl_registry_listener registry_listener = {
    .global = global_add,
    .global_remove = global_remove,
};

// --- socket discovery ----------------------------------------------------

// The daemon's environment has XDG_RUNTIME_DIR but no WAYLAND_DISPLAY, so
// connecting the ordinary way returns NULL there. Scanning is self-contained
// and needs nothing imported into the unit.
static struct wl_display *connect_any (void) {
    struct wl_display *d = wl_display_connect (NULL);
    if (d) {
        const char *w = getenv ("WAYLAND_DISPLAY");
        say ("CONNECT via WAYLAND_DISPLAY=%s", w ? w : "(default)");
        return d;
    }

    const char *dir = getenv ("XDG_RUNTIME_DIR");
    if (!dir) {
        say ("CONNECT failed: no WAYLAND_DISPLAY and no XDG_RUNTIME_DIR");
        return NULL;
    }

    say ("CONNECT no WAYLAND_DISPLAY -- scanning %s", dir);

    DIR *dp = opendir (dir);
    if (!dp) {
        return NULL;
    }

    struct dirent *e;
    while ((e = readdir (dp))) {
        if (strncmp (e->d_name, "wayland-", 8) != 0) {
            continue;
        }
        if (strstr (e->d_name, ".lock")) {
            continue;
        }
        d = wl_display_connect (e->d_name);
        if (d) {
            say ("CONNECT via scan: %s", e->d_name);
            closedir (dp);
            return d;
        }
    }

    closedir (dp);
    say ("CONNECT failed: no socket in %s answered", dir);
    return NULL;
}

int main (int argc, char **argv) {
    int seconds = argc > 1 ? atoi (argv[1]) : 60;

    clock_gettime (CLOCK_MONOTONIC, &started);

    struct wl_display *display = connect_any ();
    if (!display) {
        return 1;
    }

    struct wl_registry *registry = wl_display_get_registry (display);
    wl_registry_add_listener (registry, &registry_listener, NULL);

    wl_display_roundtrip (display);   // globals
    wl_display_roundtrip (display);   // output names

    if (!manager) {
        say ("NO zwlr_output_power_manager_v1 -- this compositor does not "
             "implement the protocol, backend would report present=false");
        return 2;
    }

    say ("OUTPUTS %d found", output_count);

    // No surface is ever created. That is the point: the daemon has no window.
    for (int i = 0; i < output_count; i++) {
        outputs[i].power = zwlr_output_power_manager_v1_get_output_power (manager,
                                                                         outputs[i].wl);
        zwlr_output_power_v1_add_listener (outputs[i].power, &power_listener, &outputs[i]);
    }

    wl_display_roundtrip (display);

    say ("WATCHING for %d s -- blank the panel now (idle timeout, lid, or "
         "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })')", seconds);

    struct pollfd pfd = { .fd = wl_display_get_fd (display), .events = POLLIN };

    while (elapsed () < seconds) {
        while (wl_display_prepare_read (display) != 0) {
            wl_display_dispatch_pending (display);
        }
        wl_display_flush (display);

        int remaining = (int) ((seconds - elapsed ()) * 1000);
        if (remaining <= 0) {
            wl_display_cancel_read (display);
            break;
        }

        if (poll (&pfd, 1, remaining) > 0) {
            wl_display_read_events (display);
            wl_display_dispatch_pending (display);
        } else {
            wl_display_cancel_read (display);
        }
    }

    say ("DONE");
    wl_display_disconnect (display);
    return 0;
}
