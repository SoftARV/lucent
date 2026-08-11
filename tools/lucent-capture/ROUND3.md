# Round 3 result — the battery mode mapping, settled

Captured 11 Aug 2026 on battery (68%, charger unplugged, `Win32_Battery
BatteryStatus = 1`). Razer Blade 14, Synapse 4.0.698.

## Answer

| Synapse label (On Battery) | EC value |
|---|---|
| **Battery Saver** | **`0x03`** |
| **Balanced** | **`0x06`** |

**This inverts round 1**, which recorded `0x03` = Balanced and `0x06` = Battery
Saver. Round 1 inferred the mapping from an assumed starting state and got it
backwards. The inverted reading that the Linux measurements suggested is correct.

## Why this is now certain

Two runs with **opposite starting states**, so the first write differs between
them. A wrong mapping cannot survive both.

**Run 1** — `50-battery-balanced-then-saver.pcapng`, started on *Balanced*:

```
0x03  0x06  0x03  0x06  0x03
```

First press was Battery Saver → first write `0x03`.

**Run 2** — `50b-battery-verify.pcapng`, started on *Battery Saver*:

```
0x06  0x03  0x06  0x03  0x06
```

First press was Balanced → first write `0x06`. The sequence inverts exactly as
predicted, which was stated before the capture was decoded.

**End-state check:** run 2 finished on Balanced, and its last write is `0x06`.
This is the same technique that settled Performance on AC — anchoring on a
confirmed final UI state rather than an assumed initial one.

**Independent agreement:** Linux measurement under identical load has `0x03`
sustaining 2461 MHz and `0x06` sustaining 2907 MHz. The slower value being the
saver is the only sensible reading, and it is the one the captures give.

Both writes go to both zones (`0x01` CPU, `0x02` GPU) with the same value, and
`manual` (arg[3]) stayed `0x00` throughout.

## Complete mode table

| Synapse label | EC value | power source |
|---|---|---|
| Balanced | `0x00` | AC |
| Performance | `0x02` | AC |
| Battery Saver | `0x03` | battery |
| Custom | `0x04` | AC |
| Silent | `0x05` | AC |
| Balanced | `0x06` | battery |

Note **"Balanced" is not one value.** It is `0x00` on AC and `0x06` on battery.
A single global label table will mislabel one of them, which is the trap round 1
fell into.

This also resolves the round 2 open question "what is `0x03` on AC" — it is the
Battery Saver value, which is why Synapse enumerates it at startup but never
offers it in the AC profile UI.

## Files

| file | contents |
|---|---|
| `50-battery-balanced-then-saver.pcapng` | run 1, from Balanced: `03 06 03 06 03` |
| `50b-battery-verify.pcapng` | run 2, from Battery Saver: `06 03 06 03 06` |

Capture settings unchanged: `\\.\USBPcap1`, all devices on that hub, no admin.
Decoded with the round 2 filter, which is the correct one:

```
usb.setup.wLength == 90 && usb.bmRequestType == 0x21
```
