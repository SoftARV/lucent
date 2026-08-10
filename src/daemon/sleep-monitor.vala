namespace Lucent {

    // logind announces both edges of a suspend on one signal: true just before
    // sleeping, false once userspace is back. Only the second is interesting --
    // the EC drops its live power mode across the cycle and needs it rewritten.
    public class SleepMonitor : Object {

        public signal void resumed ();

        private DBusConnection? system_bus = null;
        private uint subscription = 0;

        construct {
            try {
                system_bus = Bus.get_sync (BusType.SYSTEM);
            } catch (Error e) {
                warning ("no system bus, resume handling is off: %s", e.message);
                return;
            }

            subscription = system_bus.signal_subscribe (
                "org.freedesktop.login1",
                "org.freedesktop.login1.Manager",
                "PrepareForSleep",
                "/org/freedesktop/login1",
                null,
                DBusSignalFlags.NONE,
                (connection, sender, path, iface, name, parameters) => {
                    var going_to_sleep = false;
                    parameters.get ("(b)", out going_to_sleep);

                    if (!going_to_sleep) {
                        resumed ();
                    }
                });
        }

        public override void dispose () {
            if (subscription != 0 && system_bus != null) {
                system_bus.signal_unsubscribe (subscription);
                subscription = 0;
            }
            base.dispose ();
        }
    }
}
