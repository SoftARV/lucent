# Round 3 — one capture, to settle the battery mode mapping

**Scope: a single capture file.** Everything else about the protocol is
already known. This closes one specific gap.

Take this file to Windows. It is self-contained.

---

## The question

On battery, Synapse offers exactly two modes: **Balanced** and **Battery
Saver**. It writes `0x03` for one and `0x06` for the other. We do not know
which way round.

Round 1 recorded 3 = Balanced and 6 = Battery Saver, but that reading assumed
which button was pressed first, and the screenshots from that session show
Battery Saver was *already selected* when it began — so the first press was
probably Balanced, which would make the mapping the other way round.

Measurements on Linux support the inverted reading. Under identical load on
battery, `0x03` sustains 2461 MHz and `0x06` sustains 2907 MHz. A "saver" that
runs 450 MHz faster than "balanced" is backwards, so `0x03` is more likely
Battery Saver.

Both readings are plausible. One capture settles it.

---

## Setup

Already installed from the previous round, but for a fresh machine:

1. **Wireshark** from <https://www.wireshark.org/download.html>
2. **USBPcap** separately from
   <https://github.com/desowin/usbpcap/releases> — Wireshark 4.6+ does *not*
   bundle it. Version 1.5.4.0 works on Windows 11 26200.
3. Reboot after installing USBPcap.

Capture on `\\.\USBPcap1`, all devices on that hub. The Razer composite device
is address 1 there. No administrator rights needed.

---

## The capture

**Be on battery.** Unplug the charger and boot Windows unplugged, so Synapse's
*On Battery* tab is the live one. The Plugged In profile is irrelevant here.

Synapse does not re-send a mode that is already selected, so the starting
state matters. Fix it deliberately:

1. In Synapse → Performance → **On Battery**, select **Battery Saver**.
   Do this **before** starting the capture.
2. Start the capture.
3. Press **Balanced**.
4. Press **Battery Saver**.
5. Stop the capture. Save as `50-battery-balanced-then-saver.pcapng`.

Two actions rather than one, in a known order, so the file is self-checking:
the first write is Balanced, the second is Battery Saver, and the two values
**must differ**. If they come out the same, something went wrong and it will
be obvious rather than silently producing a wrong answer.

### Filter

```
usb.setup.wLength == 90 && usb.bmRequestType == 0x21
```

Do **not** filter on `usb.data_len >= 90` — a 251-byte Bluetooth control
transfer on the same hub decodes as a plausible looking Razer command and will
invent a discovery that does not exist.

### What you are looking for

Reports with class `0x0d` and command id `0x02`, at payload offsets 6 and 7.
There is no leading report-id byte on the USB wire; the 90-byte report starts
at offset 0. Layout:

```
 offset  field
   0     status          0x00 on the request
   1     transaction id  increments per command; the EC ignores it
   5     data size       4 for this command
   6     command class   0x0d
   7     command id      0x02
   8     arg[0]          0x01 from Synapse; the EC ignores it
   9     arg[1]          zone: 0x01 CPU, 0x02 GPU
  10     arg[2]          THE MODE VALUE -- this is what we want
  11     arg[3]          manual-fan flag
```

Each mode change writes **twice**, once per zone, with the same mode value.
So expect four `0x0d/0x02` writes total: two for Balanced, two for Battery
Saver.

Sanity check before leaving Windows: the mode byte at offset 10 should be
`0x03` in one pair and `0x06` in the other. If you see anything else, note it
— that is more interesting than the expected result.

---

## What to bring back

The `.pcapng` file, unparsed, into `tools/lucent-capture/`. A decoder on the
Linux side (`tools/decode_capture.py`) labels the commands, so no
interpretation is needed here.

If moving the binary is awkward:

```
tshark -r 50-battery-balanced-then-saver.pcapng ^
  -Y "usb.setup.wLength == 90 && usb.bmRequestType == 0x21" ^
  -T fields -e frame.number -e usb.data_fragment
```

A text dump of that decodes just as well.

---

## Optional, only if it is easy

Not needed for the mapping, but cheap while you are set up and unanswered:

**`51-battery-custom.pcapng`** — on battery, is Custom offered at all? Our
measurements say boost and the graphics limit are both inert unplugged, and
Synapse appears to hide Custom there. Confirming it is hidden would settle
whether that is Razer's UI choice or something the firmware enforces.

**`52-battery-fan.pcapng`** — on battery, is Fixed Fan Speed selectable?
Synapse greys it out, but the EC accepts manual fan on battery when Lucent
sets it directly. If Synapse greys it and the hardware allows it, that is
Razer's policy rather than a limitation.

---

## Context, if you want it

This is for **Lucent**, a GTK4/Vala Razer control app for Linux:
<https://github.com/SoftARV/lucent>

The task is **capture only** — no writes, no probing, no driver work. Analysis
happens on the Linux side.

Known AC mapping, already captured and verified: Balanced `0x00`, Performance
`0x02`, Custom `0x04`, Silent `0x05`. The battery values are a different set,
which is why this round exists.
