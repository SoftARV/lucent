[GtkTemplate (ui = "/dev/miguel/Lucent/ui/window.ui")]
public class Lucent.Window : Adw.ApplicationWindow {

    [GtkChild] private unowned Adw.ToastOverlay toasts;
    [GtkChild] private unowned Gtk.Scale brightness;
    [GtkChild] private unowned Gtk.Label brightness_value;
    [GtkChild] private unowned Gtk.Box quick;
    [GtkChild] private unowned Adw.SwitchRow logo_row;
    [GtkChild] private unowned Gtk.FlowBox effects;
    [GtkChild] private unowned Adw.PreferencesGroup options;
    [GtkChild] private unowned Adw.ComboRow mode_row;
    [GtkChild] private unowned ColorRow primary_row;
    [GtkChild] private unowned ColorRow secondary_row;
    [GtkChild] private unowned Adw.ComboRow speed_row;
    [GtkChild] private unowned Adw.ComboRow direction_row;

    private RazerDevice device;
    private Effect current = Effect.OFF;
    private Mode mode = Mode.SINGLE;
    private EffectTile[] tiles = {};
    private bool syncing = false;
    private uint brightness_debounce = 0;
    private uint apply_debounce = 0;

    public Window (Gtk.Application app, RazerDevice device) {
        Object (application: app);

        this.device = device;
        this.title = device.name;

        build_tiles ();
        build_quick_levels ();
        load_state ();
        connect_signals ();
    }

    private const int[] QUICK_LEVELS = { 0, 25, 50, 75, 100 };

    private void build_quick_levels () {
        var action = new SimpleAction ("set-brightness", VariantType.INT32);
        action.activate.connect ((parameter) => {
            if (parameter != null) {
                brightness.set_value ((double) parameter.get_int32 ());
            }
        });
        add_action (action);

        foreach (var level in QUICK_LEVELS) {
            var button = new Gtk.Button.with_label ("%d%%".printf (level));
            button.set_action_name ("win.set-brightness");
            button.set_action_target_value (new Variant.int32 (level));
            quick.append (button);
        }
    }

    public override void dispose () {
        if (brightness_debounce != 0) {
            Source.remove (brightness_debounce);
            brightness_debounce = 0;
        }
        if (apply_debounce != 0) {
            Source.remove (apply_debounce);
            apply_debounce = 0;
        }
        base.dispose ();
    }

    private void build_tiles () {
        foreach (var effect in all_effects ()) {
            var tile = new EffectTile (effect);
            tile.toggled.connect (() => {
                if (syncing) {
                    return;
                }
                if (!tile.active) {
                    highlight ();
                    return;
                }
                choose (tile.effect);
            });
            effects.append (tile);
            tiles += tile;
        }
    }

    private void load_state () {
        syncing = true;

        try {
            brightness.set_value (device.read_brightness ());
            show_brightness ();
            device.read_effect (out current, out mode);
            primary_row.set_rgba (device.read_color (0));
            secondary_row.set_rgba (device.read_color (1));
            direction_row.selected = device.read_wave_dir () == 2 ? 1 : 0;

            if (device.has_logo) {
                logo_row.visible = true;
                logo_row.active = device.read_logo_active ();
            }

            rebuild_models ();

            var speed = device.read_speed ();
            if (speed >= 1 && speed <= current.speeds ().length) {
                speed_row.selected = speed - 1;
            }
        } catch (Error e) {
            toast (e.message);
            rebuild_models ();
        }

        update_visibility ();
        highlight ();
        syncing = false;
    }

    private void connect_signals () {
        brightness.value_changed.connect (() => {
            show_brightness ();

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

        mode_row.notify["selected"].connect (() => {
            var available = current.modes ();
            if (syncing || mode_row.selected >= available.length) {
                return;
            }
            var chosen = available[mode_row.selected];
            if (chosen == mode) {
                return;
            }
            mode = chosen;
            update_visibility ();
            apply ();
        });

        primary_row.edited.connect (() => {
            if (!syncing) {
                apply ();
            }
        });

        secondary_row.edited.connect (() => {
            if (!syncing) {
                apply ();
            }
        });

        speed_row.notify["selected"].connect (() => {
            if (!syncing) {
                apply ();
            }
        });

        direction_row.notify["selected"].connect (() => {
            if (!syncing) {
                apply ();
            }
        });
    }

    private void choose (Effect effect) {
        current = effect;

        var available = effect.modes ();
        mode = available.length > 0 ? available[0] : Mode.SINGLE;

        rebuild_models ();
        update_visibility ();
        highlight ();
        apply ();
    }

    private void rebuild_models () {
        var was_syncing = syncing;
        syncing = true;

        var available = current.modes ();
        if (available.length > 0) {
            var labels = new string[available.length];
            uint index = 0;
            for (var i = 0; i < available.length; i++) {
                labels[i] = available[i].title ();
                if (available[i] == mode) {
                    index = i;
                }
            }
            mode_row.model = new Gtk.StringList (labels);
            mode_row.selected = index;
        }

        var speeds = current.speeds ();
        if (speeds.length > 0) {
            speed_row.model = new Gtk.StringList (speeds);
            speed_row.selected = 0;
        }

        syncing = was_syncing;
    }

    private void update_visibility () {
        mode_row.visible = current.modes ().length > 0;

        var count = current.colors (mode);
        primary_row.visible = count >= 1;
        secondary_row.visible = count >= 2;

        speed_row.visible = current.speeds ().length > 0;
        direction_row.visible = current.has_direction ();

        options.visible = mode_row.visible || primary_row.visible
            || speed_row.visible || direction_row.visible;
    }

    private void highlight () {
        var was_syncing = syncing;
        syncing = true;
        foreach (var tile in tiles) {
            tile.active = tile.effect == current;
        }
        syncing = was_syncing;
    }

    private void apply () {
        if (apply_debounce != 0) {
            Source.remove (apply_debounce);
        }
        apply_debounce = Timeout.add (40, () => {
            apply_debounce = 0;
            send ();
            return Source.REMOVE;
        });
    }

    private void send () {
        var speed = speed_row.visible ? (int) speed_row.selected + 1 : 1;

        try {
            device.apply (current, mode,
                          primary_row.get_rgba (), secondary_row.get_rgba (),
                          speed,
                          direction_row.selected == 1 ? 2 : 1);
        } catch (Error e) {
            toast (e.message);
        }
    }

    private void show_brightness () {
        brightness_value.label = "%.0f%%".printf (brightness.get_value ());
    }

    private void toast (string message) {
        toasts.add_toast (new Adw.Toast (message));
    }
}
