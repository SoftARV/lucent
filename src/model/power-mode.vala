namespace Lucent {

    // Shared by the daemon, which writes these to the EC, and the GUI, which
    // labels them. Lives here rather than in src/hid/ because src/hid/ is
    // compiled into the daemon only.
    public enum PowerMode {
        BALANCED = 0,
        GAMING = 1,
        CREATOR = 2,
        SILENT = 3,
        CUSTOM = 4;

        public string title () {
            switch (this) {
                case BALANCED: return "Balanced";
                case GAMING: return "Gaming";
                case CREATOR: return "Creator";
                case SILENT: return "Silent";
                case CUSTOM: return "Custom";
                default: return "Unknown";
            }
        }

        public static bool is_valid (int value) {
            return value >= BALANCED && value <= CUSTOM;
        }
    }
}
