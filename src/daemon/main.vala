int main (string[] argv) {
    Environment.set_prgname ("lucent-daemon");

    Lucent.LaptopDevice? device = null;

    try {
        device = Lucent.LaptopDevice.open ();
        message ("using %s", device.path);
    } catch (Error e) {
        // Kept running rather than exited: the GUI asks for Available and can
        // then say something useful instead of failing to reach the daemon.
        warning ("no laptop control device: %s", e.message);
        warning ("if the device is present, install 99-lucent-razer.rules and replug");
    }

    var service = new Lucent.DaemonService (device);
    var loop = new MainLoop ();

    var owner = Bus.own_name (
        BusType.SESSION,
        Lucent.DAEMON_BUS_NAME,
        BusNameOwnerFlags.NONE,
        (connection) => {
            try {
                connection.register_object (Lucent.DAEMON_OBJECT_PATH, service);
                service.attach (connection);
            } catch (IOError e) {
                critical ("cannot export %s: %s", Lucent.DAEMON_OBJECT_PATH, e.message);
                loop.quit ();
            }
        },
        () => {
            message ("owning %s", Lucent.DAEMON_BUS_NAME);
        },
        () => {
            critical ("lost %s, is another instance running?", Lucent.DAEMON_BUS_NAME);
            loop.quit ();
        });

    loop.run ();
    Bus.unown_name (owner);
    return 0;
}
