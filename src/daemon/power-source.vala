namespace Lucent {

    // UPower carries OnBattery on its root object, so the power source can be
    // watched without guessing at a line_power device path -- those are named
    // per-machine (AC0, ACAD, ...) and would need enumerating first.
    public class PowerSource : Object {

        private const string UPOWER = "org.freedesktop.UPower";
        private const string UPOWER_PATH = "/org/freedesktop/UPower";

        public signal void changed ();

        public bool on_battery { get; private set; default = false; }

        private DBusConnection? system_bus = null;
        private uint subscription = 0;

        construct {
            try {
                system_bus = Bus.get_sync (BusType.SYSTEM);
            } catch (Error e) {
                warning ("no system bus, power source tracking is off: %s", e.message);
                return;
            }

            read_current ();

            subscription = system_bus.signal_subscribe (
                UPOWER,
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
                UPOWER_PATH,
                null,
                DBusSignalFlags.NONE,
                (connection, sender, path, iface, name, parameters) => {
                    string interface_name;
                    Variant properties;
                    Variant invalidated;

                    parameters.get ("(s@a{sv}@as)",
                                    out interface_name, out properties, out invalidated);

                    if (interface_name != UPOWER) {
                        return;
                    }

                    var value = properties.lookup_value ("OnBattery", VariantType.BOOLEAN);
                    if (value == null) {
                        return;
                    }

                    var now = value.get_boolean ();
                    if (now != on_battery) {
                        on_battery = now;
                        changed ();
                    }
                });
        }

        private void read_current () {
            try {
                var reply = system_bus.call_sync (
                    UPOWER,
                    UPOWER_PATH,
                    "org.freedesktop.DBus.Properties",
                    "Get",
                    new Variant ("(ss)", UPOWER, "OnBattery"),
                    new VariantType ("(v)"),
                    DBusCallFlags.NONE,
                    -1,
                    null);

                Variant boxed;
                reply.get ("(v)", out boxed);
                on_battery = boxed.get_boolean ();
            } catch (Error e) {
                warning ("cannot read UPower OnBattery: %s", e.message);
            }
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
