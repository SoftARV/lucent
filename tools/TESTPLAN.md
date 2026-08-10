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

## Constraint tests: does boost or manual fan depend on the power mode?

Two claims from the reference projects, neither verified on this model, and
they cannot both be right:

- rcr implies **boost only takes effect in Custom** (mode 4)
- razer-ctl refuses **manual fan unless the mode is Balanced** (mode 0)

These decide the UI. If manual fan is Balanced-only, the control has to be
disabled elsewhere with an explanation rather than offered as a free slider.

**What these tests can and cannot show.** They measure whether the register
holds the value you wrote, which is falsifiable and quick. They do *not* show
whether it has any effect on power limits — that needs sustained load and a
power measurement. For the fan there is a better signal: no tachometer exists,
so if the fans do not audibly change, the write did nothing regardless of what
reads back.

### Boost

```sh
python3 razer_set_mode.py 3      # Silent
python3 razer_set_boost.py cpu 2 # note STUCK / DID NOT STICK
python3 razer_set_mode.py 4      # Custom
python3 razer_set_boost.py cpu 3 # note again
python3 razer_set_mode.py 2      # restore Creator
```

### Fan

Use **5600**, the maximum. Not 4000: a mid-range value is audible either way
and cannot be told apart from the normal curve by ear, which is how the first
run of this test produced an unusable answer. The maximum is also the safest
possible setpoint, since more cooling is never a thermal risk.

Judge it by A/B, not by absolute impression. Run auto, listen, then manual,
listen. The difference at 5600 is unmistakable.

```sh
python3 razer_set_mode.py 3      # Silent
python3 razer_set_fan.py auto    # listen: this is the baseline
python3 razer_set_fan.py 5600    # listen: unmistakable, or nothing happened
python3 razer_set_fan.py auto

python3 razer_set_mode.py 4      # Custom -- the likeliest candidate
python3 razer_set_fan.py 5600    # listen
python3 razer_set_fan.py auto
python3 razer_set_mode.py 2      # restore Creator
```

Leave the fans on auto when finished. A manual setpoint is not raised by the
EC when the machine heats up.

### Constraint results, Blade 14 2025

**Manual fan works, with no mode gating.** Confirmed by ear, A/B against auto,
in Creator and Silent, on both AC and battery. razer-ctl's rule that manual
fan requires Balanced does **not** apply to this model; rcr's "any mode" is
correct here. Do not copy razer-ctl's restriction.

At 5600 the change is clearly audible but far from a gaming roar -- expect a
whoosh, not a jet. Without a tachometer this only shows the fan responds to
the setpoint, not that it reaches the number written.

**Boost is unresolved and this method cannot resolve it.** The register holds
the written value in Silent *and* in Custom, so the read-back cannot tell the
two apart. Whether Custom is the only mode that acts on it needs sustained
load and a power measurement, not a register probe. Until that exists, treat
"boost applies only in Custom" as rcr's claim rather than a measured fact.

**Manual fan does not survive suspend, and neither does boost.** Measured
across a real suspend: both zones came back on `auto`, and CPU boost fell from
3 (Boost) to 1 (Medium). The manual flag shares a register with the power
mode, which is already known to revert, so this follows.

Treat that as a safety net rather than a bug to fix. A manual fan speed the
firmware forgets is one the user cannot leave dangerously low by accident, so
Lucent should not reapply it on resume. Boost is the opposite: if it is ever
exposed, it needs restoring like the power mode or it silently evaporates.

**Anomaly worth chasing before the fan readout is designed.** After that
resume, `CPU.rpm` read 4200 -- a value never written by us, while `GPU.rpm`
still held our stale 5600. If the CPU zone's setpoint register tracks the EC's
live target while on auto, it is a real readout rather than dead storage.
Test by taking several snapshots a minute apart on auto and watching whether
it moves by itself.

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
