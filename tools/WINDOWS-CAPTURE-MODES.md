# Round 2 — map every Synapse control to its EC command

Round 1 established that CPU power limit, undervolt and GPU overclock are
**not on USB** — they go via ACPI/WMI. Do not chase those again.

This round is about the things that *are* on USB, where we have partial
information and are currently shipping wrong labels because of it.

Take this file to Windows. It is self-contained.

---

## Read this first: corrections from round 1

The earlier guide got three things wrong. These are already verified.

**USBPcap is a separate install.** Wireshark 4.6+ does not bundle it. Get it
from <https://github.com/desowin/usbpcap/releases> (1.5.4.0 works on Windows 11
26200). Capture works without administrator rights.

**There is no leading report-id byte on the USB wire.** The 90-byte report
starts at payload offset 0, so class is at offset **6** and command id at
offset **7** with no shift. `wLength` is 90, `usb.data_len` is 98 (8-byte
setup + 90). The report-id byte is a Linux hidraw artefact.

**The payload field is `usb.data_fragment`**, not `usb.capdata`.

Setup packet for reference:

```
bmRequestType 0x21   bRequest 0x09   wValue 0x0300   wIndex 0x0002   wLength 90
```

Report layout:

```
 offset  field
   0     status          0x00 sent, 0x02 = success in reply
   1     transaction id  Synapse increments it; the EC ignores the value
   2-3   remaining       0x0000
   4     protocol type   0x00
   5     data size       number of argument bytes that matter
   6     command class
   7     command id
   8+    arguments       Synapse puts 0x01 in arg[0]; the EC ignores it
```

---

## What we already know

Confirmed by decoding round 1's captures:

| Synapse label | EC value | how |
|---|---|---|
| Balanced | `0x03` | captured |
| Custom | `0x04` | captured |
| Silent | `0x05` | captured |
| Battery Saver | `0x06` | captured (battery only) |
| **Performance** | **unknown** | **never captured — the main gap** |

Values `0x00`, `0x01`, `0x02` and `0x07` are accepted by the EC and produce
distinct measured behaviour, but Synapse does not appear to use them. One of
`0x01`, `0x02` or `0x07` is probably Performance.

Commands already known:

| feature | class | set / get | args |
|---|---|---|---|
| power mode + manual-fan flag | `0x0d` | `0x02` / `0x82` | `[01, zone, mode, manual]` |
| fan setpoint | `0x0d` | `0x01` / `0x81` | `[01, zone, rpm/100]` |
| CPU / GPU boost | `0x0d` | `0x07` / `0x87` | `[01, zone, level]` |
| measured fan speed | `0x0d` | — / `0x88` | `[01, zone, 00]` |
| charge limit | `0x07` | `0x12` / `0x92` | `[enabled<<7 \| percent]` |

Zones: `0x01` CPU, `0x02` GPU. Everything is written to both.

Seen but not understood: `0x07/0x8c` (read, size 2) fires immediately before
every mode change. `0x07/0x8f` and `0x07/0x0f` fire in pairs on Apply.

---

## Capture plan

**Stay plugged in for all of this.** Battery Saver is the only battery-only
mode and it is already captured.

One action per file, capture started and stopped around just that action.
Short files with a single write are far easier to read than long ones.

### Part 1 — power modes (essential; do this even if you do nothing else)

Switch to each mode from a *different* mode, so a write definitely happens.
Synapse will not re-send a mode that is already selected.

| save as | action |
|---|---|
| `10-mode-performance.pcapng` | from Balanced → **Performance** |
| `11-mode-balanced.pcapng` | from Performance → **Balanced** |
| `12-mode-silent.pcapng` | from Balanced → **Silent** |
| `13-mode-custom.pcapng` | from Silent → **Custom** |

`10-mode-performance.pcapng` is the one that matters. The other three
re-confirm known values and cost a minute each.

Look for `0d 02` at offsets 6–7; the mode is the byte at offset **10**
(arg[2]).

### Part 2 — Custom's CPU and GPU presets

Requires Custom selected and plugged in. We assume these map to boost levels
0/1/2, but have never seen Synapse send them.

| save as | action |
|---|---|
| `20-cpu-low.pcapng` | Custom → CPU Preset → **Low** |
| `21-cpu-high.pcapng` | CPU Preset → **High** |
| `22-gpu-low.pcapng` | GPU → **Low** |
| `23-gpu-high.pcapng` | GPU → **High** |

Expect `0d 07` writes. Confirm the level byte and which zone gets which.

### Part 3 — fan control

| save as | action |
|---|---|
| `30-fan-fixed-3000.pcapng` | Fan Control → **Fixed Fan Speed** → 3000 RPM |
| `31-fan-fixed-5000.pcapng` | change the slider to **5000 RPM** |
| `32-fan-auto.pcapng` | back to **Auto (Default)** |
| `33-fan-curve.pcapng` | **Manual Fan Curve** → set any points → Apply |

Two RPM values matter for the same reason as before: with 3000 and 5000 we can
confirm the encoding is RPM/100 rather than guessing from one sample.

**`33-fan-curve.pcapng` is the interesting one.** Manual Fan Curve is a
feature Lucent has no command for at all. If it produces USB writes, it is
something new; if it produces none, it lives in ACPI like the power limit.

### Part 4 — optional, if you have patience

| save as | action |
|---|---|
| `40-synapse-start.pcapng` | start capture, **then launch Synapse**, wait for the Performance page |

This shows what Synapse reads at startup, which may explain `0x07/0x8c` and
tell us whether it trusts the EC's stored state or overwrites it.

---

## Filter

```
usb.transfer_type == 2 && usb.data_len >= 90
```

Synapse streams RGB (`0x03/0x0b`) constantly, and polls fan speed
(`0x0d/0x88`) whenever the Performance page is open. Both are noise. Note that
fan polling stops on battery, so "no `0x88`" does not mean the capture is dead.

---

## What to bring back

The `.pcapng` files, unparsed, into `tools/lucent-capture/`. There is already a
decoder on the Linux side (`tools/decode_capture.py`) that labels known
commands and flags unknown ones, so no interpretation is needed on Windows.

If moving binaries is awkward, `tshark -r FILE -Y "usb.data_fragment" -T
fields -e frame.number -e usb.data_fragment` produces a text dump that decodes
just as well.

---

## Why this round matters

Lucent currently ships **wrong labels**. It calls `0x03` "Silent" when Synapse
calls it Balanced, and dropped `0x05` and `0x06` as meaningless aliases when
they are in fact Silent and Battery Saver. That happened because the labels
were inferred from CPU clock alone, and Balanced and Silent differ almost
entirely in *graphics* power — 80 W against 50 W — with nearly identical CPU
clocks. They looked like the same mode.

The one value still missing is Performance. Until it is known, one of the
four modes in the app's own list cannot be named correctly.
