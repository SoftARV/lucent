namespace Lucent {

    public const string LAPTOP_BUS_NAME = "dev.miguel.Lucent.Daemon";
    public const string LAPTOP_OBJECT_PATH = "/dev/miguel/Lucent/Daemon";

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
        public abstract uint fan_rpm { get; }
        public abstract uint cpu_boost { get; }
        public abstract uint gpu_boost { get; }
        public abstract bool charge_limit_enabled { get; }
        public abstract uint charge_limit_threshold { get; }
        public abstract int power_mode_ac { get; }
        public abstract int power_mode_battery { get; }

        public abstract async void apply_power_mode (uint mode) throws Error;
        public abstract async void apply_power_mode_for (bool for_battery, uint mode) throws Error;
        public abstract async void clear_power_mode_for (bool for_battery) throws Error;
        public abstract async void apply_charge_limit (bool enabled, uint threshold) throws Error;
        public abstract async void refresh () throws Error;
    }
}
