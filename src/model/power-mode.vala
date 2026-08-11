namespace Lucent {

    // The values are the EC's. The names are what each one measurably does,
    // not Razer's -- those turned out to be unobtainable, because Synapse only
    // changes the live mode from its own config and that dies at the next
    // boot. See the Laptop control section of CLAUDE.md for the measurements.
    //
    // Only four of the eight accepted values are worth offering. 1 is
    // identical to PERFORMANCE in every measurement, and 5, 6 and 7 pair a low
    // CPU clock with a low GPU limit or, in 7's case, run hottest of all for a
    // marginal gain.
    public enum PowerMode {
        BALANCED = 0,
        PERFORMANCE = 2,
        SILENT = 3,
        CUSTOM = 4;

        public string title () {
            return title_for (this);
        }

        // Takes any byte the EC might report, not just the four offered, so a
        // device sitting on 6 reads as "Mode 6" rather than "Unknown".
        public static string title_for (uint value) {
            switch (value) {
                case BALANCED: return "Balanced";
                case PERFORMANCE: return "Performance";
                case SILENT: return "Silent";
                case CUSTOM: return "Custom";
                default: return "Mode %u".printf (value);
            }
        }

        public static bool is_valid (int value) {
            return value >= 0 && value <= 7;
        }

        // On battery the dGPU is pinned at 65 W whatever the mode, and boost
        // is inert, so only the two that still differ on the CPU side are
        // offered there. Anything else would be a control that does nothing.
        public static PowerMode[] offered (bool for_battery) {
            if (for_battery) {
                return { BALANCED, SILENT };
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
