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

    public async void write_brightness (double value) throws Error {
        yield bright.set_brightness (value);
    }

    public void read_effect (out Effect effect, out Mode mode) throws Error {
        parse_effect (chroma.get_effect (), out effect, out mode);
    }

    public Gdk.RGBA read_color (int index) throws Error {
        var raw = chroma.get_effect_colors ();
        var offset = index * 3;
        var rgba = Gdk.RGBA () { red = 0, green = 1, blue = 1, alpha = 1 };

        if (raw.length >= offset + 3) {
            rgba.red = raw[offset] / 255.0f;
            rgba.green = raw[offset + 1] / 255.0f;
            rgba.blue = raw[offset + 2] / 255.0f;
        }
        return rgba;
    }

    public int read_speed () throws Error {
        return chroma.get_effect_speed ();
    }

    public int32 read_wave_dir () throws Error {
        return chroma.get_wave_dir ();
    }

    public bool read_logo_active () throws Error {
        return has_logo ? logo.get_logo_active () : false;
    }

    public async void write_logo_active (bool active) throws Error {
        if (has_logo) {
            yield logo.set_logo_active (active);
        }
    }

    public async void apply (Effect effect, Mode mode, Gdk.RGBA first, Gdk.RGBA second,
                             int speed, int32 direction) throws Error {
        uint8 r1 = byte_of (first.red), g1 = byte_of (first.green), b1 = byte_of (first.blue);
        uint8 r2 = byte_of (second.red), g2 = byte_of (second.green), b2 = byte_of (second.blue);
        uint8 s = (uint8) speed;

        switch (effect) {
            case Effect.STATIC:
                yield chroma.set_static (r1, g1, b1);
                break;

            case Effect.SPECTRUM:
                yield chroma.set_spectrum ();
                break;

            case Effect.WAVE:
                yield chroma.set_wave (direction);
                break;

            case Effect.REACTIVE:
                yield chroma.set_reactive (r1, g1, b1, s);
                break;

            case Effect.BREATH:
                if (mode == Mode.RANDOM) {
                    yield chroma.set_breath_random ();
                } else if (mode == Mode.DUAL) {
                    yield chroma.set_breath_dual (r1, g1, b1, r2, g2, b2);
                } else {
                    yield chroma.set_breath_single (r1, g1, b1);
                }
                break;

            case Effect.STARLIGHT:
                if (mode == Mode.RANDOM) {
                    yield chroma.set_starlight_random (s);
                } else if (mode == Mode.DUAL) {
                    yield chroma.set_starlight_dual (r1, g1, b1, r2, g2, b2, s);
                } else {
                    yield chroma.set_starlight_single (r1, g1, b1, s);
                }
                break;

            default:
                yield chroma.set_none ();
                break;
        }
    }

    private static uint8 byte_of (float component) {
        return (uint8) (component.clamp (0.0f, 1.0f) * 255.0f);
    }
}
