namespace Lucent {

    public const string RAZER_BUS = "org.razer";
    public const string RAZER_PATH = "/org/razer";
    public const string RAZER_DEVICE_PATH = "/org/razer/device/";

    // Getters are synchronous: they run once at startup, before the window is
    // shown, where blocking costs nothing. Setters are async because they fire
    // repeatedly while the user drags a slider or clicks through effects, and
    // a blocking call there stalls the frame clock.

    [DBus (name = "razer.devices")]
    public interface RazerDevices : Object {
        [DBus (name = "getDevices")]
        public abstract string[] get_devices () throws Error;

        [DBus (name = "device_added")]
        public signal void device_added ();

        [DBus (name = "device_removed")]
        public signal void device_removed ();
    }

    [DBus (name = "razer.device.misc")]
    public interface DeviceMisc : Object {
        [DBus (name = "getDeviceName")]
        public abstract string get_device_name () throws Error;

        [DBus (name = "getDeviceType")]
        public abstract string get_device_type () throws Error;

        [DBus (name = "getFirmware")]
        public abstract string get_firmware () throws Error;

        [DBus (name = "getMatrixDimensions")]
        public abstract int[] get_matrix_dimensions () throws Error;

        [DBus (name = "hasMatrix")]
        public abstract bool has_matrix () throws Error;
    }

    [DBus (name = "razer.device.lighting.brightness")]
    public interface DeviceBrightness : Object {
        [DBus (name = "getBrightness")]
        public abstract double get_brightness () throws Error;

        [DBus (name = "setBrightness")]
        public abstract async void set_brightness (double value) throws Error;
    }

    [DBus (name = "razer.device.lighting.chroma")]
    public interface DeviceChroma : Object {
        [DBus (name = "getEffect")]
        public abstract string get_effect () throws Error;

        [DBus (name = "getEffectColors")]
        public abstract uint8[] get_effect_colors () throws Error;

        [DBus (name = "getEffectSpeed")]
        public abstract int32 get_effect_speed () throws Error;

        [DBus (name = "getWaveDir")]
        public abstract int32 get_wave_dir () throws Error;

        [DBus (name = "setNone")]
        public abstract async void set_none () throws Error;

        [DBus (name = "setStatic")]
        public abstract async void set_static (uint8 r, uint8 g, uint8 b) throws Error;

        [DBus (name = "setSpectrum")]
        public abstract async void set_spectrum () throws Error;

        [DBus (name = "setWave")]
        public abstract async void set_wave (int32 direction) throws Error;

        [DBus (name = "setReactive")]
        public abstract async void set_reactive (uint8 r, uint8 g, uint8 b, uint8 speed) throws Error;

        [DBus (name = "setBreathSingle")]
        public abstract async void set_breath_single (uint8 r, uint8 g, uint8 b) throws Error;

        [DBus (name = "setBreathDual")]
        public abstract async void set_breath_dual (uint8 r1, uint8 g1, uint8 b1,
                                                    uint8 r2, uint8 g2, uint8 b2) throws Error;

        [DBus (name = "setBreathRandom")]
        public abstract async void set_breath_random () throws Error;

        [DBus (name = "setStarlightSingle")]
        public abstract async void set_starlight_single (uint8 r, uint8 g, uint8 b, uint8 speed) throws Error;

        [DBus (name = "setStarlightDual")]
        public abstract async void set_starlight_dual (uint8 r1, uint8 g1, uint8 b1,
                                                       uint8 r2, uint8 g2, uint8 b2, uint8 speed) throws Error;

        [DBus (name = "setStarlightRandom")]
        public abstract async void set_starlight_random (uint8 speed) throws Error;
    }

    [DBus (name = "razer.device.lighting.logo")]
    public interface DeviceLogo : Object {
        [DBus (name = "getLogoActive")]
        public abstract bool get_logo_active () throws Error;

        [DBus (name = "setLogoActive")]
        public abstract async void set_logo_active (bool active) throws Error;
    }
}
