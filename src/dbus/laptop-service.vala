namespace Lucent {

    // Republishes the daemon's D-Bus properties as ordinary Vala properties.
    //
    // This layer exists for one measured reason: Vala's generated proxies do
    // not emit notify when PropertiesChanged arrives, only DBusProxy's
    // g-properties-changed. Widgets that bound straight to the proxy would
    // never update. Here the signal is caught once and turned into property
    // changes the UI can bind to normally.
    public class LaptopService : Object {

        // The daemon answered at all. False means it is not installed or not
        // enabled, which is a different problem from a missing device.
        public bool present { get; private set; default = false; }

        // The daemon is running but could not open the device -- almost always
        // a missing udev rule.
        public bool available { get; private set; default = false; }

        public bool on_battery { get; private set; default = false; }
        public uint power_mode { get; private set; default = 0; }
        public bool fan_manual { get; private set; default = false; }
        public uint fan_rpm { get; private set; default = 0; }
        public uint cpu_boost { get; private set; default = 0; }
        public uint gpu_boost { get; private set; default = 0; }
        public bool charge_limit_enabled { get; private set; default = false; }
        public uint charge_limit_threshold { get; private set; default = 80; }
        public int power_mode_ac { get; private set; default = -1; }
        public int power_mode_battery { get; private set; default = -1; }

        private LaptopProxy? proxy = null;

        public LaptopService () {
            try {
                proxy = Bus.get_proxy_sync<LaptopProxy> (
                    BusType.SESSION, LAPTOP_BUS_NAME, LAPTOP_OBJECT_PATH,
                    DBusProxyFlags.DO_NOT_AUTO_START);
            } catch (Error e) {
                warning ("cannot build a proxy for %s: %s", LAPTOP_BUS_NAME, e.message);
                return;
            }

            var raw = (DBusProxy) proxy;

            raw.g_properties_changed.connect ((changed, invalidated) => {
                pull ();
            });

            // Presence has to come from the name owner. get_proxy_sync succeeds
            // whether or not anything owns the name, and reading a property off
            // an unowned proxy returns the type's default rather than failing --
            // so a property read can never tell us the daemon is missing.
            //
            // Watching it also means the window recovers on its own if the
            // daemon is started, restarted or stopped while the app is open.
            raw.notify["g-name-owner"].connect (() => {
                sync_presence ();
            });

            sync_presence ();
        }

        private void sync_presence () {
            present = ((DBusProxy) proxy).g_name_owner != null;

            if (present) {
                pull ();
            } else {
                available = false;
            }
        }

        // Reads the proxy's cached values, which GDBusProxy has already
        // refreshed by the time the signal lands. No round trip.
        private void pull () {
            if (proxy == null) {
                return;
            }

            available = proxy.available;
            on_battery = proxy.on_battery;
            power_mode = proxy.power_mode;
            fan_manual = proxy.fan_manual;
            fan_rpm = proxy.fan_rpm;
            cpu_boost = proxy.cpu_boost;
            gpu_boost = proxy.gpu_boost;
            charge_limit_enabled = proxy.charge_limit_enabled;
            charge_limit_threshold = proxy.charge_limit_threshold;
            power_mode_ac = proxy.power_mode_ac;
            power_mode_battery = proxy.power_mode_battery;
        }

        public int mode_for (bool for_battery) {
            return for_battery ? power_mode_battery : power_mode_ac;
        }

        public async void apply_power_mode_for (bool for_battery, uint mode) throws Error {
            require ();
            yield proxy.apply_power_mode_for (for_battery, mode);
        }

        public async void clear_power_mode_for (bool for_battery) throws Error {
            require ();
            yield proxy.clear_power_mode_for (for_battery);
        }

        public async void apply_charge_limit (bool enabled, uint threshold) throws Error {
            require ();
            yield proxy.apply_charge_limit (enabled, threshold);
        }

        public async void apply_fan (bool manual, uint rpm) throws Error {
            require ();
            yield proxy.apply_fan (manual, rpm);
        }

        private void require () throws Error {
            if (proxy == null) {
                throw new IOError.NOT_FOUND (
                    "lucent-daemon is not running. Enable it with:\n"
                    + "systemctl --user enable --now lucent-daemon");
            }
        }
    }
}
