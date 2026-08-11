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
        public uint fan_actual_cpu { get; private set; default = 0; }
        public uint fan_actual_gpu { get; private set; default = 0; }
        public uint cpu_boost { get; private set; default = 0; }
        public uint gpu_boost { get; private set; default = 0; }
        public bool charge_limit_enabled { get; private set; default = false; }
        public uint charge_limit_threshold { get; private set; default = 80; }
        public int power_mode_ac { get; private set; default = -1; }
        public int power_mode_battery { get; private set; default = -1; }

        // Lighting. The daemon owns this too now, so there is one model and
        // one transport rather than a second daemon for the keyboard.
        public uint brightness { get; private set; default = 0; }
        public bool logo_active { get; private set; default = false; }
        public string effect { get; private set; default = "off"; }
        public uint effect_mode { get; private set; default = 0; }
        public uint effect_primary { get; private set; default = 0; }
        public uint effect_secondary { get; private set; default = 0; }
        public uint effect_speed { get; private set; default = 1; }
        public uint wave_direction { get; private set; default = 2; }

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
            fan_actual_cpu = proxy.fan_actual_cpu;
            fan_actual_gpu = proxy.fan_actual_gpu;
            cpu_boost = proxy.cpu_boost;
            gpu_boost = proxy.gpu_boost;
            charge_limit_enabled = proxy.charge_limit_enabled;
            charge_limit_threshold = proxy.charge_limit_threshold;
            power_mode_ac = proxy.power_mode_ac;
            power_mode_battery = proxy.power_mode_battery;

            brightness = proxy.brightness;
            logo_active = proxy.logo_active;
            effect = proxy.effect;
            effect_mode = proxy.effect_mode;
            effect_primary = proxy.effect_primary;
            effect_secondary = proxy.effect_secondary;
            effect_speed = proxy.effect_speed;
            wave_direction = proxy.wave_direction;
        }

        // --- lighting -------------------------------------------------------

        // The firmware takes a byte; the slider is a percentage. Rounding
        // rather than truncating keeps 100% at 255 instead of 254.
        public static uint8 level_of (double percent) {
            return (uint8) (percent.clamp (0, 100) / 100.0 * KEYBOARD_BRIGHTNESS_MAX + 0.5);
        }

        public static double percent_of (uint level) {
            return (level * 100 + KEYBOARD_BRIGHTNESS_MAX / 2) / KEYBOARD_BRIGHTNESS_MAX;
        }

        public static Gdk.RGBA rgba_of (uint packed) {
            return Gdk.RGBA () {
                red = ((packed >> 16) & 0xff) / 255.0f,
                green = ((packed >> 8) & 0xff) / 255.0f,
                blue = (packed & 0xff) / 255.0f,
                alpha = 1,
            };
        }

        public static uint packed_of (Gdk.RGBA rgba) {
            uint r = (uint) (rgba.red.clamp (0, 1) * 255);
            uint g = (uint) (rgba.green.clamp (0, 1) * 255);
            uint b = (uint) (rgba.blue.clamp (0, 1) * 255);
            return (r << 16) | (g << 8) | b;
        }

        public async void apply_brightness (double percent) throws Error {
            require ();
            yield proxy.apply_brightness (level_of (percent));
        }

        public async void apply_logo (bool active) throws Error {
            require ();
            yield proxy.apply_logo (active);
        }

        public async void apply_effect (Effect chosen, Mode mode, Gdk.RGBA first,
                                        Gdk.RGBA second, int speed,
                                        uint direction) throws Error {
            require ();
            yield proxy.apply_effect (chosen.id (), (uint) mode, packed_of (first),
                                      packed_of (second), (uint) speed, direction);
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

        // Separate calls because the hardware writes one zone per change.
        public async void apply_cpu_boost (uint level) throws Error {
            require ();
            yield proxy.apply_cpu_boost (level);
        }

        public async void apply_gpu_boost (uint level) throws Error {
            require ();
            yield proxy.apply_gpu_boost (level);
        }

        // Asks the daemon to re-read the device. Nothing else makes the live
        // values move: the daemon has no timer of its own, deliberately, so
        // that it costs nothing while no window is open.
        public async void refresh () throws Error {
            require ();
            yield proxy.refresh ();
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
