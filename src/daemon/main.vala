int main (string[] argv) {
    Environment.set_prgname ("lucent-daemon");

    // The service acquires the device itself, with retries: the udev ACL is
    // not always in place by the time the user manager starts us. It stays
    // running either way, so the GUI can read Available and say something
    // useful instead of failing to reach the daemon at all.
    var service = new Lucent.DaemonService ();
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
