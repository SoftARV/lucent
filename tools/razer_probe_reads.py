#!/usr/bin/env python3
"""Hunt for undiscovered read commands, in particular a live fan tachometer.

Synapse displays two changing fan RPMs, so the EC can report actual speed --
we simply have not found the command. The known reads are all `set id | 0x80`
(0x02/0x82, 0x01/0x81, 0x07/0x87), so this sweeps 0x80-0x8f in class 0x0d and
records which ids answer.

Answering is not enough on its own: a stale register answers too. So the sweep
runs twice, with the fans deliberately driven from auto to 5600 in between,
and reports which responses *changed*. A live tachometer must move when the
fans move; stale storage cannot.

    python3 razer_probe_reads.py               # full sweep, spins the fans up
    python3 razer_probe_reads.py --no-fan      # sweep only, fans untouched
    python3 razer_probe_reads.py --watch 88    # sample one id over time

Only ids with the 0x80 bit are sent, and only in class 0x0d, the class this
protocol already speaks. Every known command follows the convention that this
bit means "read", so the risk of writing something by accident is low -- but
it is a convention, not a guarantee, which is why the sweep stays narrow.
"""
import argparse
import multiprocessing
import os
import sys
import time

from razer_snapshot import Blade, find_device

CLASS = 0x0D
IDS = range(0x80, 0x90)
SIZES = (1, 2, 3, 4)
ZONES = (0x00, 0x01, 0x02)

KNOWN = {0x81: "fan setpoint", 0x82: "zone state", 0x87: "boost"}


def _spin(stop_at):
    x = 0
    while time.time() < stop_at:
        for _ in range(100000):
            x = (x * 1103515245 + 12345) & 0x7FFFFFFF
    return x


def burn(seconds):
    stop_at = time.time() + seconds
    workers = [multiprocessing.Process(target=_spin, args=(stop_at,))
               for _ in range(os.cpu_count() or 4)]
    for w in workers:
        w.start()
    return workers


def probe(dev, cid, size, zone):
    """Returns the reply's first 8 arg bytes, or None."""
    r = dev.send(CLASS, cid, size, bytes([0x00, zone, 0x00, 0x00]), retries=2)
    if not r or r[0] != 0x02:
        return None
    return r[2]


def sweep(dev):
    found = {}
    for cid in IDS:
        for size in SIZES:
            for zone in ZONES:
                got = probe(dev, cid, size, zone)
                if got is not None:
                    found[(cid, size, zone)] = got
    return found


def plausible(raw):
    """Flag byte patterns that could be an RPM in the encodings this
    protocol uses elsewhere: RPM/100 (22-56), or a 16-bit raw RPM."""
    hits = []
    for i, b in enumerate(raw):
        if 20 <= b <= 60:
            hits.append(f"[{i}]={b} (~{b * 100} RPM if /100)")
    for i in range(len(raw) - 1):
        for label, v in (("LE", raw[i] | (raw[i + 1] << 8)),
                         ("BE", (raw[i] << 8) | raw[i + 1])):
            if 1500 <= v <= 7000:
                hits.append(f"[{i}:{i+2}]{label}={v} RPM")
    return hits


def show(found, title):
    print(f"\n=== {title}: {len(found)} responding combinations ===")
    for (cid, size, zone), raw in sorted(found.items()):
        note = f"  <- known: {KNOWN[cid]}" if cid in KNOWN else ""
        print(f"  0x{cid:02x} size={size} zone={zone}  {raw.hex(' ')}{note}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-fan", action="store_true",
                    help="sweep once at idle and stop; nothing is loaded")
    ap.add_argument("--load", type=int, default=90,
                    help="seconds of all-core load used to make the EC ramp the fans")
    ap.add_argument("--watch", type=lambda s: int(s, 16), default=None,
                    help="sample one command id repeatedly, hex")
    ap.add_argument("--seconds", type=int, default=20)
    args = ap.parse_args()

    dev = find_device()
    if dev is None:
        sys.exit("no responding hidraw node")

    if args.watch is not None:
        print(f"sampling 0x{args.watch:02x} every 2s for {args.seconds}s")
        for _ in range(max(1, args.seconds // 2)):
            row = []
            for size in SIZES:
                got = probe(dev, args.watch, size, 0x01)
                row.append(f"size={size}:{got.hex(' ') if got else '-'}")
            print("  " + "   ".join(row))
            time.sleep(2)
        return

    before = sweep(dev)
    show(before, "idle, fans on auto")

    if args.no_fan:
        return

    # Load rather than writes. Driving the fans by setting a manual speed
    # would change 0x81 and 0x82 because *we* changed them, which tells us
    # nothing. Heating the CPU makes the EC ramp the fans on its own, so
    # every difference below is the firmware's doing, not ours.
    print(f"\nloading all cores for {args.load}s so the EC ramps the fans itself ...")
    workers = burn(args.load)
    time.sleep(args.load * 0.7)
    under_load = sweep(dev)
    for w in workers:
        w.join()

    changed = {k: (before.get(k), v)
               for k, v in under_load.items() if before.get(k) != v}

    print(f"\n=== responses the EC changed by itself: {len(changed)} ===")
    if not changed:
        print("  none. Nothing in this range tracks fan speed or temperature.")
        return

    for (cid, size, zone), (was, now) in sorted(changed.items()):
        note = f"  <- known: {KNOWN[cid]}" if cid in KNOWN else "  <- CANDIDATE"
        print(f"  0x{cid:02x} size={size} zone={zone}{note}")
        print(f"      idle  {was.hex(' ') if was else '-'}")
        print(f"      load  {now.hex(' ')}")
        for h in plausible(now):
            print(f"      {h}")


if __name__ == "__main__":
    main()
