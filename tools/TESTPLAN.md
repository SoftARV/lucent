# EC persistence test

Answers one question: **does the Blade's EC hold power mode and the charge
limit on its own, or does something need to reapply them?**

That decides whether Lucent needs a background daemon or can stay a plain GUI
that reads real state on launch.

All commands run from this directory:

```sh
cd ~/Developer/keyboard-controller/tools
```

Every step appends to `razer_snapshot.log`, which lives here and survives
reboots. Read it at any point with `cat razer_snapshot.log`.

## Why these values

We set **Gaming (1)** and **BHO on / 75%** because both are distinct from the
defaults *and* from the current values. If a reading comes back 75, that can
only be our write surviving — 80 was already stored, so testing at 80 would
have been unfalsifiable.

## Steps

Start **plugged in**.

| # | Do this | Then run |
|---|---|---|
| 0 | (nothing — capture the state left by the last reboot) | `sudo python3 razer_snapshot.py --label T0-carryover` |
| 1 | Plug in if you are not already | `sudo python3 razer_snapshot.py --label T1-baseline` |
| 2 | Write both test values | `sudo python3 razer_set_mode.py 1` then `sudo python3 razer_set_bho.py on 75` |
| 3 | (nothing — confirm the writes landed) | `sudo python3 razer_snapshot.py --label T2-after-write` |
| 4 | **Unplug the charger** | `sudo python3 razer_snapshot.py --label T3-unplugged` |
| 5 | Plug back in | `sudo python3 razer_snapshot.py --label T4-replugged` |
| 6 | Suspend, wait a few seconds, resume | `sudo python3 razer_snapshot.py --label T5-after-resume` |
| 7 | **Reboot** | `sudo python3 razer_snapshot.py --label T6-after-reboot` |

Fans audibly ramping at step 2 is a good sign the mode write landed — Gaming
raises the EC power limits and the auto fan curve with them.

## Restore when done

```sh
sudo python3 razer_set_mode.py 2      # back to Creator
sudo python3 razer_set_bho.py off     # keeps the stored threshold
sudo python3 razer_snapshot.py --label T7-restored
```

## Reading the result

For each of `CPU.mode` and `bho`, compare T2 against T3 / T5 / T6:

- **unchanged at T3** — unplugging does not reset it, so no AC-change hook is
  needed and per-AC profiles are a pure preference feature
- **unchanged at T5** — no resume hook needed; rcr's double-reapply after
  wake is defensive, not required
- **unchanged at T6** — the EC stores it in nonvolatile memory, so Lucent
  needs no daemon at all for that setting

Any value that *does* revert names exactly which hook is required, and for
which setting. They can differ: BHO is a BIOS-level setting and is the more
likely of the two to persist.

## Safety notes

- `razer_set_mode.py` accepts modes 0-3 only. Mode 4 (Custom) is refused
  because it engages the CPU/GPU boost registers, which this test does not
  need.
- It reads each zone's manual-fan flag and writes it back unchanged, so it
  cannot move the fans off auto. Nothing here ever sets a manual fan speed.
- `razer_snapshot.py` only ever reads.
- `razer_set_bho.py` clamps to the firmware's 50-80 range and verifies by
  read-back rather than trusting the acknowledgement.

## Measured result

Blade 14 2025 (RZ09-0530, `1532:02c5`), run 2026-08-10. Test values were
Gaming (1) and BHO on / 75%, both chosen to differ from the values already
stored, so a match can only mean the write survived.

| Setting | Unplug | Replug | Suspend/resume | Reboot |
|---|---|---|---|---|
| BHO `on/75` | held | held | held | held |
| Power mode `Gaming` | held | held | **reverted to Creator** | not tested |

Conclusions:

- **BHO persists through everything, including a power cycle.** It is stored
  in EC nonvolatile memory, consistent with it also being a BIOS setting.
  Writing it once is enough — no reapply, no daemon, no stored state.
- **Power mode survives AC transitions but not suspend/resume.** It reverted
  to Creator, the value present before the write, not to the Balanced default
  — so there appear to be two layers, a nonvolatile stored mode and the live
  one that `0x0d/0x02` writes. The EC re-applies from nonvolatile on resume.
- Reboot persistence for power mode was not measured: the value was already
  lost at resume, so the reboot had nothing left to test.
- Per-AC-state profiles are therefore a preference feature only. Nothing
  resets on unplug, so no AC hook is needed for correctness.
- The one hook required is **reapply power mode on resume**.

All six `0x0d` reads (zone state, fan setpoint, boost, per zone) answered
`SUCCESSFUL` on this model. Fans stayed on auto throughout; the boost
registers were never written.

Note that the fan setpoint register reads `2000` even though the model's
documented floor is 2200. Both zones report `fan=auto`, so that register is
stale and unused — rcr's own `read_fan_setting()` returns 0 whenever the
manual flag is clear, for the same reason.
