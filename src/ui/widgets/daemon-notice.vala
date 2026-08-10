// Shown by the Performance and Battery pages when the laptop controls cannot
// be reached. Three different problems land here and they need three different
// answers, which is the whole point of telling them apart:
//
//   no unit installed  -> nothing the app can do; install the package
//   unit not running   -> one click, no privileges needed
//   no device access   -> needs root, so the app explains instead of offering
[GtkTemplate (ui = "/dev/miguel/Lucent/daemon-notice.ui")]
public class Lucent.DaemonNotice : Adw.Bin {

    private const string UNIT = "lucent-daemon.service";

    [GtkChild] private unowned Adw.StatusPage status;
    [GtkChild] private unowned Gtk.Button enable;

    public signal void report (string message);

    private LaptopService service;

    public void configure (LaptopService service) {
        this.service = service;

        enable.clicked.connect (start_service);
        service.notify.connect (() => refresh ());
        refresh ();
    }

    private void refresh () {
        if (service.present) {
            status.title = "Keyboard Not Reachable";
            status.description =
                "The background service is running but cannot open the device. Its "
                + "udev rule grants access when the session starts, so if the rule "
                + "was installed after booting, restarting the machine is usually "
                + "all that is missing.";
            enable.visible = false;
            return;
        }

        // Offering a button that cannot work is worse than offering none: the
        // failure would surface as an opaque systemctl error.
        if (!unit_installed ()) {
            status.title = "Background Service Not Installed";
            status.description =
                "The Performance and Battery controls need lucent-daemon, which "
                + "ships with the Lucent package. Running Lucent from a build tree "
                + "is not enough on its own -- install the package, then reopen "
                + "this window.";
            enable.visible = false;
            return;
        }

        status.title = "Background Service Not Running";
        status.description =
            "Lucent needs lucent-daemon to reach the power and battery controls. "
            + "It runs as you, not as root, and starts with your session.";
        enable.visible = true;
    }

    // Asking systemd directly rather than guessing at unit paths, which differ
    // between a packaged install, /etc and a per-user override. The call fails
    // outright when no unit file exists anywhere.
    private bool unit_installed () {
        try {
            var bus = Bus.get_sync (BusType.SESSION);

            bus.call_sync (
                "org.freedesktop.systemd1",
                "/org/freedesktop/systemd1",
                "org.freedesktop.systemd1.Manager",
                "GetUnitFileState",
                new Variant ("(s)", UNIT),
                new VariantType ("(s)"),
                DBusCallFlags.NONE,
                -1,
                null);

            return true;
        } catch (Error e) {
            return false;
        }
    }

    // systemctl --user needs no elevation: the unit belongs to this session.
    private void start_service () {
        enable.sensitive = false;

        try {
            var process = new Subprocess (
                SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE,
                "systemctl", "--user", "enable", "--now", UNIT);

            process.communicate_utf8_async.begin (null, null, (obj, res) => {
                string ignored, errors;

                try {
                    process.communicate_utf8_async.end (res, out ignored, out errors);

                    if (!process.get_successful ()) {
                        report (errors == null || errors.strip () == ""
                            ? "Could not start the background service."
                            : errors.strip ());
                    }
                } catch (Error e) {
                    report ("Could not start the background service: " + e.message);
                }

                enable.sensitive = true;
            });
        } catch (Error e) {
            report ("Could not run systemctl: " + e.message);
            enable.sensitive = true;
        }
    }
}
