namespace Lucent {

    // One way of learning whether the panel is powered, for one family of
    // compositors. GNOME answers on D-Bus, the wlroots family answers over a
    // Wayland protocol, and nothing answers for everyone -- which is why this
    // is an abstraction rather than a second branch inside one class.
    //
    // Two rules hold for every backend, and both were paid for in bugs:
    //
    //   * `present` false must report lit, never blanked. A compositor that
    //     cannot be reached is not a dark panel, and holding this blanked
    //     would strand the keyboard off with nothing left to send the wake
    //     edge.
    //
    //   * both edges must be *pushed*. A backend that can only be polled does
    //     not qualify: the daemon's measured zero idle CPU is the thing being
    //     protected, and a timer here turns that zero into a nonzero.
    public abstract class ScreenBackend : Object {

        public signal void changed ();

        // Whether this backend has something to talk to. False before the
        // compositor owns its name, and again if it goes away.
        public bool present { get; protected set; default = false; }

        public bool blanked { get; protected set; default = false; }

        // For logging which one won the probe.
        public abstract string label { get; }

        // Connecting is deliberately not done in construct, so the selector
        // can wire up `changed` before anything can fire.
        public abstract void start ();

        // Backends set this rather than assigning the two properties, so the
        // signal is emitted on exactly one condition everywhere.
        protected void publish (bool now) {
            if (now == blanked) {
                return;
            }
            blanked = now;
            changed ();
        }
    }
}
