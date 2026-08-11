namespace Lucent {

    // The keyboard's lighting, on the same 90-byte report and the same hidraw
    // node as the laptop controls. The openrazer daemon speaks this too;
    // talking to it directly is what lets one process be the single writer.
    //
    // Effects are write-only. The firmware has no "what effect is set" query,
    // which is why openrazer keeps that in software and why the daemon has to
    // remember it. Brightness and the logo LED do read back.
    public class KeyboardDevice : Object {

        private const uint8 CLASS_LIGHTING = 0x03;
        private const uint8 CLASS_MISC = 0x0e;

        // Argument 0 of 0x03/0x0a. This device is on the standard matrix
        // path, not the extended matrix one newer Blades use.
        private const uint8 FX_OFF = 0x00;
        private const uint8 FX_WAVE = 0x01;
        private const uint8 FX_REACTIVE = 0x02;
        private const uint8 FX_BREATHING = 0x03;
        private const uint8 FX_SPECTRUM = 0x04;
        private const uint8 FX_STATIC = 0x06;
        private const uint8 FX_STARLIGHT = 0x19;

        private const uint8 TYPE_SINGLE = 0x01;
        private const uint8 TYPE_DUAL = 0x02;
        private const uint8 TYPE_RANDOM = 0x03;

        private const uint8 VARSTORE = 0x01;
        private const uint8 LOGO_LED = 0x04;

        // The firmware takes a byte. openrazer's D-Bus API took a percentage
        // and converted, so anything moving off it owns the conversion.
        public const uint8 BRIGHTNESS_MAX = 0xff;

        public const uint8 WAVE_LEFT = 0x01;
        public const uint8 WAVE_RIGHT = 0x02;

        private HidDevice hid;

        public KeyboardDevice (HidDevice hid) {
            this.hid = hid;
        }

        // --- brightness -----------------------------------------------------

        // Not on the lighting class at all: this is the blade brightness
        // command. Reading it is how a change made with the laptop's own Fn
        // keys is noticed, since nothing pushes that to us.
        public uint8 read_brightness () throws HidError {
            var report = new RazerReport (CLASS_MISC, 0x84, 0x02);
            report.set_args ({ 0x01, 0x00 });
            return hid.send (report).arg (1);
        }

        public void write_brightness (uint8 level) throws HidError {
            var report = new RazerReport (CLASS_MISC, 0x04, 0x02);
            report.set_args ({ 0x01, level });
            hid.send (report);
        }

        // --- logo -----------------------------------------------------------

        // Blade laptops drive the logo through led *state*, not led effect.
        public bool read_logo () throws HidError {
            var report = new RazerReport (CLASS_LIGHTING, 0x80, 0x03);
            report.set_args ({ VARSTORE, LOGO_LED, 0x00 });
            return hid.send (report).arg (2) != 0;
        }

        public void write_logo (bool active) throws HidError {
            var report = new RazerReport (CLASS_LIGHTING, 0x00, 0x03);
            report.set_args ({ VARSTORE, LOGO_LED, active ? 0x01 : 0x00 });
            hid.send (report);
        }

        // --- effects --------------------------------------------------------

        public void write_off () throws HidError {
            effect (FX_OFF, 0x01, {});
        }

        public void write_spectrum () throws HidError {
            effect (FX_SPECTRUM, 0x01, {});
        }

        public void write_wave (uint8 direction) throws HidError {
            effect (FX_WAVE, 0x02, { direction.clamp (WAVE_LEFT, WAVE_RIGHT) });
        }

        public void write_static (uint8 r, uint8 g, uint8 b) throws HidError {
            effect (FX_STATIC, 0x04, { r, g, b });
        }

        public void write_reactive (uint8 speed, uint8 r, uint8 g, uint8 b) throws HidError {
            effect (FX_REACTIVE, 0x05, { speed.clamp (1, 4), r, g, b });
        }

        public void write_breath_single (uint8 r, uint8 g, uint8 b) throws HidError {
            effect (FX_BREATHING, 0x08, { TYPE_SINGLE, r, g, b });
        }

        public void write_breath_dual (uint8 r1, uint8 g1, uint8 b1,
                                       uint8 r2, uint8 g2, uint8 b2) throws HidError {
            effect (FX_BREATHING, 0x08, { TYPE_DUAL, r1, g1, b1, r2, g2, b2 });
        }

        public void write_breath_random () throws HidError {
            effect (FX_BREATHING, 0x08, { TYPE_RANDOM });
        }

        // Starlight declares a data size of 1 while filling nine argument
        // bytes. That is what the driver sends and what the firmware accepts;
        // it is not a bug to tidy up.
        public void write_starlight_single (uint8 speed, uint8 r, uint8 g, uint8 b) throws HidError {
            effect (FX_STARLIGHT, 0x01,
                    { TYPE_SINGLE, speed.clamp (1, 3), r, g, b, 0x00, 0x00, 0x00 });
        }

        public void write_starlight_dual (uint8 speed, uint8 r1, uint8 g1, uint8 b1,
                                          uint8 r2, uint8 g2, uint8 b2) throws HidError {
            effect (FX_STARLIGHT, 0x01,
                    { TYPE_DUAL, speed.clamp (1, 3), r1, g1, b1, r2, g2, b2 });
        }

        public void write_starlight_random (uint8 speed) throws HidError {
            effect (FX_STARLIGHT, 0x01, { TYPE_RANDOM, speed.clamp (1, 3) });
        }

        private void effect (uint8 id, uint8 size, uint8[] rest) throws HidError {
            var args = new uint8[rest.length + 1];
            args[0] = id;
            for (var i = 0; i < rest.length; i++) {
                args[i + 1] = rest[i];
            }

            var report = new RazerReport (CLASS_LIGHTING, 0x0a, size);
            report.set_args (args);
            hid.send (report);
        }
    }
}
