namespace Lucent {

    // Picks a backend and republishes it, so the rest of the daemon asks one
    // object whether the panel is lit and never learns which desktop it is on.
    //
    // Selection is by probing rather than by reading XDG_CURRENT_DESKTOP: the
    // variable is set by whoever launched the session and describes intent, not
    // what is actually running and answering. Backends are re-evaluated every
    // time one of them changes presence, which is what already lets the Mutter
    // path recover by itself when the shell restarts underneath the daemon.
    public class ScreenMonitor : Object {

        public signal void changed ();

        public bool blanked { get; private set; default = false; }

        // False until some backend has something to talk to. Nothing consumes
        // this yet; it is what a UI would need to explain a toggle that cannot
        // do anything on this desktop.
        public bool present { get; private set; default = false; }

        private ScreenBackend[] backends;

        construct {
            // Mutter first: on GNOME it is the accurate answer, and GNOME does
            // not implement the wlroots protocol anyway, so the two never both
            // report present.
            backends = { new MutterBackend (), new WlrBackend () };

            foreach (var backend in backends) {
                backend.changed.connect (reevaluate);
                backend.notify["present"].connect (reevaluate);
            }

            // Started only once every signal is wired, so nothing can fire
            // into a half-built selector.
            foreach (var backend in backends) {
                backend.start ();
            }

            reevaluate ();
        }

        private void reevaluate () {
            ScreenBackend? active = null;

            foreach (var backend in backends) {
                if (backend.present) {
                    active = backend;
                    break;
                }
            }

            if (active != null && !present) {
                message ("following the screen via %s", active.label);
            }

            present = active != null;

            // No backend means lit. This is the invariant the whole design
            // rests on -- see ScreenBackend.
            var now = active != null && active.blanked;

            if (now != blanked) {
                blanked = now;
                changed ();
            }
        }
    }
}
