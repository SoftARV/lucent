# Making follow-screen work outside GNOME

`lighting-follow-screen` is inert on every desktop that is not GNOME. This is
the plan to change that. Scope is the screen-follow backend only -- packaging,
non-systemd init and other Razer models are deliberately out.

## The defect, precisely

`ScreenMonitor` is Mutter all the way down: the bus name, the object path, the
`PowerSaveMode` property and the `Bus.watch_name` presence check are all
`org.gnome.Mutter.DisplayConfig`. Nothing else publishes that name.

It does not fail loudly, and that is by design. When the name is unowned the
monitor reports `present = false` and holds `blanked = false`, because a
compositor that cannot be reached is not a blanked panel -- reporting blanked
would strand the keyboard dark with nothing left running to send the wake edge.
So on Hyprland the setting reads `true`, the daemon logs nothing, and the
keyboard simply never follows the panel.

## Measured on the target machine

Omarchy 4.0.0, Hyprland 0.56.2, one internal panel (eDP-2).

| Question | Answer | How |
|---|---|---|
| Is Mutter reachable? | no | no `org.gnome.Mutter.DisplayConfig` on the session bus, no `mutter`/`gnome-shell` process |
| What drives blanking? | `omarchy-shell` (Quickshell) | `idle.screensaver` 150 s, `idle.lock` 300 s in `~/.config/omarchy/shell.json`; no hypridle, no swayidle running |
| Is there a distro-native hook? | **no** | installed hook points are `battery-low`, `font-set`, `post-boot`, `post-update`, `pre-refresh-pacman`, `theme-set` -- none for idle, screensaver or lock |
| Does Hyprland speak the wlroots power protocol? | yes | `zwlr_output_power_manager_v1` and `zwlr_output_power_v1` present in the binary's symbols |
| Can the daemon reach Wayland? | **no** | `/proc/<pid>/environ` has `XDG_RUNTIME_DIR` but **no `WAYLAND_DISPLAY`** |

That last row is the one that shapes the work, and it is covered in stage 0.

An earlier probe of Hyprland's `socket2` event stream was **invalid** and its
result must not be reused: Hyprland 0.56 moved dispatch to a Lua API, so
`hyprctl dispatch dpms off` errored, the panel never blanked, and the empty
capture measured nothing. Whether `socket2` carries a usable DPMS edge is still
open -- upstream reports a monitor being removed and re-added on DPMS wake,
which would be an indirect and fragile proxy at best.

## Why the wlroots protocol, and not the alternatives

`zwlr_output_power_manager_v1` is the analogue of Mutter's `PowerSaveMode`: the
compositor pushes a `mode` event per output, so it keeps the property that
matters most here -- **the daemon still never runs a timer**, and its measured
zero idle CPU survives. It is also one implementation covering Hyprland, sway,
river and Wayfire rather than one per compositor.

Rejected, with reasons:

- **Hyprland `socket2`** -- compositor-specific, and carries no documented DPMS
  event. Inferring blanking from `monitorremoved`/`monitoradded` would key the
  backlight off a quirk.
- **An Omarchy hook** -- there is no idle or screensaver hook point to install
  into, so there is nothing to hook.
- **`hypridle` / `swayidle` config** -- not running here at all, and it would
  duplicate the save-and-restore logic the daemon already owns, losing the four
  guards that were built and tested around it.
- **`org.freedesktop.ScreenSaver`** -- tracks the *lock*, which is the exact
  openrazer bug this feature exists to avoid. Measured divergence up to 19.9 s
  on the wake edge.

## Design

Split `ScreenMonitor` into a small interface and swappable backends. The two
invariants stay, because both were paid for in bugs:

1. **Absent backend reports lit, never blanked.**
2. **Both edges are pushed.** A backend that can only poll does not qualify;
   the daemon's zero-timer property is the thing being protected.

```
ScreenBackend (interface)  present, blanked, changed signal
  |- MutterBackend         existing code, moved unchanged
  |- WlrOutputPowerBackend zwlr_output_power_manager_v1
  |- KWinBackend           unresearched, stage 4
```

Selection is by probing, not by sniffing `XDG_CURRENT_DESKTOP`: try each
backend, keep the first that reports `present`, and re-evaluate when a name
owner appears or the Wayland connection drops. That is what already lets the
Mutter path recover when the shell restarts underneath the daemon, and it
should not regress.

`blanked` with multiple outputs means **every** output is off. One dark panel
of two is not a blanked session.

## Stages

**Stage 0 -- probe. DONE, measured.** `tools/wlr-power-probe/` binds
`zwlr_output_power_manager_v1` and logs `mode` events across a real DPMS cycle.
It never calls `set_mode`, so it cannot itself blank anything.

| Question | Answer | Evidence |
|---|---|---|
| Does a client with **no surface** get `mode` events? | **yes** | probe creates no surface; got `ON` on creation, `OFF` at t+6.01 s, `ON` at t+13.44 s |
| Is the current state delivered on connect? | **yes** | first event per object is the state, the protocol's own `read_current()` |
| Does a change **we did not cause** get reported? | **yes** | blank driven by Hyprland's dispatcher, not by the probe |
| Does anything hold **exclusive** control? | **no** | no `failed` event across a full off/on cycle |
| Can the socket be found with no `WAYLAND_DISPLAY`? | **yes** | scanning `$XDG_RUNTIME_DIR` found `wayland-1` and connected |

The panel really did blank -- `dpmsStatus` read 0 monitors on while off.

**The environment finding is bigger than expected, and it decides the design.**
`systemctl --user show-environment` *does* carry `WAYLAND_DISPLAY=wayland-1`,
yet the running daemon's `/proc/<pid>/environ` does not. The timestamps say why:

```
02:50:18  lucent-daemon.service active
02:50:19  Hyprland starts
```

The daemon is `WantedBy=default.target` and comes up a second *before* the
compositor, and uwsm only finalizes `WAYLAND_DISPLAY` into the user manager's
environment afterwards. Units started later inherit it; this one never does.

So **scanning is not the tidier option, it is the only correct one** -- reading
`WAYLAND_DISPLAY` would work when tested by hand and fail on every cold boot.
That is the same shape as the hidraw ACL race already documented in CLAUDE.md,
and it wants the same answer: retry rather than assume, and connect by
discovery rather than by inherited state.

Correct dispatch syntax under Hyprland 0.56's Lua config, for the record:
`hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'`. The legacy
`hyprctl dispatch dpms off` is silently rejected.

**Still open from stage 0:** the blank here came from Hyprland's dispatcher.
On Omarchy the production blank comes from `omarchy-shell` at
`idle.screensaver`. If that client takes power control via `set_mode`, our
object could in principle receive `failed` -- untested, because reaching it
means idling for 150 s. Test it by lowering `idle.screensaver` temporarily
before trusting the backend in production.

## The backlight sysfs is not an instrument, and here is why

Recorded because it was used as corroborating evidence once and should not be
again. On this panel (`amdgpu_bl2`, `scale = non-linear`, max 400000):

| | `brightness` | `actual_brightness` | `bl_power` | drm `dpms` |
|---|---|---|---|---|
| lit | 240000 | 166859 | 0 | On |
| **blanked** | 240000 | **240000** | 0 | **Off** |
| woken | 240000 | 166859 | 0 | On |

`actual_brightness` goes **up** when the panel goes dark, and it lands exactly
on the stored `brightness`. Blanking at 240000 rather than the 160000 used
earlier is what makes that falsifiable: it reads 240000, not a constant.

So the two values are in different domains. `brightness` is the perceptual
scale the class device advertises; `actual_brightness` reads the hardware PWM
while the display is on, and falls back to returning the stored perceptual
value when the display is off and the hardware cannot be read. The mapping
between them is deterministic and content-independent -- not adaptive
backlight, which was the first guess:

| set | 40000 | 120000 | 160000 | 280000 | 400000 |
|---|---|---|---|---|---|
| actual | 5694 | 49506 | 83929 | 220059 | 389047 |
| ratio | 0.142 | 0.413 | 0.525 | 0.786 | 0.973 |

`bl_power` stays 0 throughout, so DPMS off does not route through the backlight
class device at all -- the display is disabled at the connector.

**The valid sysfs instrument is the DRM connector**, which tracked the blank
exactly on both edges:

```sh
cat /sys/class/drm/card2-eDP-2/dpms      # On / Off
cat /sys/class/drm/card2-eDP-2/enabled   # enabled / disabled
```

It is poll-only, so it is no use as a backend -- the whole point of the wlr
protocol is that it pushes. It is useful as an **independent check when testing
the backend**, which matters because otherwise the only witness to a blank is
the same compositor being tested. Note the card number varies between machines.

**Stage 1 -- extract the interface. DONE.** `ScreenBackend` is an abstract
class carrying the two invariants; `MutterBackend` holds the existing code
moved verbatim; `ScreenMonitor` became a selector that probes backends and
republishes the winner. `daemon-service.vala` is untouched -- the selector kept
the old class name and the `changed`/`blanked` surface, so nothing downstream
had to learn about backends.

Selection probes rather than reading `XDG_CURRENT_DESKTOP`, which describes
what launched the session rather than what is running and answering.

Verified: builds with no new warnings (the two `will never be NULL` notices on
`Bus.watch_name` lambdas moved file with the code -- 5 before, 5 after), daemon
starts, opens the device, owns the bus name, and every property reads back
unchanged.

**The gap that remains is honest and unclosed: there is no GNOME on this
machine.** The Mutter path was verified by inspection and by the code being
moved byte-for-byte, not by running it. It needs a second machine or a nested
session before release.

**Stage 2 -- `WlrBackend`. DONE, measured.** Built on
`zwlr_output_power_manager_v1` through a small C shim (`wlr-screen.c`), rather
than a hand-written VAPI over generated listener structs -- more fragile than
the code it would have saved. Read-only: `set_mode` is never called.

End to end on Hyprland 0.56.2, with the daemon driving a real cycle:

```
screen-monitor.vala:55: following the screen via wlr-output-power
brightness before: 75
BLANKED:           0
WOKE:             75
```

**The resident cost is unchanged, which was the thing at risk.** `wayland-client`
is a C library, not a toolkit, so the no-GTK rule is not breached -- but a new
fd watch in a daemon whose measured idle CPU is a literal zero had to be
checked rather than assumed:

| | recorded baseline | with WlrBackend |
|---|---|---|
| RSS | 7.6 MB | 7.09 MB |
| **PSS** | **1.1 MB** | **0.99 MB** |
| Threads | 5 | 5 |
| **Idle CPU, 180 s** | **0.000 s** | **0.000 s** |

Zero ticks over 180 s with the backend connected and the fd watched. That is
what the push requirement buys: an fd watch costs nothing while nothing
happens, where a 0.25 s poll would not.

**Stage 3 -- selection and failover,** plus the retest of all four existing
guards on the new backend: an explicit `ApplyBrightness` during a blank cancels
that restore; brightness and logo restore on separate flags; a second blank
does not overwrite saved values; turning the toggle off while dark hands both
back.

**Stage 4 -- KWin,** unresearched. `org.kde.Solid.PowerManagement` and an
`org_kde_kwin_dpms` protocol both surfaced in searching and neither is verified.
KWin does not implement the wlroots protocol, so Plasma needs its own backend or
it stays unsupported and honest about it.

## Open questions

- The one item left open in stage 0: whether an `omarchy-shell` idle blank
  takes exclusive power control and lands us a `failed` event.
- X11 sessions have no push mechanism for DPMS that has been identified; if
  none exists, X11 stays unsupported rather than getting a poll.
- Should the UI say why the toggle does nothing on an unsupported desktop? The
  daemon already knows -- `present` is false on every backend. Surfacing it
  beats a switch that silently does nothing, which is the bug being fixed.
