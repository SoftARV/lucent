# EC persistence test

Answers one question: **does the Blade's EC hold power mode and the charge
limit on its own, or does something need to reapply them?**

That decides whether Lucent needs a background daemon or can stay a plain GUI
that reads real state on launch.

All commands run from this directory:

```sh
cd ~/Developer/keyboard-controller/tools
```

## Close Lucent before measuring anything

Step zero, and it has already invalidated two runs here. The window polls the
device every two seconds while the Performance page is open, and any click on
a control writes to it. A mode sweep run with the app open produced readings
that were really someone dragging the fan slider.

```sh
pgrep -af '/usr/bin/lucent$' || echo "clear"
```

Check the daemon journal afterwards too: `fan set to`, `power mode set to`
lines during your test window mean something else was writing.

Background CPU load is the other one. Anything measuring clocks or fan speed
needs an otherwise idle machine, and a stray load generator left running is
invisible unless you look for it.

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

## Mode characterisation results, plugged in

Constant all-core load, 50s per mode, one forward pass, 2026-08-11.

| group | modes | sustained clock | fan |
|---|---|---|---|
| high | 1, 2, 4 | 3554 / 3558 / 3556 MHz | 5300-5700 |
| medium | 0 | 3229 MHz | 3454 |
| low | 3, 5, 6 | 2900 / 2895 / 2878 MHz | 3400-4100 |
| odd | 7 | 3025 MHz at 96.8C, near-max fan | 5692 |

**There are three power levels, not eight modes.** Clocks within a group land
within 5 MHz of each other while the gaps between groups exceed 300 MHz, which
is far too tight a clustering to be thermal noise.

So **1 and 2 are the same mode** -- we offer them as "Gaming" and "Creator"
and they are measurably identical -- and **3, 5 and 6 are one mode**. Only 0
is genuinely in the middle, and it is the one label we can now call certain.
Mode 7 looks like an invalid value producing undefined behaviour rather than a
mode: highest temperature of the run and near-max fan for a middling clock.

Caveats. Single forward pass, so mode 0 was measured coolest and mode 7 with
maximum heat soak: the *clock* groupings survive that, the temperatures do
not. Mode 4 also had CPU boost left raised from an earlier test, so its clock
is not purely the mode's doing.

## Mode characterisation results, on battery

Same protocol, unplugged. TLP was verified to be in the same state for both
runs -- `gov=powersave epp=balance_performance` plugged in and unplugged alike,
because the explicit `CPU_ENERGY_PERF_POLICY` lines are commented out and
TLP's own default is `balance_performance` for AC. So the only variable
between the two runs was the power source.

| mode | clock on AC | clock on battery |
|---|---|---|
| 1, 2, 4 (high) | ~3555 MHz | **~2910 MHz** |
| 0 Balanced | 3229 MHz | 2922 MHz |
| 3 Silent | 2890 MHz | **2459 MHz** |
| 5, 6 | ~2890 MHz | ~2895 MHz |
| 7 | 3025 MHz | 2510 MHz |

**The firmware restricts power modes on battery.** The high group loses about
650 MHz and lands exactly on Balanced, so unplugged there are only two
distinguishable behaviours: normal (Balanced, Performance and Custom are all
the same thing) and reduced (Silent). That is precisely the Balanced plus
Battery Saver pair Synapse offers on battery, which makes its two-mode battery
UI honest rather than policy.

Note that Lucent currently offers every mode on battery, so three of those
choices do nothing.

Modes 5 and 6 sat with Silent on AC and with Balanced on battery. A real mode
does not change group with the power source; this is more evidence they are
aliases rather than modes.

Caveat: one forward pass per run, and the AC run's EPP was reconstructed
afterwards rather than recorded. The tool now prints the CPU-side state at the
start and end of every run so that cannot happen again.

## Cross-OS tests: naming, reboot survival, and who owns the register

### First: stop our own daemon from writing

This is not optional. `try_open()` calls `restore()` at startup, so on the way
back from Windows the daemon rewrites the stored profile before anything can
read what the EC was holding — the reading would just be our own setting. It
also writes on resume and on AC change.

Setting both profiles to Unmanaged makes `restore()` return early, so the
daemon runs normally and simply never touches the power mode:

Written out in full rather than through a shell variable: zsh does not
word-split an unquoted parameter, so `$D ClearPowerModeFor ...` is read as one
very long command name and fails.

```sh
busctl --user call dev.miguel.Lucent.Daemon /dev/miguel/Lucent/Daemon \
  dev.miguel.Lucent.Daemon ClearPowerModeFor b true
busctl --user call dev.miguel.Lucent.Daemon /dev/miguel/Lucent/Daemon \
  dev.miguel.Lucent.Daemon ClearPowerModeFor b false

busctl --user get-property dev.miguel.Lucent.Daemon /dev/miguel/Lucent/Daemon \
  dev.miguel.Lucent.Daemon PowerModeAc
busctl --user get-property dev.miguel.Lucent.Daemon /dev/miguel/Lucent/Daemon \
  dev.miguel.Lucent.Daemon PowerModeBattery
```

Both must read `-1` before you reboot. Restore afterwards with
`ApplyPowerModeFor bu false 2` and `ApplyPowerModeFor bu true 3`, or whatever
your profiles were.

Keep Lucent's window closed throughout: touching the mode combo writes.

### Then: separate "survives a reboot" from "Synapse reads it"

Test 1 below conflates two questions. Do this one first, because it removes a
variable from everything after it:

```sh
python3 razer_set_mode.py 3        # Silent, distinct from the usual
python3 razer_snapshot.py --label before-linux-reboot
# reboot into Linux, then:
python3 razer_snapshot.py --label after-linux-reboot
```

If the mode comes back as 3, it survives a reboot and the cross-OS tests mean
something. If it reverts, the mode is volatile like it is across suspend, and
neither Windows test can tell us anything about naming — they would only ever
show the EC's nonvolatile default.

Three open questions, and they overlap enough that two reboots answer all of
them. Record the mode number before each reboot with `razer_snapshot.py`.

**Does the mode survive a reboot at all?** We know it is dropped across
suspend, reverting to whatever the EC holds. Reboot was never tested, because
the value was already gone by the time we looked.

**What are the modes really called?** Our labels come from rcr's table for
older Blades. Synapse on this model shows Balanced, Silent, Performance and
Custom plugged in, and Balanced plus Battery Saver on battery -- no Gaming, no
Creator, though we call mode 2 Creator and this machine sits on it.

**Do Linux and Windows write the same register?** If Synapse reads back what
we set from Linux, the two are talking to the same place and can be reasoned
about together. If not, one of them keeps its own copy somewhere else and the
comparison is meaningless.

### Establishing the label mapping, one trip per label

A write from Synapse survives a reboot where a write from Linux does not, so
each Windows visit yields one confirmed mapping. Neuter the daemon once, at
the start, and leave it that way for the whole series -- otherwise it rewrites
the mode at startup and every reading is just our own stored profile.

For each label: boot Windows, set that profile in Synapse, reboot to Linux,
and read **before opening Lucent**:

```sh
python3 razer_snapshot.py --label synapse-<label>
```

| Synapse label | source | read back | verdict |
|---|---|---|---|
| Performance | plugged in | 2 | **void** -- slot already held 2, profile already Performance |
| Battery Saver | on battery | 6 | **void** -- slot already held 6, profile already Battery Saver |
| Balanced | plugged in | 2 | unchanged from before; either Balanced is 2 or nothing committed |
| Silent | plugged in | ? | **do this one** -- must differ from 2, so it is falsifiable |
| Custom | plugged in | ? | |
| Balanced | on battery | ? | may differ from the AC one |

**Every reading so far is unfalsifiable.** Both "confirmations" set a profile
that was already selected, into a slot that already held the value we then
read back. The rule at the top of this file exists for exactly this and was
not applied. Pick a label whose value must differ from what is stored, and
spend a few minutes in Windows before shutting down in case the commit is
lazy.

The per-source storage means a label can map to different values depending on
which tab it was set from, so Balanced is worth testing on both. Battery Saver
being 6 rather than 3 is the precedent: it is a value we had written off as
unnamed.

Note the tension with the behavioural data. On battery mode 6 clocked 2891 MHz
while Silent (3) clocked 2459, so the "saver" runs faster than Silent. Either
it saves through the GPU, display or platform rather than CPU clock, or one of
those measurements is off.

Battery Saver is the one worth doing even if the others are skipped. The other
three are tightly constrained by behaviour already -- Custom is the only mode
where boost controls appear, Silent the only one that differs on battery,
Balanced the measured middle level -- but Battery Saver could be our 3 wearing
another name, or a value our enum does not have at all. Behaviour cannot
distinguish those, because 3 is the only mode that differs on battery either
way.

For the battery one, set Synapse's On Battery profile, then **unplug before
rebooting** so that profile is the active one.

### Test 1 — Linux to Windows

Plugged in, from Linux:

```sh
python3 razer_set_mode.py 3          # Silent, distinct from the usual 2
python3 razer_snapshot.py --label before-windows
```

Reboot into Windows, open Synapse's Performance tab, and note **which mode is
highlighted** on the Plugged In tab.

- highlighted as Silent — same register, mode survives a reboot, and mode 3 is
  confirmed as Silent
- highlighted as something else — that name is what 3 really is
- nothing highlighted, or a default like Balanced — either the mode did not
  survive, or Synapse keeps its own copy; the next test separates those

Then check the **On Battery** tab without unplugging. Synapse keeps a separate
profile per power source, exactly as Lucent does. If it shows a different mode
there, Synapse is a software layer over a single EC value, like our daemon,
rather than the EC storing one mode per source.

### Test 2 — Windows to Linux

Still in Windows, set the Plugged In profile to **Performance**, the label we
most likely have wrong. Reboot into Linux:

```sh
python3 razer_snapshot.py --label after-windows
```

Whatever number comes back is Performance. That one reading anchors the
mapping, since Balanced, Silent and Custom are consistent across Synapse, rcr
and razer-ctl, and 0, 3 and 4 are near-certain already.

### Test 3 — the same on battery

Repeat test 1 unplugged. Synapse only offers Balanced and Battery Saver on
battery, but we have already shown the EC accepts any mode unplugged, so a
mode Synapse cannot select may still be sitting there. What Synapse displays
when the EC holds a mode outside its own list is worth seeing.

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
