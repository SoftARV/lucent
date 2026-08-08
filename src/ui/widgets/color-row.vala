[GtkTemplate (ui = "/dev/miguel/Lucent/color-row.ui")]
public class Lucent.ColorRow : Adw.ActionRow {

    [GtkChild] private unowned Gtk.ColorDialogButton button;

    public signal void edited ();

    construct {
        button.notify["rgba"].connect (() => {
            edited ();
        });
    }

    public Gdk.RGBA get_rgba () {
        unowned Gdk.RGBA? rgba = button.get_rgba ();
        if (rgba != null) {
            return rgba;
        }
        return Gdk.RGBA () { red = 0, green = 1, blue = 1, alpha = 1 };
    }

    public void set_rgba (Gdk.RGBA color) {
        button.set_rgba (color);
    }
}
