# Lucent

A small, fast GTK4 front end for Razer laptops — lighting, fans, power modes and the battery
charge limit, without a heavyweight settings suite.

Written in Vala with libadwaita. It speaks to the hardware directly over `hidraw`, so there is no
Python, no dbus-python, no numpy and no OpenRazer at runtime. A small background service owns the
device and the GUI is a pure D-Bus client.

## Features

- Brightness slider and lid-logo toggle
- Every lighting effect the keyboard supports
- Reads the keyboard's actual state on launch, so the window never opens showing stale defaults
- Effects are grouped into families with a mode selector, so the window stays short
- Nothing to save: the service remembers the effect and replays it at startup

### Effects

| Effect | Options |
| --- | --- |
| Off | — |
| Static | colour |
| Spectrum | — |
| Wave | direction |
| Reactive | colour, speed (500 ms – 2 s) |
| Breath | one colour / two colours / random |
| Starlight | one colour / two colours / random, speed |

Option rows appear only for the effect that uses them.

## Requirements

Runtime:

- GTK 4.10+ and libadwaita 1.4+
- `lucent-daemon`, enabled with `systemctl --user enable --now lucent-daemon`

Build:

- Vala, Meson, `blueprint-compiler`

On Arch:

```sh
sudo pacman -S gtk4 libadwaita vala meson blueprint-compiler
```

## Build and run

```sh
meson setup build
meson compile -C build
./build/src/lucent
```

To install system-wide:

```sh
sudo meson install -C build
```

## Device support

Developed and tested against a **Razer Blade 14 (2025)** (`1532:02C5`, 6x16 matrix).

Other Blades speak the same protocol, but the daemon currently hardcodes this product id, and the
effect list is fixed rather than derived from the device's reported capabilities. Both are on the
list.

## Not implemented yet

- Per-key colours (reachable on the same transport, but needs its own storage and replay)
- Saved presets
- Translations
- Flatpak package

## Licence

GPL-3.0-or-later.
