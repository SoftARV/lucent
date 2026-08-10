namespace Lucent {

    // glibc declares ioctl's request as unsigned long. Vala's posix.vapi types
    // it as int, which cannot hold HIDIOCSFEATURE(91) = 0xc05b4806, so bind the
    // real signature instead of casting a truncated literal.
    [CCode (cname = "ioctl", cheader_filename = "sys/ioctl.h")]
    extern int raw_ioctl (int fd, ulong request, void* argp);

    // Feature reports are only reachable through ioctl; writing to the hidraw
    // node sends an output report instead, which the device ignores.
    public class HidDevice : Object {

        // _IOC(dir, type, nr, size) with dir = _IOC_READ|_IOC_WRITE
        private const ulong IOC_DIR = 3;
        private const ulong IOC_TYPE = 'H';

        private const int WIRE_SIZE = RazerReport.SIZE + 1;  // report id byte first
        private const int ATTEMPTS = 3;

        private int fd = -1;
        private string node;

        public string path {
            get { return node; }
        }

        private static ulong ioc (ulong nr, ulong size) {
            return (IOC_DIR << 30) | (size << 16) | (IOC_TYPE << 8) | nr;
        }

        public HidDevice (string path) throws HidError {
            node = path;

            fd = Posix.open (path, Posix.O_RDWR);
            if (fd < 0) {
                throw new HidError.NO_DEVICE ("cannot open %s: %s",
                                              path, Posix.strerror (Posix.errno));
            }
        }

        ~HidDevice () {
            if (fd >= 0) {
                Posix.close (fd);
            }
        }

        // Sends a report and returns the device's reply. Retries on transport
        // errors and on a reply that does not match the request: the openrazer
        // daemon is writing to this same control endpoint, so an interleaved
        // exchange can hand us its answer instead of ours.
        public RazerReport send (RazerReport report) throws HidError {
            report.seal ();

            uint8 out_buffer[WIRE_SIZE];
            uint8 in_buffer[WIRE_SIZE];
            unowned uint8[] payload = report.wire ();

            out_buffer[0] = 0x00;
            for (var i = 0; i < RazerReport.SIZE; i++) {
                out_buffer[i + 1] = payload[i];
            }

            string failure = "no attempt made";

            for (var attempt = 0; attempt < ATTEMPTS; attempt++) {
                if (raw_ioctl (fd, ioc (0x06, WIRE_SIZE), out_buffer) < 0) {
                    failure = "write: %s".printf (Posix.strerror (Posix.errno));
                    Thread.usleep (5000);
                    continue;
                }

                Thread.usleep (1000);

                in_buffer[0] = 0x00;
                if (raw_ioctl (fd, ioc (0x07, WIRE_SIZE), in_buffer) < 0) {
                    failure = "read: %s".printf (Posix.strerror (Posix.errno));
                    Thread.usleep (5000);
                    continue;
                }

                uint8[] wire = new uint8[RazerReport.SIZE];
                for (var i = 0; i < RazerReport.SIZE; i++) {
                    wire[i] = in_buffer[i + 1];
                }
                var response = new RazerReport.from_wire (wire);

                if (response.command_class () != report.command_class ()
                    || response.command_id () != report.command_id ()) {
                    failure = "reply was for %02x/%02x, asked %02x/%02x".printf (
                        response.command_class (), response.command_id (),
                        report.command_class (), report.command_id ());
                    Thread.usleep (5000);
                    continue;
                }

                if (response.status () == RazerReport.STATUS_UNSUPPORTED) {
                    throw new HidError.UNSUPPORTED ("device rejected %02x/%02x",
                                                    report.command_class (),
                                                    report.command_id ());
                }

                if (response.status () != RazerReport.STATUS_OK) {
                    failure = "status %s".printf (response.describe_status ());
                    Thread.usleep (5000);
                    continue;
                }

                return response;
            }

            throw new HidError.IO ("%02x/%02x failed after %d attempts: %s",
                                   report.command_class (), report.command_id (),
                                   ATTEMPTS, failure);
        }

        // Several interfaces of the same device expose a hidraw node and only
        // some answer control commands, so callers probe the candidates rather
        // than trusting an interface number. hidapi cannot report one here in
        // any case: its hidraw backend returns -1.
        public static string[] candidates (uint16 vendor_id, uint16 product_id) {
            string[] found = {};
            var wanted = "HID_ID=0003:%08X:%08X".printf (vendor_id, product_id);

            try {
                var dir = Dir.open ("/sys/class/hidraw");
                var names = new List<string> ();
                string? name;

                // Sorted only so the chosen node is stable between runs; every
                // node that answers behaves identically.
                while ((name = dir.read_name ()) != null) {
                    names.insert_sorted (name, strcmp);
                }

                foreach (var entry in names) {
                    string contents;
                    var uevent = "/sys/class/hidraw/" + entry + "/device/uevent";

                    if (!FileUtils.test (uevent, FileTest.EXISTS)) {
                        continue;
                    }
                    if (!FileUtils.get_contents (uevent, out contents)) {
                        continue;
                    }
                    if (contents.up ().contains (wanted)) {
                        found += "/dev/" + entry;
                    }
                }
            } catch (Error e) {
                warning ("cannot enumerate hidraw nodes: %s", e.message);
            }

            return found;
        }
    }
}
