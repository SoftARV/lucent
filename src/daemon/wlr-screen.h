// Minimal C surface over zwlr_output_power_manager_v1, for WlrBackend.
//
// This is C rather than Vala because the protocol's generated bindings are
// listener structs full of function pointers, and hand-writing a VAPI for
// those is more fragile than the fifty lines it would save. Nothing here is
// GObject: the Vala side owns the lifetime and drives the fd.
//
// Deliberately read-only -- set_mode is never called, so the daemon cannot be
// what turns a panel off.

#pragma once

typedef struct _LucentWlr LucentWlr;

// Connects and binds. NULL when there is no compositor to talk to yet, or
// when it does not implement the protocol at all.
//
// out_connected distinguishes those two, and the caller needs it: a
// compositor that is not up yet is worth retrying, while one that answered
// and has no such protocol is simply not this backend's desktop and never
// will be.
LucentWlr *lucent_wlr_open (int *out_connected);

void lucent_wlr_close (LucentWlr *self);

// The Wayland fd, to be watched by the caller's main loop. There is no timer
// anywhere in here.
int lucent_wlr_fd (LucentWlr *self);

// Drains pending events. Returns < 0 if the connection is gone, in which case
// the caller must close and stop watching the fd.
int lucent_wlr_dispatch (LucentWlr *self);

// 1 when every output with working power control is off. One dark panel of
// two is not a blanked session.
int lucent_wlr_blanked (LucentWlr *self);

// 0 when no output has usable power control, e.g. every one of them answered
// `failed` because something else holds it exclusively. The caller must report
// itself absent in that case rather than claiming the panel is lit.
int lucent_wlr_usable (LucentWlr *self);
