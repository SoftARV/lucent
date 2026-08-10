#!/usr/bin/env python3
"""Set the Razer Blade EC CPU/GPU boost, and report whether it stuck.

The open question this answers: rcr's code implies boost only takes effect in
the Custom power mode (4), and that has never been checked on the 2025 model.
So the script prints the live power mode alongside the read-back, letting you
run the same write in Silent and again in Custom and compare.

    python3 razer_set_boost.py show
    python3 razer_set_boost.py cpu 2
    python3 razer_set_boost.py gpu 1

Boost only shifts power limits. It cannot set a fan below its automatic curve,
which is why this is the safer of the two probes.
"""
import argparse
import sys
import time

from razer_snapshot import POWER_MODES, ZONES, Blade, find_device

CPU_BOOST = {0: "Low", 1: "Medium", 2: "High", 3: "Boost"}
GPU_BOOST = {0: "Low", 1: "Medium", 2: "High"}

ZONE_BY_NAME = {"cpu": 0x01, "gpu": 0x02}
LABELS = {0x01: CPU_BOOST, 0x02: GPU_BOOST}


def set_boost(dev: Blade, zone: int, value: int) -> bool:
    """class 0x0d / id 0x07: [reserved, zone, boost]"""
    r = dev.send(0x0D, 0x07, 0x03, bytes([0x00, zone, value]))
    return bool(r and r[0] == 0x02)


def show(dev):
    mode = None
    st = dev.zone_state(0x01)
    if st:
        mode = st[0]
        print(f"  power mode : {mode}({POWER_MODES.get(mode, '?')})"
              f"{'   <-- boost is only expected to apply here' if mode == 4 else ''}")
    for zone, zname in ZONES.items():
        value = dev.boost(zone)
        label = LABELS[zone].get(value, "?") if value is not None else "?"
        print(f"  {zname} boost  : {value}({label})")
    return mode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("zone", choices=["cpu", "gpu", "show"])
    ap.add_argument("value", type=int, nargs="?", default=None)
    args = ap.parse_args()

    dev = find_device()
    if dev is None:
        sys.exit("no responding hidraw node")

    print("before:")
    mode = show(dev)

    if args.zone == "show":
        return

    if args.value is None:
        sys.exit("a value is required, e.g. razer_set_boost.py cpu 2")

    zone = ZONE_BY_NAME[args.zone]
    allowed = LABELS[zone]
    if args.value not in allowed:
        sys.exit(f"refusing {args.value}; {args.zone} accepts {sorted(allowed)}")

    print(f"\nwriting {args.zone} boost = {args.value}({allowed[args.value]})")
    acked = set_boost(dev, zone, args.value)
    print(f"  device acked: {acked}")
    time.sleep(0.05)

    print("\nafter:")
    show(dev)

    read_back = dev.boost(zone)
    if read_back == args.value:
        print(f"\n  STUCK: register holds {args.value} in "
              f"{POWER_MODES.get(mode, '?')} mode")
    else:
        print(f"\n  DID NOT STICK: asked {args.value}, register holds {read_back}")


if __name__ == "__main__":
    main()
