# Capturing Synapse's USB traffic

Goal: find the HID commands Razer Synapse uses for three controls we cannot
reach from Linux — **CPU power limit**, **CPU voltage offset** (undervolt) and
**GPU overclock**. Synapse exposes all three; no open-source project
implements any of them.

This is passive observation. Nothing is written to the laptop, so there is no
risk to the machine, unlike probing unknown write commands blind.

Take this file to Windows. It is self-contained: everything needed to run the
capture and sanity-check it is here.

---

## Background: what we already know

Lucent talks to the Blade's embedded controller over USB HID, on the keyboard
device `1532:02c5`. Every command rides the same **90-byte report**, sent as a
HID feature report (`SET_REPORT`, `bmRequestType 0x21`, `bRequest 0x09`,
`wValue 0x0300`), prefixed on the wire by a report-id byte of `0x00`.

Byte layout of the 90-byte report:

```
 offset  field
   0     status            0x00 when sent, 0x02 = success in the reply
   1     transaction id    0x1f
   2-3   remaining packets 0x0000
   4     protocol type     0x00
   5     data size         number of argument bytes that matter
   6     command class
   7     command id
   8-87  arguments
   88    crc               XOR of bytes 2..87; the firmware ignores it
   89    reserved
```

Commands already known and implemented. Read id is always set id `| 0x80`:

| feature | class | set / get | args |
|---|---|---|---|
| power mode + manual-fan flag | `0x0d` | `0x02` / `0x82` | `[00, zone, mode, manual]` |
| fan setpoint | `0x0d` | `0x01` / `0x81` | `[00, zone, rpm/100]` |
| CPU / GPU boost | `0x0d` | `0x07` / `0x87` | `[00, zone, level]` |
| measured fan speed | `0x0d` | — / `0x88` | `[00, zone, 00]` |
| charge limit | `0x07` | `0x12` / `0x92` | `[enabled<<7 \| percent]` |

Zones are `0x01` CPU and `0x02` GPU; everything is written to both.

**What we are looking for is almost certainly class `0x0d`** with command ids
we have not seen — most likely in the `0x03`–`0x06` or `0x08`–`0x0f` range,
since `0x01`, `0x02` and `0x07` are taken.

---

## Setup

1. Install **Wireshark** from <https://www.wireshark.org/download.html>
2. During installation, **tick USBPcap** in the components list. This is easy
   to miss and nothing works without it.
3. **Reboot.** USBPcap installs a kernel driver.

### Finding the right interface

Wireshark will show several `USBPcap1`, `USBPcap2` … interfaces, one per root
hub. The Blade's keyboard is on one of them.

If you cannot tell which: Device Manager → *Keyboards* or *Human Interface
Devices* → the Razer entry → Properties → Details → **Location paths**. The
hub number there matches the USBPcap interface number.

Failing that, start a capture on each in turn and press a key — the one that
floods with traffic is the keyboard's hub.

---

## Step 1: capture a known action first

**Do not skip this.** It proves the capture is pointed at the right device and
shows what the framing looks like, before you go hunting for things whose
shape you do not know.

1. Start capture on the USBPcap interface
2. In Synapse → Performance, switch the **Plugged In** profile from one mode
   to another, e.g. Balanced → Silent
3. Stop capture, save as `00-mode-silent.pcapng`

You are looking for a control transfer carrying 90+ bytes whose 7th and 8th
bytes are `0d 02`, with arguments starting `00 01` or `00 02`. That is the
power-mode write, and finding it means everything else in this session is
trustworthy.

If you cannot find it, the capture is on the wrong interface. Fix that before
continuing — every later capture would be worthless.

---

## Step 2: capture the unknowns

One action per capture, started and stopped around just that action. Short
captures with a single write are far easier to read than long ones.

| save as | action in Synapse |
|---|---|
| `01-cpu-power-60.pcapng` | Custom → CPU → **CPU Power Limit** → set **60** → Apply |
| `02-cpu-power-90.pcapng` | same slider → set **90** → Apply |
| `03-undervolt-10.pcapng` | **CPU Voltage Optimizer** on → offset **−10** → Apply |
| `04-undervolt-25.pcapng` | same → offset **−25** → Apply |
| `05-gpu-oc-100.pcapng` | **GPU Overclock** on → GPU Clock Offset **+100** → Apply |
| `06-gpu-oc-300.pcapng` | same → **+300** → Apply |

**Two values per control matters.** With one capture we can see *a* command;
with two we can see which byte changed and by how much, which tells us the
encoding. Guessing that from a single sample is how you end up writing watts
into a field that wanted tenths of a watt.

Note that CPU Power Limit and GPU Overclock only appear when the **Custom**
profile is selected, and only while plugged in.

---

## Reducing the noise

The keyboard streams HID input reports constantly. In Wireshark's display
filter box:

```
usb.transfer_type == 2 && usb.data_len >= 90
```

Control transfers carrying at least 90 bytes. There should be very few — often
just the one you triggered.

If that filter shows nothing, try relaxing it to `usb.transfer_type == 2` and
look for the largest payloads.

To read a packet: select it, expand **Leftover Capture Data** or **HID Data**
in the detail pane, and the bytes are in the hex view. Bytes 7 and 8 of the
90-byte report — remembering the leading `0x00` report-id byte on the wire —
are the class and command id.

---

## What to bring back

Copy the `.pcapng` files to somewhere Linux can read: a USB stick, or a shared
partition.

**Bring them back unparsed.** Do not try to interpret them on Windows. A
decoder on the Linux side will pull out class, id, data size and arguments
from every matching packet and diff the 60 W capture against the 90 W one to
work out the encoding automatically.

If you want to sanity-check before leaving Windows, the only thing worth
confirming is that `00-mode-silent.pcapng` contains a packet with `0d 02` in
it. Everything else can wait.

---

## If you are running Claude Code on Windows

Useful context to hand it:

- The project is **Lucent**, a GTK4/Vala Razer control app for Linux at
  <https://github.com/SoftARV/lucent>
- The protocol summary above is complete and verified on this hardware
- The task is **capture only** — no writes, no probing, no driver work
- The deliverable is the `.pcapng` files; analysis happens on the Linux side
- Wireshark can also export packet bytes as text (`File → Export Packet
  Dissections → As Plain Text`, with *Packet bytes* ticked) if moving binary
  files is awkward — a text dump of the matching packets is just as good

---

## Why this is worth doing

The CPU Power Limit slider is the most valuable of the three. Measurement
showed the boost presets are lopsided: Low → Medium is +580 MHz, Medium →
High is +30 MHz. A three-way preset implies a granularity the hardware does
not have, while a direct 45–95 W control is the same knob without the
pretence.

Undervolt and GPU overclock are features no Linux tool for these machines has
at all.
