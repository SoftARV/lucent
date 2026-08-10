// Shown by the Performance and Battery pages when the laptop controls cannot
// be reached. Two different problems land here and they need different
// answers: a service that is not running can be started from the app without
// any privileges, while a missing udev permission cannot and must not be --
// a GUI has no business asking for root to copy one file.
[GtkTemplate (ui = "/dev/miguel/Lucent/daemon-notice.ui")]
public class Lucent.DaemonNotice : Adw.Bin {

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
        if (!service.present) {
            status.title = "Background Service Not Running";
            status.description =
                "Lucent needs lucent-daemon to reach the power and battery controls. "
                + "It runs as you, not as root, and starts with your session.";
            enable.visible = true;
            return;
        }

        status.title = "Keyboard Not Reachable";
        status.description =
            "The service is running but cannot open the device. Its udev rule grants "
            + "access when the session starts, so if the rule was installed after "
            + "booting, restarting the machine is usually all that is missing.";
        enable.visible = false;
    }

    // systemctl --user needs no elevation: the unit belongs to this session.
    private void start_service () {
        enable.sensitive = false;

        try {
            var process = new Subprocess (
                SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE,
                "systemctl", "--user", "enable", "--now", "lucent-daemon.service");

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
