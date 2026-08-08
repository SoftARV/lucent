public class Lucent.Application : Adw.Application {

    public Application () {
        Object (application_id: Config.APP_ID,
                flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    protected override void activate () {
        if (active_window != null) {
            active_window.present ();
            return;
        }

        try {
            var device = new RazerManager ().primary ();
            if (device == null) {
                show_problem ("No Razer device", "The OpenRazer daemon is running but reported no devices.");
                return;
            }
            new Window (this, device).present ();
        } catch (Error e) {
            show_problem ("Daemon unavailable", "Could not reach the OpenRazer daemon.\n\n" + e.message);
        }
    }

    private void show_problem (string title, string detail) {
        var view = new Adw.ToolbarView ();
        view.add_top_bar (new Adw.HeaderBar ());
        view.content = new Adw.StatusPage () {
            icon_name = "dialog-warning-symbolic",
            title = title,
            description = detail,
        };

        new Adw.ApplicationWindow (this) {
            title = "Lucent",
            default_width = 420,
            default_height = 380,
            content = view,
        }.present ();
    }
}
