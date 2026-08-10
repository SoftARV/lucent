#!/usr/bin/env python3
"""Set the Razer Battery Health Optimizer (charge limit).

    sudo python3 razer_set_bho.py on 75
    sudo python3 razer_set_bho.py off

The threshold is a single byte: bit 7 is the enable flag, bits 0-6 are the
percentage. Firmware accepts 50-80 only, so anything else is refused here
rather than silently rejected by the device.

The write is always verified by reading the value back, because the device's
acknowledgement for this command class is inconsistent (reads answer with
command id 0x92 rather than echoing 0x12). Read-back is the ground truth.
"""
import argparse
import sys
import time

from razer_snapshot import Blade, find_device

MIN_THRESHOLD, MAX_THRESHOLD = 50, 80


def set_bho(dev: Blade, enabled: bool, threshold: int) -> None:
    """class 0x07 / id 0x12, one arg byte: enabled << 7 | threshold"""
    byte = (0x80 if enabled else 0x00) | threshold
    dev.send(0x07, 0x12, 0x01, bytes([byte]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("state", choices=["on", "off"])
    ap.add_argument("threshold", type=int, nargs="?", default=None,
                    help=f"percent, {MIN_THRESHOLD}-{MAX_THRESHOLD} (required with 'on')")
    args = ap.parse_args()

    enabled = args.state == "on"

    dev = find_device()
    if dev is None:
        sys.exit("no responding hidraw node (need root?)")

    current = dev.bho()
    if current is None:
        sys.exit("could not read current BHO state; refusing to write blind")
    was_on, was_threshold = current
    print(f"before: {'on' if was_on else 'off'} / {was_threshold}%")

    # Turning off keeps the stored threshold, matching how the firmware behaves.
    threshold = args.threshold if args.threshold is not None else was_threshold
    if enabled and args.threshold is None:
        sys.exit("'on' needs an explicit threshold")
    if not MIN_THRESHOLD <= threshold <= MAX_THRESHOLD:
        sys.exit(f"refusing threshold {threshold}; firmware accepts "
                 f"{MIN_THRESHOLD}-{MAX_THRESHOLD}")

    set_bho(dev, enabled, threshold)
    time.sleep(0.05)

    after = dev.bho()
    if after is None:
        sys.exit("write sent but read-back failed")
    now_on, now_threshold = after
    print(f"after : {'on' if now_on else 'off'} / {now_threshold}%")

    if (now_on, now_threshold) == (enabled, threshold):
        print("verified")
        sys.exit(0)
    print(f"MISMATCH: asked for {'on' if enabled else 'off'} / {threshold}%")
    sys.exit(1)


if __name__ == "__main__":
    main()
