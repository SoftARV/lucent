[CCode (cheader_filename = "wlr-screen.h")]
namespace Lucent.Wlr {

    [Compact]
    [CCode (cname = "LucentWlr", free_function = "lucent_wlr_close", has_type_id = false)]
    public class Connection {

        [CCode (cname = "lucent_wlr_open")]
        public static Connection? open (out int connected);

        [CCode (cname = "lucent_wlr_fd")]
        public int fd ();

        [CCode (cname = "lucent_wlr_dispatch")]
        public int dispatch ();

        [CCode (cname = "lucent_wlr_blanked")]
        public int blanked ();

        [CCode (cname = "lucent_wlr_usable")]
        public int usable ();
    }
}
