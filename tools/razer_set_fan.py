#!/usr/bin/env python3
"""Set the Razer Blade fans manual or automatic, and report whether it stuck.

    python3 razer_set_fan.py auto      # back to the automatic curve
    python3 razer_set_fan.py 4000      # manual, 4000 RPM on both zones

The open question this answers: razer-ctl refuses manual fan unless the power
mode is Balanced, while rcr sets it in any mode. They cannot both be right for
this hardware, so the script prints the live power mode with the read-back --
run the same write in Silent and again in Balanced and compare.

SAFETY. A manual setpoint can be lower than what the automatic curve would
have chosen, and the EC will not raise it for you. Test upwards first: 4000 is
above the idle curve, so it is audible and cannot cook anything. Only then try
the low end, and go back to auto when finished. There is no tachometer on this
device, so the read-back is the setpoint, not a measurement -- if the fan does
not audibly change, the write did nothing regardless of what it reads.
"""
import argparse
import sys
import time

from razer_snapshot import POWER_MODES, ZONES, Blade, find_device
from razer_set_mode import set_power_mode

RPM_MIN, RPM_MAX = 2200, 5600


def set_manual(dev: Blade, zone: int, manual: int) -> bool:
    """The manual flag shares command 0x0d/0x02 with the power mode, so the
    mode has to be read and written back unchanged."""
    st = dev.zone_state(zone)
    if st is None:
        return False
    mode, _ = st
    return set_power_mode(dev, zone, mode, manual)


def set_rpm(dev: Blade, zone: int, rpm: int) -> bool:
    """class 0x0d / id 0x01: [reserved, zone, rpm/100]"""
    r = dev.send(0x0D, 0x01, 0x03, bytes([0x00, zone, rpm // 100]))
    return bool(r and r[0] == 0x02)


def show(dev):
    mode = None
    for zone, zname in ZONES.items():
        st = dev.zone_state(zone)
        if st is None:
            print(f"  {zname}: read failed")
            continue
        mode, manual = st
        setpoint = dev.fan_setpoint(zone)
        print(f"  {zname}: mode={mode}({POWER_MODES.get(mode, '?')}) "
              f"fan={'manual' if manual else 'auto'} setpoint={setpoint}"
              f"{'  (meaningless while auto)' if not manual else ''}")
    return mode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("target", help=f"'auto', or an RPM between {RPM_MIN} and {RPM_MAX}")
    args = ap.parse_args()

    manual = args.target != "auto"
    rpm = None

    if manual:
        try:
            rpm = int(args.target)
        except ValueError:
            sys.exit(f"expected 'auto' or a number, got {args.target!r}")
        if not RPM_MIN <= rpm <= RPM_MAX:
            sys.exit(f"refusing {rpm} RPM; this model accepts {RPM_MIN}-{RPM_MAX}")

    dev = find_device()
    if dev is None:
        sys.exit("no responding hidraw node")

    print("before:")
    mode = show(dev)

    if not manual:
        print("\nreturning both zones to the automatic curve")
        for zone, zname in ZONES.items():
            print(f"  {zname}: {'ok' if set_manual(dev, zone, 0x00) else 'FAILED'}")
    else:
        print(f"\nsetting both zones to manual at {rpm} RPM")
        for zone, zname in ZONES.items():
            flag = set_manual(dev, zone, 0x01)
            sp = set_rpm(dev, zone, rpm)
            print(f"  {zname}: manual={'ok' if flag else 'FAILED'} "
                  f"setpoint={'ok' if sp else 'FAILED'}")

    time.sleep(0.1)
    print("\nafter:")
    show(dev)

    st = dev.zone_state(0x01)
    if st is None:
        return
    _, now_manual = st

    if manual:
        back = dev.fan_setpoint(0x01)
        if now_manual and back == rpm:
            print(f"\n  STUCK: manual at {rpm} RPM in {POWER_MODES.get(mode, '?')} mode")
            print("  Listen. If the fans did not change, the EC ignored it.")
        else:
            print(f"\n  DID NOT STICK: manual={bool(now_manual)} setpoint={back}")
    else:
        print(f"\n  {'back on auto' if not now_manual else 'STILL MANUAL -- auto did not take'}")


if __name__ == "__main__":
    main()
