namespace Lucent {

    public const string LAPTOP_BUS_NAME = "dev.miguel.Lucent.Daemon";
    public const string LAPTOP_OBJECT_PATH = "/dev/miguel/Lucent/Daemon";

    // Brightness crosses the bus as the byte the firmware takes, not as the
    // percentage openrazer's API used to convert for us.
    public const uint KEYBOARD_BRIGHTNESS_MAX = 255;

    // lucent-daemon's interface. Properties are read-only here; every write
    // goes through an Apply call so the daemon stays the only writer to the
    // device.
    //
    // Do not connect to notify on this proxy. Vala generates no code to turn
    // an incoming PropertiesChanged into a GObject property notification, so
    // notify never fires and bind_property silently does nothing. Only
    // DBusProxy's own g-properties-changed arrives -- LaptopService wraps that
    // back into real properties.
    [DBus (name = "dev.miguel.Lucent.Daemon")]
    public interface LaptopProxy : Object {
        public abstract bool available { get; }
        public abstract bool on_battery { get; }
        public abstract uint power_mode { get; }
        public abstract bool fan_manual { get; }
        public abstract uint fan_rpm { get; }
        public abstract uint fan_actual_cpu { get; }
        public abstract uint fan_actual_gpu { get; }
        public abstract uint cpu_boost { get; }
        public abstract uint gpu_boost { get; }
        public abstract bool charge_limit_enabled { get; }
        public abstract uint charge_limit_threshold { get; }
        public abstract int power_mode_ac { get; }
        public abstract int power_mode_battery { get; }

        public abstract uint brightness { get; }
        public abstract bool logo_active { get; }
        public abstract string effect { owned get; }
        public abstract uint effect_mode { get; }
        public abstract uint effect_primary { get; }
        public abstract uint effect_secondary { get; }
        public abstract uint effect_speed { get; }
        public abstract uint wave_direction { get; }
        public abstract bool follow_screen { get; }
        public abstract bool follow_screen_supported { get; }

        public abstract async void apply_power_mode (uint mode) throws Error;
        public abstract async void apply_power_mode_for (bool for_battery, uint mode) throws Error;
        public abstract async void clear_power_mode_for (bool for_battery) throws Error;
        public abstract async void apply_charge_limit (bool enabled, uint threshold) throws Error;
        public abstract async void apply_fan (bool manual, uint rpm) throws Error;
        public abstract async void apply_cpu_boost (uint level) throws Error;
        public abstract async void apply_gpu_boost (uint level) throws Error;
        public abstract async void apply_brightness (uint level) throws Error;
        public abstract async void apply_logo (bool active) throws Error;
        public abstract async void apply_follow_screen (bool enabled) throws Error;
        public abstract async void apply_effect (string name, uint mode, uint primary,
                                                 uint secondary, uint speed,
                                                 uint direction) throws Error;
        public abstract async void refresh () throws Error;
        public abstract async void refresh_lighting () throws Error;
    }
}
