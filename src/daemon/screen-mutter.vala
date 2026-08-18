namespace Lucent {

    // Mutter publishes the panel's own power state, which is not the same thing
    // as the session lock. Measured across three lock cycles: the display comes
    // back 3.2 s, 19.9 s and 3.5 s before the lock is dismissed, while going the
    // other way the two agree to within 0.42 s. Keying the backlight off
    // org.gnome.ScreenSaver instead is exactly what left the keyboard dark on a
    // lit lock screen under openrazer -- the divergence is one-directional,
    // which is why the bug only ever showed on the way out.
    //
    // PowerSaveMode carries both edges on PropertiesChanged, verified against a
    // 0.25 s poll running alongside, so this needs no timer of its own and the
    // daemon keeps costing nothing while idle.
    public class MutterBackend : ScreenBackend {

        private const string MUTTER = "org.gnome.Mutter.DisplayConfig";
        private const string MUTTER_PATH = "/org/gnome/Mutter/DisplayConfig";

        // 0 on, 1 standby, 2 suspend, 3 off. -1 means the compositor cannot
        // say, which is not the same as blanked and must not darken anything.
        private const int MODE_ON = 0;
        private const int MODE_UNKNOWN = -1;

        public override string label {
            get { return "mutter"; }
        }

        private DBusConnection? session_bus = null;
        private uint subscription = 0;
        private uint watch = 0;

        public override void start () {
            try {
                session_bus = Bus.get_sync (BusType.SESSION);
            } catch (Error e) {
                warning ("no session bus, screen tracking is off: %s", e.message);
                return;
            }

            subscription = session_bus.signal_subscribe (
                MUTTER,
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
                MUTTER_PATH,
                null,
                DBusSignalFlags.NONE,
                (connection, sender, path, iface, name, parameters) => {
                    string interface_name;
                    Variant properties;
                    Variant invalidated;

                    parameters.get ("(s@a{sv}@as)",
                                    out interface_name, out properties, out invalidated);

                    if (interface_name != MUTTER) {
                        return;
                    }

                    var value = properties.lookup_value ("PowerSaveMode", VariantType.INT32);
                    if (value == null) {
                        return;
                    }

                    update (value.get_int32 ());
                });

            // Presence comes from the name owner rather than from a failed
            // read: the shell restarts underneath us, and this daemon can start
            // before the shell owns the name at all.
            watch = Bus.watch_name (
                BusType.SESSION,
                MUTTER,
                BusNameWatcherFlags.NONE,
                (connection, name, owner) => {
                    present = true;
                    read_current ();
                },
                (connection, name) => {
                    present = false;

                    // A compositor that went away is not a blanked panel.
                    // Holding this true would strand the keyboard dark with
                    // nothing left running to send the wake edge.
                    update (MODE_ON);
                });
        }

        private void update (int mode) {
            publish (mode != MODE_ON && mode != MODE_UNKNOWN);
        }

        private void read_current () {
            try {
                var reply = session_bus.call_sync (
                    MUTTER,
                    MUTTER_PATH,
                    "org.freedesktop.DBus.Properties",
                    "Get",
                    new Variant ("(ss)", MUTTER, "PowerSaveMode"),
                    new VariantType ("(v)"),
                    DBusCallFlags.NONE,
                    -1,
                    null);

                Variant boxed;
                reply.get ("(v)", out boxed);
                update (boxed.get_int32 ());
            } catch (Error e) {
                warning ("cannot read PowerSaveMode: %s", e.message);
            }
        }

        public override void dispose () {
            if (subscription != 0 && session_bus != null) {
                session_bus.signal_unsubscribe (subscription);
                subscription = 0;
            }
            if (watch != 0) {
                Bus.unwatch_name (watch);
                watch = 0;
            }
            base.dispose ();
        }
    }
}
