<div align="center">

<img src="data/icons/hicolor/scalable/apps/dev.miguel.Lucent.svg" width="112" alt="Lucent">

# Lucent

**Lighting, fans, power modes and the battery charge limit for Razer Blade laptops — on Linux, without OpenRazer.**

</div>

Lucent talks to the hardware directly over `hidraw`. There is no OpenRazer, no Python, no
`dbus-python`, no kernel module. A small background service owns the device; the GTK4 window is a
pure D-Bus client of it.

## What it does

### Lighting

- Brightness slider with a live percentage, plus 0/25/50/75/100 % quick-set buttons
- Lid-logo toggle
- Every effect the keyboard supports.
- **Follows the display, not the session lock.** The keyboard dims when the screen sleeps and lights
  up the moment it wakes.

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

### Performance

- A power mode **per power source**, so the machine can drop to Silent on battery and go back to
  Performance when you plug in. The firmware loses the mode on every suspend; the service rewrites it
- Manual fan speed, with a live tachometer showing what the fans are actually doing
  rather than what was last requested
- CPU and graphics boost presets, enabled only in Custom mode.

The mode names follow the power source, because the firmware's values do: plugged in you get
Balanced, Performance, Custom and Silent; on battery, Battery Saver and Balanced. That is not a
simplification — it is what Synapse does, and the values were read off a USB capture of it.

### Battery

- Charge limit, 50–80 %. It lives in EC nonvolatile memory, so it is written once and survives
  unplugging, suspend and reboot on its own

## Install

### Arch

```sh
cd packaging
makepkg -si
```

Everything lands where pacman already has a hook, so the udev rule and the systemd user unit are
installed for you. First run needs one click, which the app offers: enabling the service.

### From source

```sh
meson setup build
meson compile -C build
sudo meson install -C build
systemctl --user enable --now lucent-daemon
```

Build needs Vala, Meson and `blueprint-compiler`; runtime needs GTK 4.10+ and libadwaita 1.4+.

```sh
sudo pacman -S gtk4 libadwaita vala meson blueprint-compiler
```

Running from a build tree without installing is fine for the GUI, but the daemon needs its
GSettings schema and the udev rule, neither of which a build tree provides:

```sh
sudo cp data/60-lucent-razer.rules /usr/lib/udev/rules.d/
sudo udevadm control --reload && sudo udevadm trigger
GSETTINGS_SCHEMA_DIR=$PWD/build/data ./build/src/lucent-daemon
```

### Permissions

Lucent needs read/write access to the keyboard's `hidraw` node. The shipped udev rule grants it to
the logged-in user through `uaccess`, which is why it is numbered **60-** — a rule numbered above
`73-seat-late.rules` sets the tag after the ACL has already been applied, and fails silently.

No part of Lucent runs as root, and it never asks for your password.

## Device support

Developed and tested against a **Razer Blade 14 (2025)** — `1532:02C5`.

Other Blades speak the same protocol, but the daemon currently hardcodes this product id and the
effect list is fixed rather than derived from what the device reports. Both are on the list below.

## Not implemented

- Per-key colours — reachable on the same transport, but needs its own storage and replay
- Fan curves — buildable on the existing commands, but it would be the service's first periodic
  timer, and that idle zero above is worth protecting
- Per-zone fan speeds — the hardware takes different CPU and GPU setpoints; Lucent sends one to both
- CPU power limit, undervolt and GPU overclock — these are not on USB at all. They go through the
  `RAZR` and `AOD` ACPI interfaces, which is WMI work rather than HID work
- Saved presets, translations, a Flatpak package
- Ripple — it needs a 25 fps render loop and access to every keystroke to know where each ripple
  starts. Too steep for one effect

## Licence

GPL-3.0-or-later.
