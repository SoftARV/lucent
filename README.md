# Lucent

A small, fast GTK4 front end for [OpenRazer](https://openrazer.github.io/) — control your Razer
keyboard's lighting without a heavyweight settings suite.

Written in Vala with libadwaita. It talks to the OpenRazer daemon directly over D-Bus rather than
going through the OpenRazer Python bindings, so nothing pulls in Python, dbus-python or numpy at
runtime. The binary is around 360 KB.

## Features

- Brightness slider and lid-logo toggle
- Every lighting effect the daemon exposes for the keyboard
- Reads the keyboard's actual state on launch, so the window never opens showing stale defaults
- Effects are grouped into families with a mode selector, so the window stays short
- Nothing to save: the daemon already persists effect state and restores it on boot

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
| Ripple | one colour / random |

Option rows appear only for the effect that uses them.

## Requirements

Runtime:

- A running `openrazer-daemon`
- GTK 4.10+ and libadwaita 1.4+

Build:

- Vala, Meson, `blueprint-compiler`

On Arch:

```sh
sudo pacman -S openrazer-daemon gtk4 libadwaita vala meson blueprint-compiler
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

Any keyboard the OpenRazer daemon exposes should work, with one caveat: the effect list is currently
fixed rather than derived from the device's reported capabilities. On a keyboard that lacks one of
the effects above, selecting it will fail and show an error toast instead of the tile being hidden.
Filtering the grid by capability is on the list.

## Not implemented yet

- Per-key colours (the daemon does not persist custom frames, so this needs its own storage)
- Saved presets
- Translations
- Flatpak package

## Licence

GPL-3.0-or-later.
