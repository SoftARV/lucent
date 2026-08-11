#!/usr/bin/env python3
"""What are the power modes actually called, and do they differ?

Our names come from rcr's table for older Blades: 0 Balanced, 1 Gaming,
2 Creator, 3 Silent, 4 Custom. Synapse on the 2025 Blade 14 shows Balanced,
Silent, Performance and Custom -- no Gaming, no Creator -- so at least one of
those labels is fiction, and this machine sits on the one we call Creator.

Naming needs Windows. Structure does not, and structure is most of the answer:

  1. which of 0-7 the EC actually accepts, which says how many modes exist
  2. how each behaves, measured, which gives the real ordering

Part 2 holds the machine under constant load and cycles modes, rather than
running a cool-down and load cycle per mode. Thermal state is then shared
across all of them, so differences in fan speed are the mode's doing. That
turns twenty minutes of testing into about one minute per mode.

    python3 razer_mode_profile.py                 # accept-probe only, no load
    python3 razer_mode_profile.py --characterise   # the full run

Restores the mode it started on, whatever happens.
"""
import argparse
import glob
import multiprocessing
import os
import statistics
import sys
import time

from razer_snapshot import POWER_MODES, find_device
from razer_set_mode import set_power_mode

ZONE_CPU, ZONE_GPU = 0x01, 0x02
SETTLE_FRACTION = 0.5


def actual_fan(dev, zone):
    r = dev.send(0x0D, 0x88, 0x03, bytes([0x00, zone, 0x00]), retries=3)
    return r[2][2] * 100 if r and r[0] == 0x02 else None


def cpu_temp():
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            if open(os.path.join(h, "name")).read().strip() != "k10temp":
                continue
            return int(open(os.path.join(h, "temp1_input")).read()) / 1000.0
        except OSError:
            continue
    return None


def cpu_side_state():
    """TLP's settings, which cap achievable clock independently of the power
    mode. Recorded per run so a flattened result can be attributed to the EC
    or to TLP instead of guessed at afterwards."""
    def read(path, default="?"):
        try:
            return open(path).read().strip()
        except OSError:
            return default

    base = "/sys/devices/system/cpu/cpu0/cpufreq/"
    return (f"gov={read(base + 'scaling_governor')} "
            f"epp={read(base + 'energy_performance_preference')} "
            f"boost={read('/sys/devices/system/cpu/cpufreq/boost')} "
            f"max={int(read(base + 'scaling_max_freq', '0')) // 1000}MHz "
            f"ac={read('/sys/class/power_supply/AC0/online')}")


def mean_clock_mhz():
    vals = []
    for f in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq"):
        try:
            vals.append(int(open(f).read()))
        except OSError:
            pass
    return sum(vals) / len(vals) / 1000.0 if vals else None


def _spin(stop_at):
    x = 0
    while time.time() < stop_at:
        for _ in range(100000):
            x = (x * 1103515245 + 12345) & 0x7FFFFFFF


def current_mode(dev):
    st = dev.zone_state(ZONE_CPU)
    return st[0] if st else None


def set_mode(dev, mode):
    for zone in (ZONE_CPU, ZONE_GPU):
        st = dev.zone_state(zone)
        set_power_mode(dev, zone, mode, st[1] if st else 0)
    time.sleep(0.3)


def probe_accepted(dev, original):
    """Which of 0-7 does the EC take? Anything it rejects reads back as
    something else, so the read-back is the whole test."""
    print("=== which mode values does the EC accept? ===")
    accepted = []

    for value in range(8):
        set_mode(dev, value)
        got = current_mode(dev)
        ok = got == value
        known = POWER_MODES.get(value, "unnamed by us")
        print(f"  {value}  ->  reads back {got}   "
              f"{'ACCEPTED' if ok else 'rejected'}   ({known})")
        if ok:
            accepted.append(value)

    set_mode(dev, original)
    return accepted


def measure(dev, mode, seconds):
    set_mode(dev, mode)
    cpu_fans, gpu_fans, temps, clocks = [], [], [], []

    end = time.time() + seconds
    while time.time() < end:
        time.sleep(2)
        cf, gf = actual_fan(dev, ZONE_CPU), actual_fan(dev, ZONE_GPU)
        t, c = cpu_temp(), mean_clock_mhz()
        if cf is not None: cpu_fans.append(cf)
        if gf is not None: gpu_fans.append(gf)
        if t: temps.append(t)
        if c: clocks.append(c)

    keep = lambda xs: xs[int(len(xs) * SETTLE_FRACTION):] or xs
    mean = lambda xs: statistics.mean(keep(xs)) if xs else None
    return {"cpu_fan": mean(cpu_fans), "gpu_fan": mean(gpu_fans),
            "temp": mean(temps), "clock": mean(clocks)}


def characterise(dev, modes, seconds):
    """Forward then reverse. A single pass measures the first mode coolest and
    the last with maximum heat soak, which is exactly the confound that made
    the idle sweep unreadable. Averaging the two directions cancels it."""
    order = list(modes) + list(reversed(modes))

    print(f"\n=== behaviour under constant load, {seconds}s per mode ===")
    print("  Forward then reverse, so ordering drift cancels.")
    print(f"  CPU-side at start: {cpu_side_state()}\n")

    stop_at = time.time() + seconds * len(order) + 40
    workers = [multiprocessing.Process(target=_spin, args=(stop_at,))
               for _ in range(os.cpu_count() or 4)]
    passes = {}

    try:
        for w in workers:
            w.start()

        print("  warming up for 30s ...")
        time.sleep(30)

        for i, mode in enumerate(order):
            leg = "fwd" if i < len(modes) else "rev"
            row = measure(dev, mode, seconds)
            passes.setdefault(mode, []).append(row)
            print(f"  [{leg}] mode {mode} ({POWER_MODES.get(mode, '?'):<8}) "
                  f"cpu fan {row['cpu_fan']:.0f}  gpu fan {row['gpu_fan']:.0f}  "
                  f"{row['temp']:.1f}C  {row['clock']:.0f} MHz")

        print(f"\n  CPU-side at end:   {cpu_side_state()}")
        print("  If this differs from the start line, TLP switched mid-run "
              "and the comparison is void.")
    finally:
        for w in workers:
            w.terminate()
        for w in workers:
            w.join()

    results = []
    for mode, rows in passes.items():
        avg = lambda k: statistics.mean([r[k] for r in rows if r[k] is not None])
        spread = lambda k: (max(r[k] for r in rows) - min(r[k] for r in rows)
                            if len(rows) > 1 else 0)
        results.append({"mode": mode, "cpu_fan": avg("cpu_fan"),
                        "gpu_fan": avg("gpu_fan"), "temp": avg("temp"),
                        "clock": avg("clock"), "clock_spread": spread("clock")})
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--characterise", action="store_true",
                    help="also run load and measure each accepted mode")
    ap.add_argument("--seconds", type=int, default=60, help="per mode")
    args = ap.parse_args()

    dev = find_device()
    if dev is None:
        sys.exit("no responding hidraw node")

    original = current_mode(dev)
    print(f"starting on mode {original} ({POWER_MODES.get(original, '?')})\n")

    try:
        accepted = probe_accepted(dev, original)
        print(f"\n  accepted: {accepted}")

        if not args.characterise:
            print("\n  re-run with --characterise to measure how they differ")
            return

        results = characterise(dev, accepted, args.seconds)

        print("\n=== averaged over both directions, quietest first ===")
        print("  mode          cpu fan  gpu fan    temp     clock   spread")
        for r in sorted(results, key=lambda r: r["clock"]):
            print(f"  {r['mode']} ({POWER_MODES.get(r['mode'], '?'):<8}) "
                  f"{r['cpu_fan']:7.0f}  {r['gpu_fan']:7.0f}  "
                  f"{r['temp']:6.1f}C  {r['clock']:6.0f}  {r['clock_spread']:6.0f}")
        print("\n  spread is the gap between the forward and reverse passes for"
              " that mode.\n  A spread comparable to the differences between "
              "modes means the run is\n  too noisy to separate them.")
    finally:
        set_mode(dev, original)
        print(f"\nrestored mode {original} ({POWER_MODES.get(original, '?')})")


if __name__ == "__main__":
    main()
