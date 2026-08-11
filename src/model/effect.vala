namespace Lucent {

    public enum Mode {
        SINGLE,
        DUAL,
        RANDOM;

        public string title () {
            switch (this) {
                case DUAL:   return "Two Colors";
                case RANDOM: return "Random";
                default:     return "One Color";
            }
        }
    }

    public enum Effect {
        OFF,
        STATIC,
        SPECTRUM,
        WAVE,
        REACTIVE,
        BREATH,
        STARLIGHT;

        public string title () {
            switch (this) {
                case STATIC:    return "Static";
                case SPECTRUM:  return "Spectrum";
                case WAVE:      return "Wave";
                case REACTIVE:  return "Reactive";
                case BREATH:    return "Breath";
                case STARLIGHT: return "Starlight";
                default:        return "Off";
            }
        }

        public string icon () {
            switch (this) {
                case STATIC:    return "color-select-symbolic";
                case SPECTRUM:  return "preferences-desktop-appearance-symbolic";
                case WAVE:      return "blend-tool-symbolic";
                case REACTIVE:  return "input-keyboard-symbolic";
                case BREATH:    return "display-brightness-symbolic";
                case STARLIGHT: return "starred-symbolic";
                default:        return "turn-off-symbolic";
            }
        }

        public Mode[] modes () {
            switch (this) {
                case BREATH:
                case STARLIGHT:
                    return { Mode.SINGLE, Mode.DUAL, Mode.RANDOM };
                default:
                    return {};
            }
        }

        public int colors (Mode mode) {
            switch (this) {
                case STATIC:
                case REACTIVE:
                    return 1;
                case BREATH:
                case STARLIGHT:
                    if (mode == Mode.RANDOM) {
                        return 0;
                    }
                    return mode == Mode.DUAL ? 2 : 1;
                default:
                    return 0;
            }
        }

        public string[] speeds () {
            switch (this) {
                case REACTIVE:  return { "500 ms", "1 s", "1.5 s", "2 s" };
                case STARLIGHT: return { "Fast", "Normal", "Slow" };
                default:        return {};
            }
        }

        public bool has_direction () {
            return this == WAVE;
        }

        // Stable name for storage. The family only -- the mode is stored
        // beside it, rather than openrazer's flat scheme where breathSingle
        // and breathDual were separate effects.
        public string id () {
            switch (this) {
                case STATIC:    return "static";
                case SPECTRUM:  return "spectrum";
                case WAVE:      return "wave";
                case REACTIVE:  return "reactive";
                case BREATH:    return "breath";
                case STARLIGHT: return "starlight";
                default:        return "off";
            }
        }

        public static Effect from_id (string id) {
            foreach (var candidate in all_effects ()) {
                if (candidate.id () == id) {
                    return candidate;
                }
            }
            return Effect.OFF;
        }
    }

    public Effect[] all_effects () {
        return {
            Effect.OFF, Effect.STATIC, Effect.SPECTRUM, Effect.WAVE,
            Effect.REACTIVE, Effect.BREATH, Effect.STARLIGHT,
        };
    }

    public void parse_effect (string id, out Effect effect, out Mode mode) {
        mode = Mode.SINGLE;

        switch (id) {
            case "static":             effect = Effect.STATIC;                        return;
            case "spectrum":           effect = Effect.SPECTRUM;                      return;
            case "wave":               effect = Effect.WAVE;                          return;
            case "reactive":           effect = Effect.REACTIVE;                      return;
            case "breathSingle":       effect = Effect.BREATH;                        return;
            case "breathDual":         effect = Effect.BREATH;    mode = Mode.DUAL;   return;
            case "breathRandom":       effect = Effect.BREATH;    mode = Mode.RANDOM; return;
            case "starlightSingle":    effect = Effect.STARLIGHT;                     return;
            case "starlightDual":      effect = Effect.STARLIGHT; mode = Mode.DUAL;   return;
            case "starlightRandom":    effect = Effect.STARLIGHT; mode = Mode.RANDOM; return;
            default:                   effect = Effect.OFF;                           return;
        }
    }
}
