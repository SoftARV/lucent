namespace Lucent {

    public enum Effect {
        OFF,
        STATIC,
        SPECTRUM,
        WAVE;

        public string id () {
            switch (this) {
                case STATIC:   return "static";
                case SPECTRUM: return "spectrum";
                case WAVE:     return "wave";
                default:       return "none";
            }
        }

        public string title () {
            switch (this) {
                case STATIC:   return "Static";
                case SPECTRUM: return "Spectrum";
                case WAVE:     return "Wave";
                default:       return "Off";
            }
        }

        public string icon () {
            switch (this) {
                case STATIC:   return "color-select-symbolic";
                case SPECTRUM: return "preferences-desktop-appearance-symbolic";
                case WAVE:     return "media-playlist-repeat-symbolic";
                default:       return "weather-clear-night-symbolic";
            }
        }

        public bool needs_color () {
            return this == STATIC;
        }

        public bool needs_direction () {
            return this == WAVE;
        }
    }

    public Effect[] all_effects () {
        return { Effect.OFF, Effect.STATIC, Effect.SPECTRUM, Effect.WAVE };
    }

    public Effect effect_from_id (string id) {
        foreach (var e in all_effects ()) {
            if (e.id () == id) {
                return e;
            }
        }
        return Effect.OFF;
    }
}
