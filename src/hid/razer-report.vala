namespace Lucent {

    public errordomain HidError {
        NO_DEVICE,
        IO,
        UNSUPPORTED,
        BAD_RESPONSE,
    }

    // Every Razer command rides on the same 90-byte report. Byte offsets match
    // the daemon's razer_report struct. The report is packed by hand rather
    // than mapped onto a Vala struct so no compiler padding can creep in.
    //
    //   0      status
    //   1      transaction id
    //   2..3   remaining packets
    //   4      protocol type
    //   5      data size
    //   6      command class
    //   7      command id
    //   8..87  arguments
    //   88     crc
    //   89     reserved
    public class RazerReport : Object {

        public const int SIZE = 90;
        public const int ARGS = 8;
        public const int ARGS_LENGTH = 80;

        public const uint8 TRANSACTION_ID = 0x1f;

        public const uint8 STATUS_NEW = 0x00;
        public const uint8 STATUS_BUSY = 0x01;
        public const uint8 STATUS_OK = 0x02;
        public const uint8 STATUS_FAILURE = 0x03;
        public const uint8 STATUS_TIMEOUT = 0x04;
        public const uint8 STATUS_UNSUPPORTED = 0x05;

        private uint8[] data;

        public RazerReport (uint8 command_class, uint8 command_id, uint8 data_size) {
            data = new uint8[SIZE];
            data[0] = STATUS_NEW;
            data[1] = TRANSACTION_ID;
            data[5] = data_size;
            data[6] = command_class;
            data[7] = command_id;
        }

        public RazerReport.from_wire (uint8[] wire) {
            data = new uint8[SIZE];
            for (var i = 0; i < SIZE && i < wire.length; i++) {
                data[i] = wire[i];
            }
        }

        public unowned uint8[] wire () {
            return data;
        }

        public uint8 status () {
            return data[0];
        }

        public uint8 command_class () {
            return data[6];
        }

        public uint8 command_id () {
            return data[7];
        }

        public uint8 arg (int index) {
            return data[ARGS + index];
        }

        public void set_args (uint8[] values) {
            for (var i = 0; i < values.length && i < ARGS_LENGTH; i++) {
                data[ARGS + i] = values[i];
            }
        }

        // XOR of everything between the transaction id and the crc. The Blade
        // firmware ignores this field -- razer-ctl never fills it in and works
        // regardless -- but a correct one costs nothing.
        public void seal () {
            uint8 crc = 0;
            for (var i = 2; i < 88; i++) {
                crc ^= data[i];
            }
            data[88] = crc;
        }

        public string describe_status () {
            switch (status ()) {
                case STATUS_NEW: return "new";
                case STATUS_BUSY: return "busy";
                case STATUS_OK: return "ok";
                case STATUS_FAILURE: return "failure";
                case STATUS_TIMEOUT: return "timeout";
                case STATUS_UNSUPPORTED: return "not supported";
                default: return "unknown (0x%02x)".printf (status ());
            }
        }
    }
}
