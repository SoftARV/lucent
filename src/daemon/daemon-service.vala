namespace Lucent {

    public const string DAEMON_BUS_NAME = "dev.miguel.Lucent.Daemon";
    public const string DAEMON_OBJECT_PATH = "/dev/miguel/Lucent/Daemon";

    // Methods are named apply_* rather than set_*: Vala turns a property into a
    // C setter of exactly that name, so set_power_mode would collide with the
    // power_mode property.
    [DBus (name = "dev.miguel.Lucent.Daemon")]
    public class DaemonService : Object {

        private const uint RETRY_DELAY_SECONDS = 2;
        private const int RETRY_LIMIT = 2;

        public bool available { get; private set; default = false; }
        public uint power_mode { get; private set; default = 0; }
        public uint fan_rpm { get; private set; default = 0; }
        public uint cpu_boost { get; private set; default = 0; }
        public uint gpu_boost { get; private set; default = 0; }
        public bool charge_limit_enabled { get; private set; default = false; }
        public uint charge_limit_threshold { get; private set; default = 0; }

        private LaptopDevice? device;
        private Settings settings;
        private SleepMonitor sleep;

        public DaemonService (LaptopDevice? device) {
            this.device = device;
            this.available = device != null;

            settings = new Settings (Config.APP_ID);

            sleep = new SleepMonitor ();
            sleep.resumed.connect (() => {
                message ("resumed, restoring power mode");
                restore (0);
            });

            refresh_state ();
            restore (0);
        }

        // --- exported ------------------------------------------------------

        public void apply_power_mode (uint mode) throws Error {
            require_device ();

            if (!PowerMode.is_valid ((int) mode)) {
                throw new HidError.UNSUPPORTED ("power mode %u is not 0-4", mode);
            }

            device.write_power_mode ((PowerMode) mode);
            settings.set_int ("power-mode", (int) mode);
            refresh_state ();
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

            var desired = settings.get_int ("power-mode");
            if (!PowerMode.is_valid (desired)) {
                return;
            }

            try {
                device.write_power_mode ((PowerMode) desired);

                var actual = device.read_power_mode ();
                if (actual == (PowerMode) desired) {
                    message ("power mode is %s", actual.title ());
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
