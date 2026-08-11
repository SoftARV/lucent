#!/usr/bin/env python3
"""Probe the lighting command class directly, bypassing the openrazer daemon.

Read-only by default. Answers two questions the driver source cannot:
which hidraw node serves lighting, and which transaction id it wants.

    python3 razer_light_probe.py
"""
import fcntl
import glob
import os
import sys
import time

VID, PID = 0x1532, 0x02C5


def _iowr(nr, size):
    return 0xC0000000 | (size << 16) | (ord("H") << 8) | nr


HIDIOCSFEATURE = lambda size: _iowr(0x06, size)
HIDIOCGFEATURE = lambda size: _iowr(0x07, size)


def build(cc, cid, size, args=b"", tid=0x1F):
    p = bytearray(90)
    p[1] = tid
    p[5] = size
    p[6] = cc
    p[7] = cid
    p[8:8 + len(args)] = args
    crc = 0
    for i in range(2, 88):
        crc ^= p[i]
    p[88] = crc
    return bytes(p)


def nodes():
    found = []
    for path in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            uevent = open(os.path.join(path, "device/uevent")).read()
        except OSError:
            continue
        # HID_ID=0003:00001532:000002C5 -- the ids are zero padded to 8 digits.
        for line in uevent.splitlines():
            if not line.startswith("HID_ID="):
                continue
            parts = line.split("=", 1)[1].split(":")
            if len(parts) == 3 and int(parts[1], 16) == VID and int(parts[2], 16) == PID:
                found.append("/dev/" + os.path.basename(path))
    return found


def send(fd, cc, cid, size, args=b"", tid=0x1F, retries=3):
    report = build(cc, cid, size, args, tid)
    for _ in range(retries):
        buf = bytearray(91)
        buf[1:] = report
        try:
            fcntl.ioctl(fd, HIDIOCSFEATURE(91), bytes(buf))
            time.sleep(0.002)
            resp = bytearray(91)
            fcntl.ioctl(fd, HIDIOCGFEATURE(91), resp)
        except OSError as e:
            return ("ioctl", str(e), None)
        pkt = resp[1:]
        if (pkt[6], pkt[7]) != (cc, cid):
            time.sleep(0.005)
            continue
        return ("ok", pkt[0], bytes(pkt[8:16]))
    return ("mismatch", None, None)


STATUS = {0: "new", 1: "busy", 2: "OK", 3: "FAILURE", 4: "timeout", 5: "UNSUPPORTED"}

def read_brightness(fd, tid=0x1F):
    kind, st, args = send(fd, 0x0E, 0x84, 0x02, b"\x01", tid)
    return args[1] if kind == "ok" and st == 2 else None


def first_responding(paths):
    for path in paths:
        try:
            fd = open(path, "rb+", buffering=0)
        except OSError:
            continue
        if read_brightness(fd) is not None:
            return path, fd
        fd.close()
    return None, None


if __name__ == "__main__":
    paths = nodes()
    if not paths:
        sys.exit(f"no hidraw node for {VID:04x}:{PID:04x}")

    mode = sys.argv[1] if len(sys.argv) > 1 else "--probe"

    if mode == "--probe":
        print(f"nodes: {', '.join(paths)}\n")
        for path in paths:
            try:
                fd = open(path, "rb+", buffering=0)
            except OSError as e:
                print(f"{path}: cannot open ({e.strerror})")
                continue
            with fd:
                for tid in (0x1F, 0xFF):
                    kind, st, args = send(fd, 0x0E, 0x84, 0x02, b"\x01", tid)
                    if kind == "ok":
                        label = STATUS.get(st, hex(st))
                        extra = f"  brightness={args[1]}" if st == 2 else ""
                        print(f"{path}  tid=0x{tid:02x}  0x0e/0x84 -> {label}{extra}")
                    else:
                        print(f"{path}  tid=0x{tid:02x}  0x0e/0x84 -> {kind} {st or ''}")
        sys.exit(0)

    path, fd = first_responding(paths)
    if fd is None:
        sys.exit("no node answered a read")
    print(f"using {path}")

    with fd:
        if mode == "--brightness-roundtrip":
            # Self-verifying: write, read back, restore. No eyes needed.
            original = read_brightness(fd)
            print(f"  original brightness = {original}")
            for value in (128, 32):
                send(fd, 0x0E, 0x04, 0x02, bytes([0x01, value]))
                time.sleep(0.05)
                got = read_brightness(fd)
                verdict = "match" if got == value else f"MISMATCH (wanted {value})"
                print(f"  wrote {value:3d} -> read {got:3d}   {verdict}")
            send(fd, 0x0E, 0x04, 0x02, bytes([0x01, original]))
            time.sleep(0.05)
            print(f"  restored to {read_brightness(fd)}")

        elif mode == "--static":
            r, g, b = (int(x) for x in sys.argv[2:5])
            kind, st, _ = send(fd, 0x03, 0x0A, 0x04, bytes([0x06, r, g, b]))
            print(f"  static {r},{g},{b} -> {STATUS.get(st, kind)}")

        elif mode == "--spectrum":
            kind, st, _ = send(fd, 0x03, 0x0A, 0x01, bytes([0x04]))
            print(f"  spectrum -> {STATUS.get(st, kind)}")

        else:
            sys.exit(f"unknown mode {mode}")
