namespace Lucent {

    // The wlroots family -- Hyprland, sway, river, Wayfire -- answers over
    // zwlr_output_power_manager_v1 rather than on D-Bus. It reports a mode per
    // output, and the protocol says the event arrives "the reason can be a
    // client using set_mode or the compositor deciding to change an output's
    // mode", which is what makes it usable: on Omarchy the blank comes from
    // the shell's idle timer, not from anything of ours.
    //
    // Measured on Hyprland 0.56.2: the current state arrives on object
    // creation the way Mutter's PowerSaveMode read does, then both edges are
    // pushed -- OFF at t+20.07 s and ON at t+30.72 s of a driven cycle, to a
    // client with no surface, with no `failed` event from anything holding the
    // output exclusively.
    public class WlrBackend : ScreenBackend {

        // The compositor can be seconds behind us: this daemon is
        // WantedBy=default.target and was measured going active a full second
        // before Hyprland started. The ladder is bounded and stops for good
        // once it connects or gives up, so the daemon still has no standing
        // timer -- the same shape as the hidraw acquire ladder.
        private const int RETRY_SECONDS = 2;
        private const int RETRY_LIMIT = 15;

        private Wlr.Connection? wlr = null;
        private uint source = 0;

        public override string label {
            get { return "wlr-output-power"; }
        }

        public override void start () {
            attempt (0);
        }

        private void attempt (int n) {
            int connected;
            wlr = Wlr.Connection.open (out connected);

            if (wlr != null) {
                watch ();
                return;
            }

            // Connected, but the compositor has no such protocol. That is not
            // a race, it is the wrong desktop, and retrying would burn a timer
            // forever on GNOME.
            if (connected != 0) {
                return;
            }

            if (n >= RETRY_LIMIT) {
                return;
            }

            Timeout.add_seconds (RETRY_SECONDS, () => {
                attempt (n + 1);
                return Source.REMOVE;
            });
        }

        private void watch () {
            // No output has usable power control -- something else may hold
            // them exclusively. Claiming the panel is lit would be a guess, so
            // the backend stays absent and the selector moves on.
            if (wlr.usable () == 0) {
                wlr = null;
                return;
            }

            var channel = new IOChannel.unix_new (wlr.fd ());
            source = channel.add_watch (IOCondition.IN | IOCondition.HUP | IOCondition.ERR, on_readable);

            present = true;
            publish (wlr.blanked () != 0);
        }

        private bool on_readable (IOChannel channel, IOCondition condition) {
            if (wlr == null) {
                return Source.REMOVE;
            }

            if ((condition & (IOCondition.HUP | IOCondition.ERR)) != 0
                || wlr.dispatch () < 0) {
                lost ();
                return Source.REMOVE;
            }

            if (wlr.usable () == 0) {
                lost ();
                return Source.REMOVE;
            }

            publish (wlr.blanked () != 0);
            return Source.CONTINUE;
        }

        // A compositor that went away is not a blanked panel. Reporting dark
        // here would strand the keyboard off with nothing left to send the
        // wake edge, which is the invariant every backend owes.
        private void lost () {
            wlr = null;
            source = 0;
            present = false;
            publish (false);
        }

        public override void dispose () {
            if (source != 0) {
                Source.remove (source);
                source = 0;
            }
            wlr = null;
            base.dispose ();
        }
    }
}
