# Windows capture results — read this before decoding the .pcapng files

Captured on the actual hardware, 11 Aug 2026.
Razer Blade 14, AMD Ryzen + RTX 5070 Laptop, Windows 11 build 26200,
Razer Synapse 4.0.698.

## Headline result

**None of the three target features are carried over USB HID.**
CPU power limit, CPU voltage offset and GPU clock offset produce no
distinguishing USB traffic whatsoever. There is no class `0x0d` command id
left to find for them, because they are not on this bus.

The capture rig was verified working before and during every one of these
tests, so this is a real negative, not a missed window. Details below.

---

## Setup corrections to WINDOWS-CAPTURE.md

**1. Wireshark no longer bundles USBPcap.** The "tick USBPcap in the components
list" step does not exist in Wireshark 4.6 — it only ships Npcap. USBPcap must
be installed separately from <https://github.com/desowin/usbpcap/releases>
(still 1.5.4.0, May 2020). It *does* load on Windows 11 26200, and capture
works **without administrator rights**.

**2. There is no leading `0x00` report-id byte on the USB wire.** Setup packet:

```
bmRequestType 0x21   bRequest 0x09   wValue 0x0300   wIndex 0x0002   wLength 90
```

`wLength` is exactly 90 and the payload is exactly 90 bytes, so the report
starts at payload offset 0. The report-id byte is a Linux hidraw artefact.
On these captures the offsets are the raw layout with **no +1 shift**:
class at offset 6, id at offset 7. `usb.data_len` is 98 = 8-byte setup + 90.

**3. The transaction id is not fixed at `0x1f`.** Synapse increments it per
command (`0x17`, `0x18`, `0x19`…). Lucent's constant `0x1f` evidently still
works, so the EC does not appear to validate it.

**4. `wIndex` is 2** — the reports go to interface 2.

**5. The payload field in tshark is `usb.data_fragment`**, not `usb.capdata`
(which is empty for these transfers).

---

## Evidence that the three features are not on USB

### CPU power limit — byte-identical traffic for two different values

`01-cpu-power-90.pcapng` (60→90 W) and `02-cpu-power-60.pcapng` (90→60 W) each
contain exactly five non-lighting reports, and the two sets are **identical
across all 80 argument bytes**:

```
0x07 0x12  size=1  d0     <- battery charge limit (0x80 enabled | 0x50 = 80%)
0x07 0x8f  size=1  00
0x07 0x0f  size=1  00
0x07 0x8f  size=1  00
0x07 0x0f  size=1  00
```

Apply *does* fire USB writes at that moment, so the channel was live and being
captured — the value simply is not in them. Neither `0x5a` (90) nor `0x3c` (60)
appears anywhere in either capture.

### CPU undervolt — no write at all

`04-undervolt-25.pcapng` (−10 → −25) contains **68 fan-speed polls and zero
writes**. The `0x0d/0x88` polling ran continuously through the whole file,
proving the capture was reading the device the entire time. Changing the offset
produced no USB traffic of any kind.

(`03-undervolt-10.pcapng` does contain a `0x0d/0x02` write, but that is Synapse
re-asserting the Custom *power mode* on Apply — args `01 01 04`, no voltage
value.)

### GPU overclock — no write at all

`05-gpu-oc-100.pcapng` contains **84 fan-speed polls and zero writes**. Same
reasoning as undervolt.

### Where they actually go

This machine has, all present and running:

| path | evidence |
|---|---|
| `ACPI\PNP0C14\RAZR` | Razer-specific ACPI WMI interface |
| `ACPI\PNP0C14\AOD` | AMD OverDrive ACPI interface |
| `RzDev_02c5.sys`, `RzCommon.sys` | Razer kernel drivers, both Running |

No Razer class is registered in `root\WMI`, so `RzDev_02c5.sys` is driving the
`RAZR` ACPI device directly rather than through the generic WMI mapper.

This is consistent with the hardware: on Ryzen, CPU package power limits
(PPT/STAPM) and voltage offsets are SMU functions reached via ACPI/AOD, not
via the keyboard EC. NVIDIA clock offsets are applied through NVAPI to the
display driver. The keyboard EC owns fans, power *mode* and lighting — a
different subsystem from the power *limit*.

**Implication for Lucent:** these three features need an ACPI/WMI investigation
on the Linux side (`/sys/bus/wmi/`, the DSDT's `RAZR` device, and the
`amd_pmf` / `ryzen_smu` route for the CPU knobs), not more HID work.

---

## Things worth keeping from these captures

### Power mode values (class `0x0d`, id `0x02`) — four confirmed

Observed directly, each by triggering that mode in Synapse and reading the
resulting write:

| mode | value |
|---|---|
| Balanced | `0x03` |
| Custom | `0x04` |
| Silent | `0x05` |
| Battery Saver | `0x06` |

Every one is written twice, once per zone (`0x01` CPU, `0x02` GPU), exactly as
the protocol summary says.

### Argument byte 0 is `01`, not `00` — and it is NOT an AC/battery flag

The doc gives the `0x0d/0x02` args as `[00, zone, mode, manual]`. Synapse sends
`01` in that first byte, consistently, on **every** class `0x0d` command
including the `0x88` fan reads:

```
doc / Lucent :  00  zone  mode  manual
Synapse      :  01  zone  0x03  00
```

**Tested and ruled out:** the obvious hypothesis was that arg[0] selects the
profile (`01` = AC, `00` = battery), matching Synapse's separate "Plugged In"
and "On Battery" profiles. `07-mode-on-battery.pcapng` was captured with the
charger physically unplugged (`Win32_Battery BatteryStatus = 1`, discharging)
and mode switched several times — arg[0] is **still `01`**. So it is a constant,
not a power-source selector. Lucent's `00` and Synapse's `01` evidently both
work, so the EC appears to ignore this byte.

### Fan polling stops on battery

`0x0d/0x88` polling ran continuously in every AC capture with the Performance
page open, and did not appear at all in the battery capture. Minor, but it
means "no `0x88` traffic" is not on its own evidence that a capture is dead.

### `0x07/0x8c` accompanies every mode change

In the battery capture a `0x07/0x8c` read (size 2, args zero) fires immediately
before each `0x0d/0x02` write, three for three. Same command appeared in the AC
mode switch. Whatever it reads, Synapse consults it as part of applying a mode.

### Commands seen that are not in the protocol table

| class | id | size | notes |
|---|---|---|---|
| `0x07` | `0x8c` | 2 | read, args all zero; fires on mode change |
| `0x07` | `0x8f` | 1 | read, arg `00`; paired with `0x0f` |
| `0x07` | `0x0f` | 1 | write, arg `00`; fires twice per Apply |
| `0x03` | `0x0b` | 0x34 | RGB matrix row write, arg[1] = row 0–5 |

`0x07/0x12` confirms the documented charge-limit encoding: observed `0xd0`
= `0x80` (enabled) `| 0x50` (80%).

### Background noise

Synapse streams the Chroma effect as class `0x03` id `0x0b` at ~1.5/sec idle.
When the Performance page is open it also polls `0x0d/0x88` continuously for
both zones. `decode.ps1` hides the lighting by default.

---

## Files

| file | what |
|---|---|
| `00-mode-switch.pcapng` | power mode → Silent. **The Step 1 proof** — contains `0d 02` |
| `01-cpu-power-90.pcapng` | CPU power limit 60 → 90 W |
| `02-cpu-power-60.pcapng` | CPU power limit 90 → 60 W |
| `03-undervolt-10.pcapng` | voltage offset → −10 |
| `04-undervolt-25.pcapng` | voltage offset → −25 |
| `05-gpu-oc-100.pcapng` | GPU clock offset → +100 |
| `07-mode-on-battery.pcapng` | mode switches **on battery**: Battery Saver ↔ Balanced |
| `decode.ps1` | summarises reports in any capture; `-All` to include lighting |
| `capture.ps1` | one-action capture helper |

Capture settings: `\\.\USBPcap1`, all devices on that hub. The Razer composite
device is address `1` there; USBPcap2/3 are empty, USBPcap4 is the camera.

To re-read any file:

```
tshark -r FILE.pcapng -Y "usb.data_fragment" -T fields -e frame.number -e usb.data_fragment
```
