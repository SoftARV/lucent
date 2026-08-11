#!/usr/bin/env python3
"""Measure what lucent-daemon costs: footprint, idle CPU, CPU under a polling
client, and the latency of every exported call.

The numbers recorded in CLAUDE.md came from this. Re-run it after anything that
adds periodic work, because the headline claim -- that an idle daemon is never
scheduled at all -- is exactly the kind of property a stray timer destroys
without anyone noticing.

  ./lucent_benchmark.py footprint          # memory, threads, linked libraries
  ./lucent_benchmark.py idle [seconds]     # CPU with no client attached
  ./lucent_benchmark.py active [seconds]   # CPU while something polls it
  ./lucent_benchmark.py latency            # per-call cost, one exchange at a time
  ./lucent_benchmark.py all

Caveat on the instrument: voluntary_ctxt_switches in /proc/PID/status counts
the main thread only, so it reads zero for a process whose work happens on
other threads. CPU time from /proc/PID/stat is process-wide; trust that one.
"""
import os
import subprocess
import sys
import time

BUS = "dev.miguel.Lucent.Daemon"
OBJ = "/dev/miguel/Lucent/Daemon"
HZ = os.sysconf("SC_CLK_TCK")


def pid_of(name):
    out = subprocess.run(["pgrep", "-x", name], capture_output=True, text=True)
    pids = [int(p) for p in out.stdout.split()]
    return pids[0] if pids else None


def read_stat(pid):
    """utime + stime in seconds, process-wide. The comm field is parenthesised
    and may contain spaces, so split on the last ')' rather than on words."""
    with open("/proc/%d/stat" % pid) as f:
        rest = f.read().rsplit(")", 1)[1].split()
    return (int(rest[11]) + int(rest[12])) / HZ


def read_status(pid, key):
    with open("/proc/%d/status" % pid) as f:
        for line in f:
            if line.startswith(key + ":"):
                return line.split()[1]
    return None


def footprint(pid):
    print("== footprint ==")
    for key in ("VmRSS", "RssAnon"):
        print("  %-12s %s kB" % (key, read_status(pid, key)))
    print("  %-12s %s" % ("Threads", read_status(pid, "Threads")))
    try:
        with open("/proc/%d/smaps_rollup" % pid) as f:
            for line in f:
                if line.split(":")[0] in ("Pss", "Pss_Anon", "Shared_Clean"):
                    print("  %-12s %s" % tuple(line.split(":")[0:1] + [line.split()[1] + " kB"]))
    except OSError:
        pass

    exe = os.path.realpath("/proc/%d/exe" % pid)
    print("  %-12s %d bytes" % ("binary", os.path.getsize(exe)))
    ldd = subprocess.run(["ldd", exe], capture_output=True, text=True).stdout
    gtkish = sum(1 for l in ldd.splitlines()
                 if any(k in l.lower() for k in ("gtk", "adwaita", "pango", "cairo", "gdk")))
    print("  %-12s %d total, %d gtk-ish" % ("shared libs", len(ldd.splitlines()), gtkish))
    if gtkish:
        print("  !! the daemon is linking UI libraries; that is the one thing it must not do")


def cpu_window(pid, seconds, label):
    print("== %s, %d s ==" % (label, seconds))
    c0, v0, t0 = read_stat(pid), int(read_status(pid, "voluntary_ctxt_switches")), time.monotonic()
    time.sleep(seconds)
    if not os.path.isdir("/proc/%d" % pid):
        print("  process vanished mid-window")
        return
    c1, v1, t1 = read_stat(pid), int(read_status(pid, "voluntary_ctxt_switches")), time.monotonic()
    el = t1 - t0
    print("  cpu time      %.3f s  (%.4f%% of one core)" % (c1 - c0, 100 * (c1 - c0) / el))
    print("  vol ctxt sw   %d  (%.1f/s, main thread only)" % (v1 - v0, (v1 - v0) / el))


def latency():
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    def bench(label, method, args=None, sig=None, iface=BUS, n=25):
        ts = []
        for _ in range(n):
            v = GLib.Variant(sig, args) if sig else None
            t = time.perf_counter()
            bus.call_sync(BUS, OBJ, iface, method, v, None, Gio.DBusCallFlags.NONE, -1, None)
            ts.append((time.perf_counter() - t) * 1000)
        ts.sort()
        print("  %-26s median %6.2f ms   min %6.2f   max %6.2f"
              % (label, ts[len(ts) // 2], ts[0], ts[-1]))

    print("== latency ==")
    bench("Ping (bus only)", "Ping", iface="org.freedesktop.DBus.Peer")
    bench("Get Brightness (cached)", "Get", (BUS, "Brightness"), "(ss)",
          iface="org.freedesktop.DBus.Properties")
    bench("RefreshLighting", "RefreshLighting")
    bench("Refresh (full state)", "Refresh")
    # Writes the level back to what it already is, so nothing visibly changes.
    level = bus.call_sync(BUS, OBJ, "org.freedesktop.DBus.Properties", "Get",
                          GLib.Variant("(ss)", (BUS, "Brightness")), None,
                          Gio.DBusCallFlags.NONE, -1, None)[0]
    bench("ApplyBrightness", "ApplyBrightness", (level,), "(u)")
    print("  (ApplyEffect is not benchmarked here: it would overwrite the")
    print("   stored effect, and it is one exchange like any other write)")


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    seconds = int(sys.argv[2]) if len(sys.argv) > 2 else 180

    pid = pid_of("lucent-daemon")
    if pid is None:
        sys.exit("lucent-daemon is not running")
    print("lucent-daemon pid=%d\n" % pid)

    if what in ("footprint", "all"):
        footprint(pid)
        print()
    if what in ("idle", "all"):
        print("  (close the GUI first, or this measures the poll instead)")
        cpu_window(pid, seconds, "idle")
        print()
    if what in ("active", "all"):
        print("  (open the GUI on the Lighting tab first)")
        cpu_window(pid, seconds, "active")
        print()
    if what in ("latency", "all"):
        latency()


if __name__ == "__main__":
    main()
