#!/usr/bin/env python3
"""Does CPU boost actually do anything? Measure rather than assume.

The register accepts any boost value in any power mode, so reading it back
proves nothing. What a raised power limit should produce is a higher
*sustained* all-core clock under load, with temperature and battery draw
following it. That is what this measures.

    python3 razer_boost_effect.py --mode 4 --levels 0,3
    python3 razer_boost_effect.py --mode 3 --levels 0,3     # is Silent gated?

Each level gets: set boost, cool down, load every core, sample for the run,
average the settled portion. Between levels the machine is allowed back down
to its starting temperature so a hot first run cannot flatter the second.

Package power via RAPL would be the ideal metric but energy_uj is root-only,
so this uses what an unprivileged process can see. Sustained clock is the
strongest of those: if the EC did not raise the limit, the clock cannot rise.
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
from razer_set_boost import CPU_BOOST, set_boost

ZONE_CPU = 0x01
COOLDOWN_MAX = 90
SETTLE_FRACTION = 0.4  # ignore the first 40% of each run


def cpu_temp():
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            if open(os.path.join(h, "name")).read().strip() != "k10temp":
                continue
            return int(open(os.path.join(h, "temp1_input")).read()) / 1000.0
        except OSError:
            continue
    return None


def mean_clock_mhz():
    vals = []
    for f in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq"):
        try:
            vals.append(int(open(f).read()))
        except OSError:
            pass
    return sum(vals) / len(vals) / 1000.0 if vals else None


def battery_watts():
    try:
        i = int(open("/sys/class/power_supply/BAT0/current_now").read())
        v = int(open("/sys/class/power_supply/BAT0/voltage_now").read())
        return i * v / 1e12
    except OSError:
        return None


def _burn(stop_at):
    x = 0
    while time.time() < stop_at:
        for _ in range(100000):
            x = (x * 1103515245 + 12345) & 0x7FFFFFFF
    return x


def cool_down(target):
    start = time.time()
    while time.time() - start < COOLDOWN_MAX:
        t = cpu_temp()
        if t is None or t <= target:
            return t
        time.sleep(2)
    return cpu_temp()


def run_level(dev, mode, level, seconds, cool_target):
    print(f"\n--- CPU boost {level} ({CPU_BOOST.get(level, '?')}) "
          f"in {POWER_MODES.get(mode, '?')} ---")

    if not set_boost(dev, ZONE_CPU, level):
        print("  write not acked; continuing anyway")
    time.sleep(0.2)

    print(f"  cooling to <= {cool_target:.0f}C ...", end="", flush=True)
    print(f" reached {cool_down(cool_target):.1f}C")

    stop_at = time.time() + seconds
    workers = [multiprocessing.Process(target=_burn, args=(stop_at,))
               for _ in range(os.cpu_count() or 4)]
    for w in workers:
        w.start()

    clocks, temps, watts = [], [], []
    while time.time() < stop_at:
        time.sleep(1.0)
        c, t, p = mean_clock_mhz(), cpu_temp(), battery_watts()
        if c: clocks.append(c)
        if t: temps.append(t)
        if p: watts.append(p)

    for w in workers:
        w.join()

    keep = int(len(clocks) * SETTLE_FRACTION)
    settled = lambda xs: xs[int(len(xs) * SETTLE_FRACTION):] or xs

    result = {
        "level": level,
        "clock": statistics.mean(settled(clocks)) if clocks else None,
        "temp": statistics.mean(settled(temps)) if temps else None,
        "watts": statistics.mean(settled(watts)) if watts else None,
    }
    print(f"  sustained clock {result['clock']:.0f} MHz"
          f"   temp {result['temp']:.1f}C"
          + (f"   draw {result['watts']:.1f} W" if result["watts"] else "   (on AC, no draw reading)"))
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", type=int, default=None,
                    help="power mode to hold for the whole run, 0-4")
    ap.add_argument("--levels", default="0,3", help="CPU boost levels to compare")
    ap.add_argument("--seconds", type=int, default=45, help="load duration per level")
    args = ap.parse_args()

    levels = [int(x) for x in args.levels.split(",")]
    for l in levels:
        if l not in CPU_BOOST:
            sys.exit(f"boost level {l} is not one of {sorted(CPU_BOOST)}")

    dev = find_device()
    if dev is None:
        sys.exit("no responding hidraw node")

    if args.mode is not None:
        st = dev.zone_state(ZONE_CPU)
        if st is None:
            sys.exit("cannot read zone state")
        for zone in (0x01, 0x02):
            zs = dev.zone_state(zone)
            set_power_mode(dev, zone, args.mode, zs[1] if zs else 0)
        time.sleep(0.3)

    st = dev.zone_state(ZONE_CPU)
    mode = st[0] if st else -1
    base = cpu_temp() or 50.0
    print(f"mode {mode}({POWER_MODES.get(mode, '?')}), starting temp {base:.1f}C, "
          f"{os.cpu_count()} workers, {args.seconds}s per level")

    results = [run_level(dev, mode, l, args.seconds, base + 3) for l in levels]

    print("\n=== comparison ===")
    for r in results:
        print(f"  boost {r['level']} ({CPU_BOOST[r['level']]:<6}) "
              f"clock {r['clock']:7.0f} MHz   temp {r['temp']:5.1f}C"
              + (f"   {r['watts']:5.1f} W" if r["watts"] else ""))

    if len(results) >= 2 and results[0]["clock"] and results[-1]["clock"]:
        delta = results[-1]["clock"] - results[0]["clock"]
        pct = delta / results[0]["clock"] * 100
        print(f"\n  clock difference: {delta:+.0f} MHz ({pct:+.1f}%)")
        print("  A few percent is noise. A real power-limit change shows up as "
              "tens of percent." if abs(pct) < 5 else
              "  That is well outside noise -- boost is doing something here.")


if __name__ == "__main__":
    main()
