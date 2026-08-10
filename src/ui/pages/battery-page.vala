[GtkTemplate (ui = "/dev/miguel/Lucent/battery-page.ui")]
public class Lucent.BatteryPage : Adw.PreferencesPage {

    [GtkChild] private unowned Adw.ActionRow level_row;
    [GtkChild] private unowned Adw.PreferencesGroup limits;
    [GtkChild] private unowned Adw.SwitchRow limit_row;
    [GtkChild] private unowned Adw.SpinRow threshold_row;
    [GtkChild] private unowned Adw.PreferencesGroup unavailable;
    [GtkChild] private unowned Adw.StatusPage status;

    public signal void report (string message);

    private LaptopService service;
    private bool syncing = false;
    private bool closing = false;
    private uint debounce = 0;
    private uint level_poll = 0;

    public void configure (LaptopService service) {
        this.service = service;

        connect_signals ();

        // Availability is re-evaluated on every change rather than decided
        // once, so starting or restarting the daemon while the window is open
        // fills the page in by itself.
        service.notify.connect (() => sync ());
        sync ();

        show_level ();

        // The kernel does not signal capacity changes, so this is the one
        // thing here that has to be polled. Slowly: it moves by a percent
        // every few minutes at best.
        level_poll = Timeout.add_seconds (30, () => {
            show_level ();
            return Source.CONTINUE;
        });
    }

    public void shutdown () {
        closing = true;

        if (debounce != 0) {
            Source.remove (debounce);
            debounce = 0;
        }
        if (level_poll != 0) {
            Source.remove (level_poll);
            level_poll = 0;
        }
    }

    private void sync () {
        var usable = service.present && service.available;

        limits.visible = usable;
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
        limit_row.notify["active"].connect (() => {
            threshold_row.sensitive = limit_row.active;
            if (!syncing) {
                push ();
            }
        });

        threshold_row.notify["value"].connect (() => {
            if (!syncing) {
                push ();
            }
        });
    }

    private void pull () {
        syncing = true;
        limit_row.active = service.charge_limit_enabled;
        threshold_row.value = service.charge_limit_threshold;
        threshold_row.sensitive = service.charge_limit_enabled;
        syncing = false;
    }

    // The spin row fires per click, so writes are coalesced the same way the
    // lighting page does it.
    private void push () {
        if (debounce != 0) {
            Source.remove (debounce);
        }
        debounce = Timeout.add (250, () => {
            debounce = 0;
            send ();
            return Source.REMOVE;
        });
    }

    private void send () {
        service.apply_charge_limit.begin (limit_row.active,
                                          (uint) threshold_row.value,
                                          (obj, res) => {
            try {
                service.apply_charge_limit.end (res);
            } catch (Error e) {
                if (!closing) {
                    report (e.message);
                    pull ();
                }
            }
        });
    }

    private void show_level () {
        var capacity = read ("/sys/class/power_supply/BAT0/capacity");
        var state = read ("/sys/class/power_supply/BAT0/status");

        if (capacity == null) {
            level_row.subtitle = "Unknown";
            return;
        }

        level_row.subtitle = state == null
            ? "%s%%".printf (capacity)
            : "%s%%  ·  %s".printf (capacity, state);
    }

    private static string? read (string path) {
        try {
            string contents;
            if (FileUtils.get_contents (path, out contents)) {
                return contents.strip ();
            }
        } catch (Error e) {
            // Absent battery is not worth a toast; the row says Unknown.
        }
        return null;
    }
}
