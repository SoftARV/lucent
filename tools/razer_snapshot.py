#!/usr/bin/env python3
"""Read-only snapshot of Razer Blade EC state (power, fan, boost, BHO).

Every command here is a read. Nothing is written to the device.

Run it once per condition and diff the log:
    sudo python3 razer_snapshot.py --label after-reboot

Appends one record per run to razer_snapshot.log next to this script, so runs
across unplug / resume / reboot can be compared.
"""
import argparse
import fcntl
import glob
import os
import sys
import time

VID, PID = 0x1532, 0x02C5
DEFAULT_LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "razer_snapshot.log")

POWER_MODES = {0: "Balanced", 1: "Gaming", 2: "Creator", 3: "Silent", 4: "Custom"}
CPU_BOOST = {0: "Low", 1: "Medium", 2: "High", 3: "Boost"}
GPU_BOOST = {0: "Low", 1: "Medium", 2: "High"}
ZONES = {0x01: "CPU", 0x02: "GPU"}


def _iowr(nr, size):
    return 0xC0000000 | (size << 16) | (ord("H") << 8) | nr


HIDIOCSFEATURE = lambda size: _iowr(0x06, size)
HIDIOCGFEATURE = lambda size: _iowr(0x07, size)


def build(command_class, command_id, data_size, args=b""):
    p = bytearray(90)
    p[0] = 0x00      # status: NEW
    p[1] = 0x1F      # transaction id
    p[5] = data_size
    p[6] = command_class
    p[7] = command_id
    p[8 : 8 + len(args)] = args
    crc = 0
    for i in range(2, 88):
        crc ^= p[i]
    p[88] = crc
    return bytes(p)


class Blade:
    def __init__(self, path):
        self.path = path
        self.fd = open(path, "rb+", buffering=0)

    def send(self, command_class, command_id, data_size, args=b"", retries=3):
        """Returns (status, command_id, args[0:8]) or None."""
        report = build(command_class, command_id, data_size, args)
        for _ in range(retries):
            buf = bytearray(91)
            buf[1:] = report
            try:
                fcntl.ioctl(self.fd, HIDIOCSFEATURE(91), bytes(buf))
                time.sleep(0.001)
                resp = bytearray(91)
                fcntl.ioctl(self.fd, HIDIOCGFEATURE(91), resp)
            except OSError:
                time.sleep(0.005)
                continue
            pkt = resp[1:]
            status, rclass, rid = pkt[0], pkt[6], pkt[7]
            # BHO reads answer with a different id than requested
            if (rclass, rid) != (command_class, command_id):
                time.sleep(0.005)
                continue
            return (status, rid, bytes(pkt[8:16]))
        return None

    # --- individual reads -------------------------------------------------
    def bho(self):
        r = self.send(0x07, 0x92, 0x01, b"\x00")
        if not r or r[0] != 0x02:
            return None
        b = r[2][0]
        return bool(b & 0x80), b & 0x7F

    def zone_state(self, zone):
        """(power_mode_byte, manual_fan_flag)"""
        r = self.send(0x0D, 0x82, 0x04, bytes([0x00, zone, 0x00, 0x00]))
        if not r or r[0] != 0x02:
            return None
        return r[2][2], r[2][3]

    def fan_setpoint(self, zone):
        r = self.send(0x0D, 0x81, 0x03, bytes([0x00, zone, 0x00]))
        if not r or r[0] != 0x02:
            return None
        return r[2][2] * 100

    def boost(self, zone):
        r = self.send(0x0D, 0x87, 0x03, bytes([0x00, zone, 0x00]))
        if not r or r[0] != 0x02:
            return None
        return r[2][2]


def find_device():
    for node in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            with open(os.path.join(node, "device", "uevent")) as f:
                text = f.read().upper()
        except OSError:
            continue
        if f"{VID:08X}:{PID:08X}" not in text:
            continue
        path = "/dev/" + os.path.basename(node)
        try:
            dev = Blade(path)
        except OSError:
            continue
        if dev.send(0x07, 0x92, 0x01, b"\x00"):
            return dev
    return None


def read_sysfs(path, default="?"):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", default="", help="tag this run, e.g. 'after-unplug'")
    ap.add_argument("--log", default=DEFAULT_LOG)
    args = ap.parse_args()

    dev = find_device()
    if dev is None:
        sys.exit(f"no responding hidraw node for {VID:04x}:{PID:04x} (need root?)")

    ac = read_sysfs("/sys/class/power_supply/AC0/online")
    cap = read_sysfs("/sys/class/power_supply/BAT0/capacity")
    st = read_sysfs("/sys/class/power_supply/BAT0/status")
    uptime = float(read_sysfs("/proc/uptime", "0").split()[0])

    fields = {}
    bho = dev.bho()
    fields["bho"] = f"{'on' if bho[0] else 'off'}/{bho[1]}%" if bho else "FAILED"

    for zone, zname in ZONES.items():
        zs = dev.zone_state(zone)
        if zs:
            mode, manual = zs
            fields[f"{zname}.mode"] = f"{mode}({POWER_MODES.get(mode, '?')})"
            fields[f"{zname}.fan"] = "manual" if manual else "auto"
        else:
            fields[f"{zname}.mode"] = "FAILED"
            fields[f"{zname}.fan"] = "FAILED"

        sp = dev.fan_setpoint(zone)
        fields[f"{zname}.rpm"] = f"{sp}" if sp is not None else "FAILED"

        bo = dev.boost(zone)
        table = CPU_BOOST if zone == 0x01 else GPU_BOOST
        fields[f"{zname}.boost"] = f"{bo}({table.get(bo, '?')})" if bo is not None else "FAILED"

    print(f"device : {dev.path}")
    print(f"AC     : {'plugged in' if ac == '1' else 'on battery'}   battery {cap}% ({st})")
    print(f"uptime : {uptime / 60:.1f} min")
    if args.label:
        print(f"label  : {args.label}")
    print()
    width = max(len(k) for k in fields)
    for k, v in fields.items():
        flag = "  <-- read failed" if v == "FAILED" else ""
        print(f"  {k:<{width}} : {v}{flag}")

    record = " ".join(f"{k}={v}" for k, v in fields.items())
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    line = (f"{stamp} label={args.label or '-'} ac={ac} bat={cap}% "
            f"uptime={uptime / 60:.1f}m {record}\n")
    with open(args.log, "a") as f:
        f.write(line)
    print(f"\nlogged to {args.log}")


if __name__ == "__main__":
    main()
