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

        private const string KEY_AC = "power-mode-ac";
        private const string KEY_BATTERY = "power-mode-battery";

        public bool available { get; private set; default = false; }
        public bool on_battery { get; private set; default = false; }

        // Live values read back off the device.
        public uint power_mode { get; private set; default = 0; }
        public uint fan_rpm { get; private set; default = 0; }
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

        public DaemonService (LaptopDevice? device) {
            this.device = device;
            this.available = device != null;

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
            refresh_state ();
            restore (0);
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
                throw new HidError.UNSUPPORTED ("power mode %u is not 0-4", mode);
            }

            settings.set_int (for_battery ? KEY_BATTERY : KEY_AC, (int) mode);
            sync_profiles ();

            var source = for_battery ? "battery" : "AC";

            if (for_battery == on_battery) {
                device.write_power_mode ((PowerMode) mode);
                refresh_state ();
                message ("power mode set to %s on %s",
                         ((PowerMode) mode).title (), source);
            } else {
                message ("stored %s for %s, which is not the live source",
                         ((PowerMode) mode).title (), source);
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

        public void refresh () throws Error {
            require_device ();
            refresh_state ();
        }

        // --- internals -----------------------------------------------------

        private void require_device () throws Error {
            if (device == null) {
                throw new HidError.NO_DEVICE (
                    "no laptop control device; is the udev rule installed?");
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
                fan_rpm = device.read_fan_rpm ();
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
                             actual.title (), on_battery ? "battery" : "AC");
                    refresh_state ();
                    return;
                }

                warning ("attempt %d: asked for %s, device reports %s",
                         attempt + 1, ((PowerMode) desired).title (), actual.title ());
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
