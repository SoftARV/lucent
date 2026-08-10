[GtkTemplate (ui = "/dev/miguel/Lucent/performance-page.ui")]
public class Lucent.PerformancePage : Adw.PreferencesPage {

    [GtkChild] private unowned Adw.PreferencesGroup profiles;
    [GtkChild] private unowned Adw.ComboRow ac_row;
    [GtkChild] private unowned Adw.ComboRow battery_row;
    [GtkChild] private unowned Adw.PreferencesGroup fans;
    [GtkChild] private unowned Adw.SwitchRow fan_manual_row;
    [GtkChild] private unowned Adw.PreferencesRow fan_speed_row;
    [GtkChild] private unowned Gtk.Scale fan_speed;
    [GtkChild] private unowned Gtk.Label fan_value;
    [GtkChild] private unowned Adw.PreferencesGroup live;
    [GtkChild] private unowned Adw.ActionRow mode_row;
    [GtkChild] private unowned Adw.ActionRow fan_row;
    [GtkChild] private unowned Adw.ActionRow boost_row;
    [GtkChild] private unowned Adw.PreferencesGroup unavailable;
    [GtkChild] private unowned DaemonNotice notice;

    public signal void report (string message);

    // Row 0 is "Unmanaged"; every row after it is power mode row - 1.
    private const int UNMANAGED = -1;

    private LaptopService service;
    private bool syncing = false;
    private bool closing = false;
    private uint fan_debounce = 0;
    private uint live_poll = 0;

    // Fan speed and temperature move on their own, so the readouts need
    // polling -- but only while this page is actually on screen. The daemon
    // deliberately has no timer, so a closed window costs nothing, and
    // switching to another tab stops the traffic again.
    private const uint LIVE_POLL_SECONDS = 2;

    public void configure (LaptopService service) {
        this.service = service;

        notice.report.connect ((message) => report (message));
        notice.configure (service);

        connect_signals ();

        // Availability is re-evaluated on every change rather than decided
        // once, so starting or restarting the daemon while the window is open
        // fills the page in by itself.
        service.notify.connect (() => sync ());
        sync ();

        map.connect (start_polling);
        unmap.connect (stop_polling);

        if (get_mapped ()) {
            start_polling ();
        }
    }

    public void shutdown () {
        closing = true;
        stop_polling ();

        if (fan_debounce != 0) {
            Source.remove (fan_debounce);
            fan_debounce = 0;
        }
    }

    private void start_polling () {
        if (live_poll != 0 || closing) {
            return;
        }

        live_poll = Timeout.add_seconds (LIVE_POLL_SECONDS, () => {
            if (closing || !get_mapped () || !service.present || !service.available) {
                return Source.CONTINUE;
            }

            service.refresh.begin ((obj, res) => {
                try {
                    service.refresh.end (res);
                } catch (Error e) {
                    // Not worth a toast on a background poll; the values simply
                    // stay where they were.
                }
            });
            return Source.CONTINUE;
        });
    }

    private void stop_polling () {
        if (live_poll != 0) {
            Source.remove (live_poll);
            live_poll = 0;
        }
    }

    private void sync () {
        var usable = service.present && service.available;

        profiles.visible = usable;
        fans.visible = usable;
        live.visible = usable;
        unavailable.visible = !usable;

        if (usable) {
            pull ();
        }
    }

    private void connect_signals () {
        // The models are declared in the template and never rebuilt, so the
        // re-entrant notify::selected trap that bites the lighting page's
        // combos cannot happen here. The guard is still needed to keep pull()
        // from writing back what it just read.
        ac_row.notify["selected"].connect (() => {
            if (!syncing) {
                push (false, ac_row.selected);
            }
        });

        battery_row.notify["selected"].connect (() => {
            if (!syncing) {
                push (true, battery_row.selected);
            }
        });

        fan_manual_row.notify["active"].connect (() => {
            fan_speed_row.sensitive = fan_manual_row.active;
            show_fan ();

            if (!syncing) {
                push_fan ();
            }
        });

        fan_speed.value_changed.connect (() => {
            show_fan ();

            if (!syncing) {
                push_fan ();
            }
        });
    }

    private void pull () {
        syncing = true;

        ac_row.selected = to_row (service.power_mode_ac);
        battery_row.selected = to_row (service.power_mode_battery);

        ac_row.subtitle = service.on_battery ? null : "Active now";
        battery_row.subtitle = service.on_battery ? "Active now" : null;

        fan_manual_row.active = service.fan_manual;
        fan_speed_row.sensitive = service.fan_manual;

        // Only meaningful while manual: on the automatic curve this register
        // holds whatever was last written, so it must never be shown as if it
        // were the current fan speed.
        if (service.fan_manual && service.fan_rpm > 0) {
            fan_speed.set_value (service.fan_rpm);
        }
        show_fan ();

        mode_row.subtitle = ((PowerMode) service.power_mode).title ();
        fan_row.subtitle = describe_fans ();
        boost_row.subtitle = "%s / %s".printf (
            cpu_boost_label (service.cpu_boost),
            gpu_boost_label (service.gpu_boost));

        syncing = false;
    }

    private void push (bool for_battery, uint row) {
        if (row == 0) {
            service.clear_power_mode_for.begin (for_battery, (obj, res) => {
                try {
                    service.clear_power_mode_for.end (res);
                } catch (Error e) {
                    fail (e);
                }
            });
            return;
        }

        service.apply_power_mode_for.begin (for_battery, row - 1, (obj, res) => {
            try {
                service.apply_power_mode_for.end (res);
            } catch (Error e) {
                fail (e);
            }
        });
    }

    // The scale fires continuously while dragged, so writes are coalesced the
    // same way the lighting page does it.
    private void push_fan () {
        if (fan_debounce != 0) {
            Source.remove (fan_debounce);
        }
        fan_debounce = Timeout.add (250, () => {
            fan_debounce = 0;
            send_fan ();
            return Source.REMOVE;
        });
    }

    private void send_fan () {
        // Clamped to the scale's own bounds rather than to constants from
        // src/hid/, which is compiled into the daemon only. The daemon
        // rejects anything outside its range, and a user would read that
        // rejection as an error rather than as a bug in this page.
        var limits = fan_speed.adjustment;
        var rpm = (uint) fan_speed.get_value ().clamp (limits.lower, limits.upper);

        service.apply_fan.begin (fan_manual_row.active, rpm, (obj, res) => {
            try {
                service.apply_fan.end (res);
            } catch (Error e) {
                fail (e);
            }
        });
    }

    // Measured speed, not the setpoint. The EC ramps towards a commanded
    // speed at roughly 40 RPM per second, so these trail a change by a minute
    // or more -- showing the request instead would just be a lie with a
    // number on it.
    private string describe_fans () {
        var cpu = service.fan_actual_cpu;
        var gpu = service.fan_actual_gpu;

        if (cpu == 0 && gpu == 0) {
            return "Stopped";
        }
        return "CPU %u RPM  ·  GPU %u RPM".printf (cpu, gpu);
    }

    private void show_fan () {
        fan_value.label = fan_manual_row.active
            ? "%.0f RPM".printf (fan_speed.get_value ())
            : "Automatic";
    }

    private void fail (Error e) {
        if (!closing) {
            report (e.message);
            pull ();
        }
    }

    private static uint to_row (int mode) {
        return mode == UNMANAGED ? 0 : (uint) (mode + 1);
    }

    // Boost only takes effect in Custom mode, and is read-only here for now.
    private static string cpu_boost_label (uint value) {
        switch (value) {
            case 0: return "Low";
            case 1: return "Medium";
            case 2: return "High";
            case 3: return "Boost";
            default: return "Unknown";
        }
    }

    private static string gpu_boost_label (uint value) {
        switch (value) {
            case 0: return "Low";
            case 1: return "Medium";
            case 2: return "High";
            default: return "Unknown";
        }
    }
}
