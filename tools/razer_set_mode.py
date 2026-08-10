#!/usr/bin/env python3
"""Set the Razer Blade EC power mode. Power mode ONLY.

Deliberately narrow: modes 0-3 only, and the per-zone manual-fan flag is read
back and preserved verbatim, so this can never move the fans off auto. Mode 4
(Custom) is refused because it engages the CPU/GPU boost registers, which this
test does not need.

    sudo python3 razer_set_mode.py 1     # Gaming
    sudo python3 razer_set_mode.py 2     # back to Creator
"""
import argparse
import sys

from razer_snapshot import POWER_MODES, ZONES, Blade, find_device

SAFE_MODES = {0, 1, 2, 3}


def set_power_mode(dev: Blade, zone: int, mode: int, manual_flag: int) -> bool:
    """class 0x0d / id 0x02: [reserved, zone, power_mode, manual_fan_flag]"""
    r = dev.send(0x0D, 0x02, 0x04, bytes([0x00, zone, mode, manual_flag]))
    return bool(r and r[0] == 0x02)


def show(dev, prefix):
    for zone, zname in ZONES.items():
        st = dev.zone_state(zone)
        if st is None:
            print(f"  {prefix} {zname}: read failed")
            continue
        mode, manual = st
        print(f"  {prefix} {zname}: mode={mode}({POWER_MODES.get(mode, '?')}) "
              f"fan={'manual' if manual else 'auto'}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", type=int, help="0 Balanced, 1 Gaming, 2 Creator, 3 Silent")
    args = ap.parse_args()

    if args.mode not in SAFE_MODES:
        sys.exit(f"refusing mode {args.mode}; this tool allows only {sorted(SAFE_MODES)}")

    dev = find_device()
    if dev is None:
        sys.exit("no responding hidraw node (need root?)")

    print(f"device: {dev.path}")
    print("before:")
    show(dev, " ")

    ok = True
    for zone, zname in ZONES.items():
        st = dev.zone_state(zone)
        if st is None:
            print(f"cannot read {zname} zone state; skipping write to avoid guessing the fan flag")
            ok = False
            continue
        _, manual_flag = st
        wrote = set_power_mode(dev, zone, args.mode, manual_flag)
        print(f"write {zname}: mode={args.mode}({POWER_MODES[args.mode]}) "
              f"fan_flag={manual_flag} -> {'ok' if wrote else 'FAILED'}")
        ok &= wrote

    print("after:")
    show(dev, " ")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
