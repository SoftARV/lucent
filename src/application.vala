public class Lucent.Application : Adw.Application {

    public Application () {
        Object (application_id: Config.APP_ID,
                flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    protected override void startup () {
        base.startup ();

        var provider = new Gtk.CssProvider ();
        provider.load_from_resource (Config.APP_PATH + "/style.css");
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        var about_action = new SimpleAction ("about", null);
        about_action.activate.connect ((parameter) => {
            show_about ();
        });
        add_action (about_action);

        var quit_action = new SimpleAction ("quit", null);
        quit_action.activate.connect ((parameter) => {
            quit ();
        });
        add_action (quit_action);

        set_accels_for_action ("app.about", { "F1" });
        set_accels_for_action ("app.quit", { "<Control>q" });
    }

    private void show_about () {
        new Adw.AboutDialog () {
            application_name = "Lucent",
            application_icon = Config.APP_ID,
            version = Config.VERSION,
            developer_name = "Miguel Rincon",
            comments = "Control your Razer keyboard lighting.",
            website = "https://github.com/SoftARV/lucent",
            issue_url = "https://github.com/SoftARV/lucent/issues",
            license_type = Gtk.License.GPL_3_0,
            copyright = "© 2026 Miguel Rincon",
        }.present (active_window);
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
