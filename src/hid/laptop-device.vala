namespace Lucent {

    // PowerMode lives in src/model/, shared with the GUI.

    // The laptop's fan, power and battery controls. These live on command
    // classes the openrazer driver does not implement, so they are spoken
    // directly rather than through its D-Bus API, which covers lighting only.
    public class LaptopDevice : Object {

        public const uint16 VENDOR_ID = 0x1532;
        public const uint16 BLADE_14_2025 = 0x02c5;

        private const uint8 CLASS_POWER = 0x0d;
        private const uint8 CLASS_BATTERY = 0x07;

        private const uint8 ZONE_CPU = 0x01;
        private const uint8 ZONE_GPU = 0x02;

        public const uint CHARGE_LIMIT_MIN = 50;
        public const uint CHARGE_LIMIT_MAX = 80;

        public const uint FAN_RPM_MIN = 2200;
        public const uint FAN_RPM_MAX = 5600;

        private HidDevice hid;

        public string path {
            get { return hid.path; }
        }

        private LaptopDevice (HidDevice hid) {
            this.hid = hid;
        }

        // Probes each hidraw node the device exposes and keeps the first that
        // answers a read. On the Blade 14 three of the four interfaces reply.
        public static LaptopDevice open (uint16 product_id = BLADE_14_2025) throws HidError {
            var paths = HidDevice.candidates (VENDOR_ID, product_id);

            if (paths.length == 0) {
                throw new HidError.NO_DEVICE ("no hidraw node for %04x:%04x",
                                              VENDOR_ID, product_id);
            }

            string last = "none responded";

            foreach (var path in paths) {
                try {
                    var candidate = new LaptopDevice (new HidDevice (path));
                    uint threshold;
                    candidate.read_charge_limit (out threshold);
                    return candidate;
                } catch (Error e) {
                    last = e.message;
                }
            }

            throw new HidError.NO_DEVICE ("found %d hidraw node(s) but %s",
                                          paths.length, last);
        }

        // --- power mode ---------------------------------------------------

        public PowerMode read_power_mode () throws HidError {
            uint8 manual;
            return read_zone (ZONE_CPU, out manual);
        }

        // The mode and the manual-fan flag share one command, so the flag is
        // read back and written unchanged. Writing a guessed value here would
        // silently take the fans off their automatic curve.
        public void write_power_mode (PowerMode mode) throws HidError {
            write_zone (ZONE_CPU, mode);
            write_zone (ZONE_GPU, mode);
        }

        private PowerMode read_zone (uint8 zone, out uint8 manual_fan) throws HidError {
            var report = new RazerReport (CLASS_POWER, 0x82, 0x04);
            report.set_args ({ 0x00, zone, 0x00, 0x00 });

            var response = hid.send (report);
            manual_fan = response.arg (3);
            return (PowerMode) response.arg (2);
        }

        private void write_zone (uint8 zone, PowerMode mode) throws HidError {
            uint8 manual_fan;
            read_zone (zone, out manual_fan);

            var report = new RazerReport (CLASS_POWER, 0x02, 0x04);
            report.set_args ({ 0x00, zone, (uint8) mode, manual_fan });
            hid.send (report);
        }

        // --- fan and boost, read-only for now -----------------------------

        // The setpoint is returned whatever the flag says; `manual` is what
        // makes it meaningful. Callers must not present it as a fan speed
        // while the zone is on its automatic curve.
        public uint read_fan_rpm (out bool manual) throws HidError {
            uint8 flag;
            read_zone (ZONE_CPU, out flag);
            manual = flag != 0;

            var report = new RazerReport (CLASS_POWER, 0x81, 0x03);
            report.set_args ({ 0x00, ZONE_CPU, 0x00 });
            return hid.send (report).arg (2) * 100;
        }

        // Measured on this model: manual fan works in every power mode and on
        // either power source. razer-ctl restricts it to Balanced, which is
        // wrong here, so do not reintroduce that check.
        public void write_fan (bool manual, uint rpm) throws HidError {
            if (manual && (rpm < FAN_RPM_MIN || rpm > FAN_RPM_MAX)) {
                throw new HidError.UNSUPPORTED (
                    "fan speed %u RPM out of range, this model accepts %u-%u",
                    rpm, FAN_RPM_MIN, FAN_RPM_MAX);
            }

            // The manual flag shares a command with the power mode, so the
            // mode is read and written back unchanged -- the mirror of what
            // write_power_mode does with the flag.
            foreach (var zone in new uint8[] { ZONE_CPU, ZONE_GPU }) {
                uint8 ignored;
                var mode = read_zone (zone, out ignored);

                var state = new RazerReport (CLASS_POWER, 0x02, 0x04);
                state.set_args ({ 0x00, zone, (uint8) mode, manual ? 0x01 : 0x00 });
                hid.send (state);
            }

            if (!manual) {
                return;
            }

            foreach (var zone in new uint8[] { ZONE_CPU, ZONE_GPU }) {
                var speed = new RazerReport (CLASS_POWER, 0x01, 0x03);
                speed.set_args ({ 0x00, zone, (uint8) (rpm / 100) });
                hid.send (speed);
            }
        }

        public uint read_cpu_boost () throws HidError {
            return read_boost (ZONE_CPU);
        }

        public uint read_gpu_boost () throws HidError {
            return read_boost (ZONE_GPU);
        }

        private uint read_boost (uint8 zone) throws HidError {
            var report = new RazerReport (CLASS_POWER, 0x87, 0x03);
            report.set_args ({ 0x00, zone, 0x00 });
            return hid.send (report).arg (2);
        }

        // --- charge limit -------------------------------------------------

        // One byte: bit 7 enables, the low seven carry the percentage.
        public bool read_charge_limit (out uint threshold) throws HidError {
            var report = new RazerReport (CLASS_BATTERY, 0x92, 0x01);
            report.set_args ({ 0x00 });

            var packed = hid.send (report).arg (0);
            threshold = packed & 0x7f;
            return (packed & 0x80) != 0;
        }

        // Verified by read-back: this command class answers reads with id 0x92
        // rather than echoing 0x12, so its acknowledgement is not a reliable
        // signal that the value took.
        public void write_charge_limit (bool enabled, uint threshold) throws HidError {
            if (threshold < CHARGE_LIMIT_MIN || threshold > CHARGE_LIMIT_MAX) {
                throw new HidError.UNSUPPORTED (
                    "charge limit %u%% out of range, firmware accepts %u-%u",
                    threshold, CHARGE_LIMIT_MIN, CHARGE_LIMIT_MAX);
            }

            var report = new RazerReport (CLASS_BATTERY, 0x12, 0x01);
            report.set_args ({ (uint8) ((enabled ? 0x80 : 0x00) | threshold) });
            hid.send (report);

            uint written;
            var now_enabled = read_charge_limit (out written);

            if (now_enabled != enabled || (enabled && written != threshold)) {
                throw new HidError.BAD_RESPONSE (
                    "charge limit did not take: asked %s/%u%%, device reports %s/%u%%",
                    enabled ? "on" : "off", threshold,
                    now_enabled ? "on" : "off", written);
            }
        }
    }
}
