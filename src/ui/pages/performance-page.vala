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
    }

    public void shutdown () {
        closing = true;

        if (fan_debounce != 0) {
            Source.remove (fan_debounce);
            fan_debounce = 0;
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
        service.apply_fan.begin (fan_manual_row.active,
                                 (uint) fan_speed.get_value (),
                                 (obj, res) => {
            try {
                service.apply_fan.end (res);
            } catch (Error e) {
                fail (e);
            }
        });
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
