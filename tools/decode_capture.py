#!/usr/bin/env python3
"""Decode Razer feature reports out of a USBPcap capture.

    python3 decode_capture.py FILE.pcapng           # writes and unknown reads
    python3 decode_capture.py FILE.pcapng --all     # include lighting and polls

Needs tshark. On the USB wire there is no leading report-id byte -- that is a
Linux hidraw artefact -- so the 90-byte report starts at payload offset 0 and
the class and id sit at offsets 6 and 7 with no shift.
"""
import argparse
import subprocess
import sys
from collections import Counter

# class, id -> what it is. Read ids are set id | 0x80.
KNOWN = {
    (0x0D, 0x02): "power mode + manual-fan flag  (write)",
    (0x0D, 0x82): "power mode + manual-fan flag  (read)",
    (0x0D, 0x01): "fan setpoint                  (write)",
    (0x0D, 0x81): "fan setpoint                  (read)",
    (0x0D, 0x07): "cpu/gpu boost                 (write)",
    (0x0D, 0x87): "cpu/gpu boost                 (read)",
    (0x0D, 0x88): "measured fan speed            (read)",
    (0x07, 0x12): "charge limit                  (write)",
    (0x07, 0x92): "charge limit                  (read)",
    (0x03, 0x0B): "rgb matrix row                (write)",
    (0x03, 0x0A): "rgb effect                    (write)",
}

NOISE = {(0x03, 0x0A), (0x03, 0x0B), (0x0D, 0x88)}

# Captured from Synapse. The two power sources use different value sets: on AC
# Balanced is 0x00, on battery it is 0x03. Anything not listed is a value the
# EC accepts but Synapse was never seen to send.
MODES_AC = {0x00: "Balanced", 0x02: "Performance", 0x04: "Custom", 0x05: "Silent"}
MODES_BAT = {0x03: "Balanced", 0x06: "Battery Saver"}


def mode_name(value):
    ac = MODES_AC.get(value)
    bat = MODES_BAT.get(value)
    if ac and bat:
        return f"{ac} on AC / {bat} on battery"
    return ac or (bat + " (battery)" if bat else "not used by Synapse")


def reports(path):
    # Filtering on data length alone catches unrelated traffic on the same
    # hub: a 251-byte Bluetooth control transfer decodes as a plausible
    # "class 0x4c id 0x41" and invents a command that does not exist.
    # Require the Razer setup packet exactly.
    out = subprocess.run(
        ["tshark", "-r", path,
         "-Y", "usb.setup.wLength == 90 && usb.bmRequestType == 0x21",
         "-T", "fields", "-e", "frame.number", "-e", "usb.data_fragment"],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(out.stderr.strip() or "tshark failed")

    for line in out.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) != 2 or not parts[1]:
            continue
        raw = bytes.fromhex(parts[1].replace(":", ""))
        if len(raw) < 90:
            continue
        yield int(parts[0]), raw


def describe(cls, cid, size, args):
    name = KNOWN.get((cls, cid), "UNKNOWN")
    note = ""
    if (cls, cid) in ((0x0D, 0x02),) and size >= 3:
        note = f"   zone={args[1]} mode=0x{args[2]:02x} ({mode_name(args[2])})"
        if size >= 4:
            note += f" manual={args[3]}"
    elif (cls, cid) in ((0x0D, 0x07),) and size >= 3:
        note = f"   zone={args[1]} level={args[2]}"
    elif (cls, cid) == (0x07, 0x12) and size >= 1:
        note = f"   enabled={bool(args[0] & 0x80)} percent={args[0] & 0x7f}"
    return name, note


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("capture")
    ap.add_argument("--all", action="store_true", help="include lighting and fan polls")
    args_cli = ap.parse_args()

    seen = Counter()
    shown = 0

    for frame, raw in reports(args_cli.capture):
        status, txn, size, cls, cid = raw[0], raw[1], raw[5], raw[6], raw[7]
        args = raw[8:8 + max(size, 4)]
        seen[(cls, cid)] += 1

        if not args_cli.all and (cls, cid) in NOISE:
            continue

        name, note = describe(cls, cid, size, args)
        print(f"  #{frame:<5} txn=0x{txn:02x} {cls:#04x}/{cid:#04x} size={size:<3} "
              f"{args[:6].hex(' '):<18} {name}{note}")
        shown += 1

    if shown == 0:
        print("  (nothing but lighting and polls; re-run with --all)")

    print("\n  totals:")
    for (cls, cid), n in sorted(seen.items()):
        print(f"    {cls:#04x}/{cid:#04x}  x{n:<5} {KNOWN.get((cls, cid), 'UNKNOWN')}")


if __name__ == "__main__":
    main()
