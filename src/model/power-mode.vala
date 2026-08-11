namespace Lucent {

    // These are Razer's own values, read off the USB wire while driving
    // Synapse -- see tools/lucent-capture/. Not inferred: Balanced and
    // Performance were caught alternating five times, Silent and Custom twice
    // each across two separate sessions.
    //
    // Earlier releases had SILENT as 3, inferred from CPU clock alone. That
    // was wrong. Silent and the mode at 3 sit within 1 MHz of each other on
    // the CPU and differ almost entirely in graphics power, so nothing short
    // of the capture could have separated them.
    //
    // Values 1, 3, 6 and 7 are accepted by the EC and behave distinctly, but
    // Synapse never sends them on AC. 3 is not junk though: it appears in
    // Synapse's startup enumeration, and it is one of the two values Synapse
    // uses on battery.
    public enum PowerMode {
        BALANCED = 0,
        PERFORMANCE = 2,
        CUSTOM = 4,
        SILENT = 5;

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

        // Returns raw values rather than enum members because the battery set
        // includes one that has no name yet.
        //
        // Battery is deliberately untouched here. Synapse uses a different
        // pair of values unplugged, 3 and 6, but which is Balanced and which
        // is Battery Saver is not established: the capture that recorded it
        // assumed which button was pressed first, and the opposite reading
        // fits the measured behaviour better -- 3 clocks 450 MHz *below* 6,
        // and a saver that runs faster than balanced is backwards. One clean
        // capture settles it; until then this stays as it was rather than
        // encoding a mapping that is probably inverted.
        public static int[] offered (bool for_battery) {
            if (for_battery) {
                return { BALANCED, 3 };
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
