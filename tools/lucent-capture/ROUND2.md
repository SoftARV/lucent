# Round 2 results — mode values, boost, fans, and the reply channel

Captured 11 Aug 2026, Razer Blade 14, Synapse 4.0.698, all on AC unless noted.
Rig as round 1: `\\.\USBPcap1`, all devices on that hub.

---

## 1. The AC power mode table is complete

Every value below was observed directly, from a known starting mode, with the
end state confirmed in the UI.

| Synapse label | EC value | how confirmed |
|---|---|---|
| Balanced | `0x00` | `12-mode-silent`, from a confirmed Performance start |
| Performance | `0x02` | `10-mode-performance`, end state confirmed as Performance |
| Silent | `0x05` | `12-mode-silent`, **and** round 1 — cross-checked |
| Custom | `0x04` | `13-mode-custom`, **and** round 1 |

**The doc's guess was wrong in a specific way.** It said Synapse "does not
appear to use" `0x00`, `0x01`, `0x02`. In fact Balanced is `0x00` and
Performance is `0x02`.

### The battery values are a different set

Round 1 on battery recorded Battery Saver `0x06` and Balanced `0x03`. Silent
reading `0x05` on AC in both rounds proves the AC readings are stable, so the
battery values are genuinely different rather than a misread.

**Unresolved:** what `0x03` means on AC. It is not "Balanced" there — `0x00`
is. But `0x03` *is* a value Synapse knows about: at startup it enumerates
`00, 05, 02, 04, 03` for both zones (see §5). So `0x03` is a real mode that the
AC profile UI does not expose. Worth a dedicated test.

---

## 2. Boost presets — confirmed, and they do NOT write both zones

`0x0d` `0x07` set / `0x87` get, args `[01, zone, level]`.

| level | preset |
|---|---|
| `0x00` | Low |
| `0x01` | Medium |
| `0x02` | High |

All six combinations observed directly (levels 0/1/2 × zones 01/02) across
`20-cpu-low`, `21-cpu-high`, `22-gpu-presets`.

**Correction to the protocol summary:** "Zones … everything is written to both"
is **not true for boost**. Changing the CPU preset writes only zone `0x01`;
changing the GPU preset writes only zone `0x02`. Mode (`0x02`) and fan setpoint
(`0x01`) *are* written to both. Lucent writing both zones on a single-zone
boost change sends a GPU write the user did not ask for.

**Synapse enforces an interlock:** CPU High and GPU High cannot both be set. It
forces the other zone down first. The EC accepts both over HID, so either it
clamps silently or Lucent can create a state Synapse never would — untested
which.

---

## 3. Fan control

### Setpoint encoding confirmed as RPM/100

`0x0d` `0x01` set / `0x81` get, args `[01, zone, rpm/100]`.

| observed | RPM |
|---|---|
| `0x17` | 2300 |
| `0x1e` | 3000 |
| `0x2a` | 4200 |
| `0x2d` | 4500 |
| `0x32` | 5000 |

Two requested values (3000 → `0x1e`, 5000 → `0x32`) confirm the scale rather
than inferring it from one sample.

### The manual-fan flag is arg[3] of the mode command

First time seen non-zero. Enabling Fixed Fan Speed sends:

```
0x0d 0x02   01 01 04 01      <- mode 0x04 (Custom), manual = 1
```

Returning to Auto sends the same with `00`. So the `[01, zone, mode, manual]`
layout is correct, and manual is a flag on the *mode* command, not a separate
command.

Enabling the control also emits an unrequested `0x17` (2300 RPM) before the
requested value — apparently a floor applied on enable.

### Manual Fan Curve is host-side — there is no curve command

**This is the most actionable finding of the round.** `33-fan-curve.pcapng`
contains no new class, no new command id, and no curve upload. Synapse simply
pushes ordinary `0x0d/0x01` setpoints repeatedly, re-asserting mode, manual flag
and boost every few seconds:

```
0x0d 0x02   01 0z 04 01      <- Custom + manual
0x0d 0x01   01 01 16         <- CPU fan 2200 RPM
0x0d 0x01   01 02 14         <- GPU fan 2000 RPM
   ...same values pushed again, repeatedly
```

The EC has no concept of a fan curve. Synapse runs the loop in userspace.

**Consequence:** Lucent does not need a new EC command for fan curves. It can
build the feature today on `0x0d/0x01` (setpoint) plus `0x0d/0x88` (measured
speed) with a polling loop. This is application work, not protocol work.

**Also:** the two zones took *different* values in the same update (`0x16` CPU,
`0x14` GPU). Every earlier fan write sent both zones the same number, so this is
what proves the per-zone argument is genuinely independent.

---

## 4. Every command gets a reply — we were only capturing half the traffic

A single command is **four** USB frames:

1. `SET_REPORT`, `bmRequestType 0x21`, `wLength 90`, `usb.data_len 98` — request
2. URB completion, no data
3. `GET_REPORT`, `bmRequestType 0xa1`, `wLength 90` — setup only, no data
4. **the reply**, `usb.data_len 90`, no `bmRequestType` field at all

Frame 4 carries the answer, with `status = 0x02` (success) at offset 0 and the
same class/id at offsets 6/7. Both SETs and GETs get one; a SET echoes its own
arguments back.

**This matters for the decoder.** The reply frame has no `bmRequestType` and no
`usb.data_fragment` — those only exist on the request. Filtering on either drops
every reply. To read replies, take frames with `usb.data_len == 90` and slice the
raw frame past the USBPcap header (its length is the first two bytes, LE —
28 here). `tshark -T json -x` exposes `frame_raw` for this.

**Consequence:** Lucent can verify that a write succeeded (`status == 0x02`) and
can read back current EC state instead of tracking it locally.

### `0x0d/0x88` returns live fan RPM

The measured-fan-speed read that fills every capture as apparent noise is
carrying real data in its replies, in the same RPM/100 scale as the setpoint:

```
0x0d 0x88   01 01 16     <- CPU fan 2200 RPM
0x0d 0x88   01 01 19     <- 2500 RPM moments later
0x0d 0x88   01 02 16     <- GPU fan 2200 RPM
```

Use `decode-replies.ps1` to see these. This is the read half of the fan-curve
loop described in §3 — setpoint out via `0x0d/0x01`, measured speed back via
`0x0d/0x88`.

---

## 5. What Synapse does at startup (`40-synapse-start.pcapng`)

**It does not trust the EC — it overwrites.** After enumerating, it restores its
own stored configuration: mode `0x04` + manual flag, then boost `01 01 01` and
`01 02 02`, matching what was set before the restart.

**It enumerates every mode.** It writes `00, 05, 02, 04, 03` to both zones in
turn, reading `0x0d/0x83` after each. This is where `0x03` shows up on AC.

### `0x0d/0x83` returns fan limits — genuinely useful

```
size 12 : 00 00 00 00 00 00 17 17 2a 39 39 39
```

Bytes 6–11 are RPM/100: **2300, 2300, 4200, 5700, 5700, 5700**. The `0x17`
matches exactly the floor Synapse applied when enabling fixed fan speed, and
`0x39` = 5700 RPM is a plausible ceiling. So this reads the valid fan range,
which Lucent could use to validate setpoints instead of hard-coding limits.

All five reads returned identical values, so despite being issued once per mode
it does not appear to be mode-specific.

### Newly observed commands

Requests seen, with their replies:

| class | id | size | reply | notes |
|---|---|---|---|---|
| `0x0d` | `0x80` | 80 | `02 01 02 00 …` | large state block |
| `0x0d` | `0x83` | 12 | `… 17 17 2a 39 39 39` | fan limits, see above |
| `0x0d` | `0x89` | 2 | `02 02` | |
| `0x0d` | `0x8a` | 2 | `02 00` | |
| `0x0d` | `0x8b` | 2 | `02 01` | |
| `0x0d` | `0x8e` | 1 | `00` | |
| `0x0d` | `0x8f` | 1 | `00` | |
| `0x07` | `0x8c` | 2 | `0c 0c` | fires before mode changes; constant `0x0c` per zone |
| `0x07` | `0x92` | 1 | `d0` | **charge limit GET** — confirms `0x12`/`0x92` pair |
| `0x07` | `0x0f` / `0x8f` | 1 | `00` | set/get pair, always zero here |
| `0x00` | `0x04` / `0x84` | 2 | `00 00`, `03 00` | |
| `0x00` | `0x86` | 3 | `01 00 00` | |
| `0x00` | `0x87` | 4 | `01 04 00 00` | |
| `0x02` | `0x06` | 2 | `00 00` | |
| `0x0f` | `0x10` / `0x90` / `0x98` | 1 | `01` | |

`0x07/0x12` write observed as `d0` = `0x80` (enabled) `| 0x50` (80%), and
`0x07/0x92` reads back the same — the documented charge-limit encoding is
confirmed in both directions.

---

## 6. Decoder warning — filter on wLength, not data length

A 251-byte Bluetooth control transfer on the same hub decoded as a plausible
looking "class `0x4c` id `0x41`, size 67" before filtering. It is not a Razer
report at all.

The doc's suggested filter `usb.transfer_type == 2 && usb.data_len >= 90` will
catch these. Require instead:

```
usb.setup.wLength == 90 && usb.bmRequestType == 0x21     # requests
usb.data_len == 90                                        # replies
```

`tools/decode_capture.py` needs this guard or it will invent commands.

---

## 7. Files

| file | contents |
|---|---|
| `10-mode-performance.pcapng` | Balanced ↔ Performance ×5 → `02` / `00` |
| `12-mode-silent.pcapng` | Performance → Balanced → Silent → `00`, `05`. Also contains the Balanced write, so no separate `11-` file |
| `13-mode-custom.pcapng` | Silent → Custom → `04` |
| `20-cpu-low.pcapng` | CPU preset Medium → Low |
| `21-cpu-high.pcapng` | GPU → Medium, CPU → High |
| `22-gpu-presets.pcapng` | GPU Low, CPU Medium, GPU High — covers `22-` and `23-` |
| `30-fan-fixed.pcapng` | Fixed fan 3000 then 5000 — covers `30-` and `31-` |
| `32-fan-auto.pcapng` | back to Auto, manual flag clears |
| `33-fan-curve.pcapng` | Manual Fan Curve — no new command |
| `40-synapse-start.pcapng` | full Synapse restart |

Three deviations from the doc's filenames, each combining two actions into one
ordered capture where the sequence makes the encoding unambiguous. Nothing was
skipped.

---

## 8. Still open

- **What `0x03` is on AC.** Synapse enumerates it but the AC UI never selects
  it. Test: on battery, capture each available mode individually.
- **The `0x0d/0x80` 80-byte block.** Only the first three bytes were non-zero
  (`02 01 02`); worth a targeted read while varying one setting at a time.
- **Whether the CPU-High/GPU-High interlock is enforced by the EC** or only by
  Synapse. Lucent can test this directly by setting both and reading back.
- **`0x07/0x8c`** returns `0c 0c` constantly. Class `0x07` otherwise holds
  battery/charge functions, so this is likely a power-source or battery reading.
