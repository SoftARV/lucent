[GtkTemplate (ui = "/dev/miguel/Lucent/ui/window.ui")]
public class Lucent.Window : Adw.ApplicationWindow {

    [GtkChild] private unowned Adw.ToastOverlay toasts;
    [GtkChild] private unowned Gtk.Scale brightness;
    [GtkChild] private unowned Adw.SwitchRow logo_row;
    [GtkChild] private unowned Gtk.FlowBox effects;
    [GtkChild] private unowned Adw.PreferencesGroup color_group;
    [GtkChild] private unowned Gtk.ColorDialogButton color;
    [GtkChild] private unowned Adw.PreferencesGroup direction_group;
    [GtkChild] private unowned Adw.ComboRow direction;

    private RazerDevice device;
    private Effect current = Effect.OFF;
    private EffectTile[] tiles = {};
    private bool syncing = false;
    private uint brightness_debounce = 0;

    public Window (Gtk.Application app, RazerDevice device) {
        Object (application: app);

        this.device = device;
        this.title = device.name;

        build_tiles ();
        load_state ();
        connect_signals ();
    }

    private void build_tiles () {
        foreach (var effect in all_effects ()) {
            var tile = new EffectTile (effect);
            tile.toggled.connect (() => {
                if (syncing || !tile.active) {
                    return;
                }
                select (tile.effect);
            });
            effects.append (tile);
            tiles += tile;
        }
    }

    private void load_state () {
        syncing = true;

        try {
            brightness.set_value (device.read_brightness ());
            current = device.read_effect ();
            color.set_rgba (device.read_color ());
            direction.selected = device.read_wave_dir () == 2 ? 1 : 0;

            if (device.has_logo) {
                logo_row.visible = true;
                logo_row.active = device.read_logo_active ();
            }
        } catch (Error e) {
            toast (e.message);
        }

        highlight ();
        update_rows ();
        syncing = false;
    }

    private void connect_signals () {
        brightness.value_changed.connect (() => {
            if (syncing) {
                return;
            }
            if (brightness_debounce != 0) {
                Source.remove (brightness_debounce);
            }
            brightness_debounce = Timeout.add (60, () => {
                brightness_debounce = 0;
                try {
                    device.write_brightness (brightness.get_value ());
                } catch (Error e) {
                    toast (e.message);
                }
                return Source.REMOVE;
            });
        });

        logo_row.notify["active"].connect (() => {
            if (syncing) {
                return;
            }
            try {
                device.write_logo_active (logo_row.active);
            } catch (Error e) {
                toast (e.message);
            }
        });

        color.notify["rgba"].connect (() => {
            if (!syncing && current.needs_color ()) {
                apply ();
            }
        });

        direction.notify["selected"].connect (() => {
            if (!syncing && current.needs_direction ()) {
                apply ();
            }
        });
    }

    private void select (Effect effect) {
        current = effect;
        highlight ();
        update_rows ();
        apply ();
    }

    private void highlight () {
        var was_syncing = syncing;
        syncing = true;
        foreach (var tile in tiles) {
            tile.active = tile.effect == current;
        }
        syncing = was_syncing;
    }

    private void update_rows () {
        color_group.visible = current.needs_color ();
        direction_group.visible = current.needs_direction ();
    }

    private Gdk.RGBA selected_color () {
        unowned Gdk.RGBA? rgba = color.get_rgba ();
        if (rgba != null) {
            return rgba;
        }
        return Gdk.RGBA () { red = 0, green = 1, blue = 1, alpha = 1 };
    }

    private void apply () {
        try {
            device.apply (current, selected_color (), direction.selected == 1 ? 2 : 1);
        } catch (Error e) {
            toast (e.message);
        }
    }

    private void toast (string message) {
        toasts.add_toast (new Adw.Toast (message));
    }
}
