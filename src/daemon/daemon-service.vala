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
        private const string KEY_CPU_BOOST = "cpu-boost";
        private const string KEY_GPU_BOOST = "gpu-boost";

        private const string KEY_FX = "lighting-effect";
        private const string KEY_FX_MODE = "lighting-mode";
        private const string KEY_FX_PRIMARY = "lighting-primary";
        private const string KEY_FX_SECONDARY = "lighting-secondary";
        private const string KEY_FX_SPEED = "lighting-speed";
        private const string KEY_FX_DIRECTION = "lighting-direction";
        private const string KEY_FX_LOGO = "lighting-logo";
        private const string KEY_FX_FOLLOW = "lighting-follow-screen";

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

        // Lighting. Brightness and the logo are read back from the device;
        // the rest is remembered here because the firmware cannot be asked
        // what effect is running. Colours are packed 0xRRGGBB.
        public uint brightness { get; private set; default = 0; }
        public bool logo_active { get; private set; default = false; }
        public string effect { get; private set; default = "off"; }
        public uint effect_mode { get; private set; default = 0; }
        public uint effect_primary { get; private set; default = 0; }
        public uint effect_secondary { get; private set; default = 0; }
        public uint effect_speed { get; private set; default = 1; }
        public uint wave_direction { get; private set; default = 2; }
        public bool follow_screen { get; private set; default = true; }

        private LaptopDevice? device;
        private Settings settings;
        private SleepMonitor sleep;
        private PowerSource power;
        private ScreenMonitor screen;
        private DBusConnection? bus = null;

        // What the lighting was on the way into a blank, and whether we are the
        // reason it is dark. Held in memory rather than GSettings: it is a
        // record of one blank, not a preference, and a value that outlived the
        // process would be replayed over whatever the Fn keys had since set.
        //
        // The logo needs no saved value, only a flag -- it is taken down only
        // when it was lit, so putting it back is always "on". The two are
        // tracked separately so that setting one by hand does not cancel the
        // other's restore.
        private uint8 saved_brightness = 0;
        private bool brightness_suspended = false;
        private bool logo_suspended = false;

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

            follow_screen = settings.get_boolean (KEY_FX_FOLLOW);

            screen = new ScreenMonitor ();
            screen.changed.connect (() => {
                sync_backlight ();
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
            restore_lighting ();

            // The acquire ladder can hand us the device seconds after the
            // screen state is already known, so the blank edge may have come
            // and gone before there was anything to write to.
            sync_backlight ();
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
            if (pspec.value_type == typeof (string)) {
                return new Variant.string (boxed.get_string () ?? "");
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

        // One zone per call, because that is what the hardware wants: a CPU
        // preset change writes zone 0x01 only and a GPU change zone 0x02 only.
        // Unlike the fan these ARE stored and reapplied, because the firmware
        // drops them across suspend and a boost the user chose should survive
        // a lid close.
        public void apply_cpu_boost (uint level) throws Error {
            require_device ();
            device.write_cpu_boost (level);
            settings.set_int (KEY_CPU_BOOST, (int) level);
            refresh_state ();
        }

        public void apply_gpu_boost (uint level) throws Error {
            require_device ();
            device.write_gpu_boost (level);
            settings.set_int (KEY_GPU_BOOST, (int) level);
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

        // --- lighting --------------------------------------------------------

        // A byte, not a percentage: the firmware takes 0-255 and openrazer's
        // D-Bus API was doing the conversion. Not persisted, because it reads
        // back off the device -- and because the laptop's own Fn keys change
        // it, so a stored value would fight the keyboard.
        public void apply_brightness (uint level) throws Error {
            require_device ();

            // An explicit write wins. Whoever asked for a level while the panel
            // is dark meant it, and the value captured at the blank is stale
            // from here -- restoring it at the next wake would undo them.
            brightness_suspended = false;

            device.lighting ().write_brightness ((uint8) uint.min (level, KeyboardDevice.BRIGHTNESS_MAX));
            read_lighting ();
        }

        // Off hands the keyboard and the logo straight back if we are holding
        // them dark: the setting meant to stop Lucent touching the lighting
        // must not be the thing that leaves it off.
        public void apply_follow_screen (bool enabled) throws Error {
            settings.set_boolean (KEY_FX_FOLLOW, enabled);
            follow_screen = enabled;

            if (enabled) {
                sync_backlight ();
                return;
            }

            if (device == null) {
                return;
            }

            try {
                if (brightness_suspended) {
                    device.lighting ().write_brightness (saved_brightness);
                    brightness_suspended = false;
                }
                if (logo_suspended) {
                    device.lighting ().write_logo (true);
                    logo_suspended = false;
                }
                read_lighting ();
            } catch (Error e) {
                warning ("cannot hand the lighting back: %s", e.message);
            }
        }

        public void apply_logo (bool active) throws Error {
            require_device ();

            // As with brightness: an explicit write is not something to undo
            // at the next wake.
            logo_suspended = false;

            device.lighting ().write_logo (active);
            settings.set_boolean (KEY_FX_LOGO, active);
            read_lighting ();
        }

        // One call carrying the whole effect, because that is how the UI
        // applies it -- everything is coalesced behind one debounce timer
        // before it reaches the bus.
        public void apply_effect (string name, uint mode, uint primary, uint secondary,
                                  uint speed, uint direction) throws Error {
            require_device ();

            var chosen = Effect.from_id (name);
            write_effect (chosen, (Mode) mode, primary, secondary, speed, direction);

            settings.set_string (KEY_FX, chosen.id ());
            settings.set_uint (KEY_FX_MODE, mode);
            settings.set_uint (KEY_FX_PRIMARY, primary);
            settings.set_uint (KEY_FX_SECONDARY, secondary);
            settings.set_uint (KEY_FX_SPEED, speed);
            settings.set_uint (KEY_FX_DIRECTION, direction);

            effect = chosen.id ();
            effect_mode = mode;
            effect_primary = primary;
            effect_secondary = secondary;
            effect_speed = speed;
            wave_direction = direction;

            message ("lighting set to %s", chosen.title ());
        }

        public void refresh () throws Error {
            require_device ();
            refresh_state ();
        }

        // --- internals -----------------------------------------------------

        private void write_effect (Effect chosen, Mode mode, uint primary, uint secondary,
                                   uint speed, uint direction) throws Error {
            var light = device.lighting ();

            uint8 r1 = (uint8) ((primary >> 16) & 0xff);
            uint8 g1 = (uint8) ((primary >> 8) & 0xff);
            uint8 b1 = (uint8) (primary & 0xff);
            uint8 r2 = (uint8) ((secondary >> 16) & 0xff);
            uint8 g2 = (uint8) ((secondary >> 8) & 0xff);
            uint8 b2 = (uint8) (secondary & 0xff);
            uint8 s = (uint8) speed;

            switch (chosen) {
                case Effect.STATIC:
                    light.write_static (r1, g1, b1);
                    break;

                case Effect.SPECTRUM:
                    light.write_spectrum ();
                    break;

                case Effect.WAVE:
                    light.write_wave ((uint8) direction);
                    break;

                case Effect.REACTIVE:
                    light.write_reactive (s, r1, g1, b1);
                    break;

                case Effect.BREATH:
                    if (mode == Mode.RANDOM) {
                        light.write_breath_random ();
                    } else if (mode == Mode.DUAL) {
                        light.write_breath_dual (r1, g1, b1, r2, g2, b2);
                    } else {
                        light.write_breath_single (r1, g1, b1);
                    }
                    break;

                case Effect.STARLIGHT:
                    if (mode == Mode.RANDOM) {
                        light.write_starlight_random (s);
                    } else if (mode == Mode.DUAL) {
                        light.write_starlight_dual (s, r1, g1, b1, r2, g2, b2);
                    } else {
                        light.write_starlight_single (s, r1, g1, b1);
                    }
                    break;

                default:
                    light.write_off ();
                    break;
            }
        }

        // The effect cannot be read back -- the firmware has no query for it,
        // which is exactly why openrazer kept that in software. So what is
        // published is what was last written, recovered from GSettings at
        // startup. Brightness and the logo are real device reads.
        private void read_lighting () {
            if (device == null) {
                return;
            }

            try {
                brightness = device.lighting ().read_brightness ();
                logo_active = device.lighting ().read_logo ();
            } catch (Error e) {
                warning ("cannot read lighting state: %s", e.message);
            }
        }

        // Only at startup, not on resume. Measured: the power mode is dropped
        // across suspend but lighting is not, and a lid close only blanks the
        // panel rather than losing the state. So a resume has nothing to put
        // back, and rewriting it there would stamp on a brightness the Fn keys
        // had just changed.
        private void restore_lighting () {
            if (device == null) {
                return;
            }

            effect = settings.get_string (KEY_FX);
            effect_mode = settings.get_uint (KEY_FX_MODE);
            effect_primary = settings.get_uint (KEY_FX_PRIMARY);
            effect_secondary = settings.get_uint (KEY_FX_SECONDARY);
            effect_speed = settings.get_uint (KEY_FX_SPEED);
            wave_direction = settings.get_uint (KEY_FX_DIRECTION);

            try {
                write_effect (Effect.from_id (effect), (Mode) effect_mode,
                              effect_primary, effect_secondary,
                              effect_speed, wave_direction);
                device.lighting ().write_logo (settings.get_boolean (KEY_FX_LOGO));
            } catch (Error e) {
                warning ("cannot restore lighting: %s", e.message);
            }

            read_lighting ();
        }

        // The lighting follows the panel, not the session lock -- see
        // ScreenMonitor for why those are different and by how much. The lid
        // logo goes with the keyboard: it is lighting on the same machine, and
        // leaving it lit over a dark keyboard looks like a bug rather than a
        // decision.
        //
        // Brightness is otherwise never replayed, because the Fn keys own it.
        // This is the one sanctioned exception and it is deliberately narrow:
        // what was captured at a blank, written back at the very next wake, and
        // dropped the moment anyone sets it themselves.
        private void sync_backlight () {
            if (device == null || !follow_screen) {
                return;
            }

            var light = device.lighting ();

            try {
                if (screen.blanked) {
                    // Each half is guarded on its own flag, so a second blank
                    // with no wake between cannot overwrite what was saved with
                    // the dark values we wrote ourselves.
                    if (!brightness_suspended) {
                        var level = light.read_brightness ();
                        if (level > 0) {
                            saved_brightness = level;
                            light.write_brightness (0);
                            brightness_suspended = true;
                        }
                    }

                    if (!logo_suspended && light.read_logo ()) {
                        light.write_logo (false);
                        logo_suspended = true;
                    }
                } else {
                    if (brightness_suspended) {
                        light.write_brightness (saved_brightness);
                        brightness_suspended = false;
                    }

                    if (logo_suspended) {
                        light.write_logo (true);
                        logo_suspended = false;
                    }
                }

                read_lighting ();
            } catch (Error e) {
                warning ("cannot follow the screen: %s", e.message);
            }
        }

        // A client asking for something is also a chance to pick the device up,
        // in case it appeared after the retry ladder above gave up.
        private void require_device () throws Error {
            if (!try_open ()) {
                throw new HidError.NO_DEVICE (
                    "no laptop control device; is 60-lucent-razer.rules installed?");
            }
        }

        // Only in Custom, and only plugged in. Measured: the registers hold a
        // value in every mode but move the graphics power limit only in
        // Custom, and not at all on battery. Writing them elsewhere would be
        // traffic with no effect.
        private void restore_boost (PowerMode mode) {
            if (device == null || on_battery || !PowerMode.takes_boost (mode)) {
                return;
            }

            var cpu = settings.get_int (KEY_CPU_BOOST);
            var gpu = settings.get_int (KEY_GPU_BOOST);

            try {
                if (cpu >= 0) {
                    device.write_cpu_boost ((uint) cpu);
                }
                if (gpu >= 0) {
                    device.write_gpu_boost ((uint) gpu);
                }
            } catch (Error e) {
                warning ("cannot restore boost: %s", e.message);
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

            // Brightness rides along with the rest: a Refresh is how the UI
            // notices the Fn keys, since a feature report notifies nobody.
            read_lighting ();
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

                restore_boost ((PowerMode) desired);

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
