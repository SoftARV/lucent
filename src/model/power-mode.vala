namespace Lucent {

    // Razer's own values, read off the USB wire while driving Synapse. See
    // tools/lucent-capture/ for the captures and the decoder.
    //
    // **The label depends on the power source.** "Balanced" is 0x00 plugged in
    // and 0x06 on battery -- the same word, two different values. A single
    // global table mislabels one of them, which is exactly the mistake made
    // twice while working this out: first by inferring names from CPU clock
    // alone, then by reading a battery capture as though it used the AC set.
    //
    // Verified in both directions: two captures with opposite starting modes
    // produce mirrored sequences, so a wrong mapping cannot survive both.
    public enum PowerMode {
        // plugged in
        BALANCED = 0,
        PERFORMANCE = 2,
        CUSTOM = 4,
        SILENT = 5,

        // on battery -- a different set, not a subset
        BATTERY_SAVER = 3,
        BATTERY_BALANCED = 6;

        public static string title_for (uint value, bool for_battery) {
            var own = for_battery ? battery_name (value) : ac_name (value);
            if (own != null) {
                return own;
            }

            // A value from the other source can legitimately be live: the
            // daemon writes the AC mode, you unplug, and nothing has rewritten
            // it yet. Name it, but say where it belongs.
            var other = for_battery ? ac_name (value) : battery_name (value);
            if (other != null) {
                return "%s (%s)".printf (other, for_battery ? "plugged-in mode"
                                                            : "battery mode");
            }
            return "Mode %u".printf (value);
        }

        private static string? ac_name (uint value) {
            switch (value) {
                case BALANCED: return "Balanced";
                case PERFORMANCE: return "Performance";
                case CUSTOM: return "Custom";
                case SILENT: return "Silent";
                default: return null;
            }
        }

        private static string? battery_name (uint value) {
            switch (value) {
                case BATTERY_BALANCED: return "Balanced";
                case BATTERY_SAVER: return "Battery Saver";
                default: return null;
            }
        }

        public static bool is_valid (int value) {
            return value >= 0 && value <= 7;
        }

        // What Synapse offers for each source, in its order. On battery it is
        // only two, and that is honest rather than conservative: the dGPU is
        // pinned at 65 W whatever the mode, and boost is inert, so Custom
        // would be a control that does nothing.
        public static int[] offered (bool for_battery) {
            if (for_battery) {
                return { BATTERY_BALANCED, BATTERY_SAVER };
            }
            return { BALANCED, PERFORMANCE, SILENT, CUSTOM };
        }

        // Boost registers are only honoured in Custom, measured directly: the
        // GPU power limit moves 50/80/100 W across boost levels in mode 4 and
        // does not move at all in any other mode.
        public static bool takes_boost (uint value) {
            return value == CUSTOM;
        }
    }
}
