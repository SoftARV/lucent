[GtkTemplate (ui = "/dev/miguel/Lucent/performance-page.ui")]
public class Lucent.PerformancePage : Adw.PreferencesPage {

    [GtkChild] private unowned Adw.PreferencesGroup profiles;
    [GtkChild] private unowned Adw.ComboRow ac_row;
    [GtkChild] private unowned Adw.ComboRow battery_row;
    [GtkChild] private unowned Adw.PreferencesGroup live;
    [GtkChild] private unowned Adw.ActionRow mode_row;
    [GtkChild] private unowned Adw.ActionRow fan_row;
    [GtkChild] private unowned Adw.ActionRow boost_row;
    [GtkChild] private unowned Adw.PreferencesGroup unavailable;
    [GtkChild] private unowned Adw.StatusPage status;

    public signal void report (string message);

    // Row 0 is "Unmanaged"; every row after it is power mode row - 1.
    private const int UNMANAGED = -1;

    private LaptopService service;
    private bool syncing = false;
    private bool closing = false;

    public void configure (LaptopService service) {
        this.service = service;

        connect_signals ();

        // Availability is re-evaluated on every change rather than decided
        // once, so starting or restarting the daemon while the window is open
        // fills the page in by itself.
        service.notify.connect (() => sync ());
        sync ();
    }

    public void shutdown () {
        closing = true;
    }

    private void sync () {
        var usable = service.present && service.available;

        profiles.visible = usable;
        live.visible = usable;
        unavailable.visible = !usable;

        if (usable) {
            pull ();
            return;
        }

        status.description = service.present
            ? "The daemon is running but cannot reach the keyboard.\n\n"
              + "Its udev rule is probably not installed."
            : "lucent-daemon is not running.\n\n"
              + "systemctl --user enable --now lucent-daemon";
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
    }

    private void pull () {
        syncing = true;

        ac_row.selected = to_row (service.power_mode_ac);
        battery_row.selected = to_row (service.power_mode_battery);

        ac_row.subtitle = service.on_battery ? null : "Active now";
        battery_row.subtitle = service.on_battery ? "Active now" : null;

        mode_row.subtitle = ((PowerMode) service.power_mode).title ();
        fan_row.subtitle = service.fan_rpm == 0
            ? "Automatic"
            : "%u RPM".printf (service.fan_rpm);
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
