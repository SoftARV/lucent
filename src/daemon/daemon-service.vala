namespace Lucent {

    public const string DAEMON_BUS_NAME = "dev.miguel.Lucent.Daemon";
    public const string DAEMON_OBJECT_PATH = "/dev/miguel/Lucent/Daemon";

    // Methods are named apply_* rather than set_*: Vala turns a property into a
    // C setter of exactly that name, so set_power_mode would collide with the
    // power_mode property.
    [DBus (name = "dev.miguel.Lucent.Daemon")]
    public class DaemonService : Object {

        private const int UNMANAGED = -1;
        private const uint RETRY_DELAY_SECONDS = 2;
        private const int RETRY_LIMIT = 2;

        private const uint ACQUIRE_DELAY_SECONDS = 2;
        private const int ACQUIRE_LIMIT = 15;

        private const string KEY_AC = "power-mode-ac";
        private const string KEY_BATTERY = "power-mode-battery";

        public bool available { get; private set; default = false; }
        public bool on_battery { get; private set; default = false; }

        // Live values read back off the device.
        public uint power_mode { get; private set; default = 0; }
        public bool fan_manual { get; private set; default = false; }
        public uint fan_rpm { get; private set; default = 0; }
        public uint fan_actual_cpu { get; private set; default = 0; }
        public uint fan_actual_gpu { get; private set; default = 0; }
        public uint cpu_boost { get; private set; default = 0; }
        public uint gpu_boost { get; private set; default = 0; }
        public bool charge_limit_enabled { get; private set; default = false; }
        public uint charge_limit_threshold { get; private set; default = 0; }

        // Stored per-source preferences. -1 means leave the firmware alone.
        public int power_mode_ac { get; private set; default = UNMANAGED; }
        public int power_mode_battery { get; private set; default = UNMANAGED; }

        private LaptopDevice? device;
        private Settings settings;
        private SleepMonitor sleep;
        private PowerSource power;
        private DBusConnection? bus = null;

        public DaemonService () {
            settings = new Settings (Config.APP_ID);

            sleep = new SleepMonitor ();
            sleep.resumed.connect (() => {
                message ("resumed, restoring power mode");
                restore (0);
            });

            power = new PowerSource ();
            on_battery = power.on_battery;
            power.changed.connect (() => {
                on_battery = power.on_battery;
                message ("now on %s", on_battery ? "battery" : "AC");
                restore (0);
            });

            sync_profiles ();
            acquire (0);
        }

        // logind applies the uaccess ACL when the session activates, which
        // races the user manager starting this service: on a cold boot the
        // hidraw node exists but is not ours yet for a few hundred
        // milliseconds. Measured on a real reboot -- the open failed 9 ms
        // after start, and succeeded on every later attempt. Giving up once
        // would leave the daemon blind until it was manually restarted.
        private void acquire (int attempt) {
            if (try_open ()) {
                return;
            }

            if (attempt == 0) {
                message ("device not ready yet, retrying");
            }

            if (attempt < ACQUIRE_LIMIT) {
                Timeout.add_seconds (ACQUIRE_DELAY_SECONDS, () => {
                    acquire (attempt + 1);
                    return Source.REMOVE;
                });
            } else {
                warning ("no laptop control device after %d attempts; "
                         + "is 60-lucent-razer.rules installed?", attempt + 1);
            }
        }

        private bool try_open () {
            if (device != null) {
                return true;
            }

            try {
                device = LaptopDevice.open ();
            } catch (Error e) {
                return false;
            }

            available = true;
            message ("using %s", device.path);

            refresh_state ();
            restore (0);
            return true;
        }

        // Vala 0.56 annotates every exported property with EmitsChangedSignal
        // in the introspection XML but generates no code to emit it, so a
        // client that trusts the annotation never hears about anything. Wire
        // notify to the real signal by hand; without this the UI has to poll.
        [DBus (visible = false)]
        public void attach (DBusConnection connection) {
            bus = connection;
            notify.connect (announce);
        }

        private void announce (ParamSpec pspec) {
            if (bus == null) {
                return;
            }

            var value = property_value (pspec);
            if (value == null) {
                return;
            }

            var entry = new Variant.dict_entry (
                new Variant.string (dbus_name (pspec.name)),
                new Variant.variant (value));

            string[] invalidated = {};

            try {
                bus.emit_signal (
                    null,
                    DAEMON_OBJECT_PATH,
                    "org.freedesktop.DBus.Properties",
                    "PropertiesChanged",
                    new Variant.tuple ({
                        new Variant.string (DAEMON_BUS_NAME),
                        new Variant.array (new VariantType ("{sv}"), { entry }),
                        new Variant.strv (invalidated),
                    }));
            } catch (Error e) {
                warning ("cannot announce %s: %s", pspec.name, e.message);
            }
        }

        private Variant? property_value (ParamSpec pspec) {
            var boxed = Value (pspec.value_type);
            get_property (pspec.name, ref boxed);

            if (pspec.value_type == typeof (bool)) {
                return new Variant.boolean (boxed.get_boolean ());
            }
            if (pspec.value_type == typeof (uint)) {
                return new Variant.uint32 (boxed.get_uint ());
            }
            if (pspec.value_type == typeof (int)) {
                return new Variant.int32 (boxed.get_int ());
            }
            return null;
        }

        // GObject names properties with dashes, D-Bus expects the PascalCase
        // form Vala exported them under.
        private static string dbus_name (string property_name) {
            var name = new StringBuilder ();

            foreach (var part in property_name.split ("-")) {
                if (part.length == 0) {
                    continue;
                }
                name.append (part.substring (0, 1).up ());
                name.append (part.substring (1));
            }

            return name.str;
        }

        // --- exported ------------------------------------------------------

        // Applies to whichever source is live now, which is what a UI showing a
        // single mode picker means by "set this".
        public void apply_power_mode (uint mode) throws Error {
            apply_power_mode_for (on_battery, mode);
        }

        public void apply_power_mode_for (bool for_battery, uint mode) throws Error {
            require_device ();

            if (!PowerMode.is_valid ((int) mode)) {
                throw new HidError.UNSUPPORTED ("power mode %u is outside 0-7", mode);
            }

            settings.set_int (for_battery ? KEY_BATTERY : KEY_AC, (int) mode);
            sync_profiles ();

            var source = for_battery ? "battery" : "AC";

            if (for_battery == on_battery) {
                device.write_power_mode ((PowerMode) mode);
                refresh_state ();
                message ("power mode set to %s on %s",
                         PowerMode.title_for (mode, for_battery), source);
            } else {
                message ("stored %s for %s, which is not the live source",
                         PowerMode.title_for (mode, for_battery), source);
            }
        }

        // Stops managing one source without touching the device: whatever the
        // firmware is doing on its own is left in place.
        public void clear_power_mode_for (bool for_battery) throws Error {
            settings.set_int (for_battery ? KEY_BATTERY : KEY_AC, UNMANAGED);
            sync_profiles ();
        }

        public void apply_charge_limit (bool enabled, uint threshold) throws Error {
            require_device ();
            device.write_charge_limit (enabled, threshold);
            refresh_state ();
        }

        // Deliberately not stored and not restored. The firmware drops a
        // manual fan setting across suspend, measured, and that is a safety
        // net rather than a defect: a speed the machine forgets is one you
        // cannot leave dangerously low by accident. Reapplying it would
        // remove the only thing standing between a forgotten 2200 RPM and a
        // machine under load with its fans idling.
        public void apply_fan (bool manual, uint rpm) throws Error {
            require_device ();
            device.write_fan (manual, rpm);
            refresh_state ();

            message (manual ? "fan set to %u RPM".printf (rpm)
                            : "fan returned to the automatic curve");
        }

        public void refresh () throws Error {
            require_device ();
            refresh_state ();
        }

        // --- internals -----------------------------------------------------

        // A client asking for something is also a chance to pick the device up,
        // in case it appeared after the retry ladder above gave up.
        private void require_device () throws Error {
            if (!try_open ()) {
                throw new HidError.NO_DEVICE (
                    "no laptop control device; is 60-lucent-razer.rules installed?");
            }
        }

        private void sync_profiles () {
            power_mode_ac = settings.get_int (KEY_AC);
            power_mode_battery = settings.get_int (KEY_BATTERY);
        }

        private int desired_mode () {
            return settings.get_int (on_battery ? KEY_BATTERY : KEY_AC);
        }

        private void refresh_state () {
            if (device == null) {
                return;
            }

            try {
                power_mode = device.read_power_mode ();

                bool manual;
                fan_rpm = device.read_fan_rpm (out manual);
                fan_manual = manual;
                fan_actual_cpu = device.read_cpu_fan ();
                fan_actual_gpu = device.read_gpu_fan ();

                cpu_boost = device.read_cpu_boost ();
                gpu_boost = device.read_gpu_boost ();

                uint threshold;
                charge_limit_enabled = device.read_charge_limit (out threshold);
                charge_limit_threshold = threshold;
            } catch (Error e) {
                warning ("cannot read device state: %s", e.message);
            }
        }

        // The charge limit is deliberately absent here: it is held in EC
        // nonvolatile memory and survives unplug, resume and reboot, so
        // rewriting it would be pure noise. Only the power mode is lost.
        private void restore (int attempt) {
            if (device == null) {
                return;
            }

            var desired = desired_mode ();
            if (!PowerMode.is_valid (desired)) {
                return;
            }

            try {
                device.write_power_mode ((PowerMode) desired);

                var actual = device.read_power_mode ();
                if (actual == (PowerMode) desired) {
                    message ("power mode is %s on %s",
                             PowerMode.title_for (actual, on_battery),
                             on_battery ? "battery" : "AC");
                    refresh_state ();
                    return;
                }

                warning ("attempt %d: asked for %s, device reports %s",
                         attempt + 1,
                         PowerMode.title_for (desired, on_battery),
                         PowerMode.title_for (actual, on_battery));
            } catch (Error e) {
                warning ("attempt %d: %s", attempt + 1, e.message);
            }

            // The device is not always ready the instant logind says userspace
            // is back, so a failed write is retried rather than given up on.
            if (attempt < RETRY_LIMIT) {
                Timeout.add_seconds (RETRY_DELAY_SECONDS, () => {
                    restore (attempt + 1);
                    return Source.REMOVE;
                });
            } else {
                warning ("giving up restoring power mode after %d attempts", attempt + 1);
            }
        }
    }
}
