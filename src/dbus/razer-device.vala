public class Lucent.RazerDevice : Object {

    public string serial { get; construct; }
    public string name { get; private set; default = "Razer Device"; }
    public string device_type { get; private set; default = "unknown"; }
    public bool has_logo { get; private set; default = false; }

    private DeviceMisc misc;
    private DeviceBrightness bright;
    private DeviceChroma chroma;
    private DeviceLogo logo;

    public RazerDevice (string serial) throws Error {
        Object (serial: serial);

        var path = RAZER_DEVICE_PATH + serial;
        misc = Bus.get_proxy_sync<DeviceMisc> (BusType.SESSION, RAZER_BUS, path);
        bright = Bus.get_proxy_sync<DeviceBrightness> (BusType.SESSION, RAZER_BUS, path);
        chroma = Bus.get_proxy_sync<DeviceChroma> (BusType.SESSION, RAZER_BUS, path);

        name = misc.get_device_name ();
        device_type = misc.get_device_type ();

        try {
            var l = Bus.get_proxy_sync<DeviceLogo> (BusType.SESSION, RAZER_BUS, path);
            l.get_logo_active ();
            logo = l;
            has_logo = true;
        } catch (Error e) {
            has_logo = false;
        }
    }

    public bool is_keyboard () {
        return device_type == "keyboard";
    }

    public double read_brightness () throws Error {
        return bright.get_brightness ();
    }

    public void write_brightness (double value) throws Error {
        bright.set_brightness (value);
    }

    public Effect read_effect () throws Error {
        return effect_from_id (chroma.get_effect ());
    }

    public Gdk.RGBA read_color () throws Error {
        var c = chroma.get_effect_colors ();
        var rgba = Gdk.RGBA () { red = 0, green = 1, blue = 1, alpha = 1 };
        if (c.length >= 3) {
            rgba.red = c[0] / 255.0f;
            rgba.green = c[1] / 255.0f;
            rgba.blue = c[2] / 255.0f;
        }
        return rgba;
    }

    public int32 read_wave_dir () throws Error {
        return chroma.get_wave_dir ();
    }

    public bool read_logo_active () throws Error {
        return has_logo ? logo.get_logo_active () : false;
    }

    public void write_logo_active (bool active) throws Error {
        if (has_logo) {
            logo.set_logo_active (active);
        }
    }

    public void apply (Effect effect, Gdk.RGBA color, int32 direction) throws Error {
        switch (effect) {
            case Effect.STATIC:
                chroma.set_static (byte_of (color.red), byte_of (color.green), byte_of (color.blue));
                break;
            case Effect.SPECTRUM:
                chroma.set_spectrum ();
                break;
            case Effect.WAVE:
                chroma.set_wave (direction);
                break;
            default:
                chroma.set_none ();
                break;
        }
    }

    private static uint8 byte_of (float component) {
        return (uint8) (component.clamp (0.0f, 1.0f) * 255.0f);
    }
}
