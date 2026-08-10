[GtkTemplate (ui = "/dev/miguel/Lucent/lighting-page.ui")]
public class Lucent.LightingPage : Adw.PreferencesPage {

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

    public signal void report (string message);

    private RazerDevice device;
    private Effect current = Effect.OFF;
    private Mode mode = Mode.SINGLE;
    private EffectTile[] tiles = {};
    private bool syncing = false;
    private bool closing = false;
    private uint brightness_debounce = 0;
    private uint apply_debounce = 0;

    private const int[] QUICK_LEVELS = { 0, 25, 50, 75, 100 };

    public void configure (RazerDevice device) {
        this.device = device;

        build_tiles ();
        build_quick_levels ();
        load_state ();
        connect_signals ();
    }

    // Called by the window before its template children go away, so in-flight
    // replies cannot touch dead widgets.
    public void shutdown () {
        closing = true;

        if (brightness_debounce != 0) {
            Source.remove (brightness_debounce);
            brightness_debounce = 0;
        }
        if (apply_debounce != 0) {
            Source.remove (apply_debounce);
            apply_debounce = 0;
        }
    }

    private void build_quick_levels () {
        var action = new SimpleAction ("set-brightness", VariantType.INT32);
        action.activate.connect ((parameter) => {
            if (parameter != null) {
                brightness.set_value ((double) parameter.get_int32 ());
            }
        });

        // Added to the window, not to a group on this page. GtkApplicationWindow
        // exports its action group on the session bus, which is what makes
        // brightness settable from busctl without simulating clicks; a
        // page-local group is not exported.
        var window = get_root () as Gtk.ApplicationWindow;
        if (window != null) {
            window.add_action (action);
        }

        foreach (var level in QUICK_LEVELS) {
            var button = new Gtk.Button.with_label ("%d%%".printf (level));
            button.set_action_name ("win.set-brightness");
            button.set_action_target_value (new Variant.int32 (level));
            quick.append (button);
        }
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
            report (e.message);
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
                device.write_brightness.begin (brightness.get_value (), (obj, res) => {
                    try {
                        device.write_brightness.end (res);
                    } catch (Error e) {
                        fail (e);
                    }
                });
                return Source.REMOVE;
            });
        });

        logo_row.notify["active"].connect (() => {
            if (syncing) {
                return;
            }
            device.write_logo_active.begin (logo_row.active, (obj, res) => {
                try {
                    device.write_logo_active.end (res);
                } catch (Error e) {
                    fail (e);
                }
            });
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

        device.apply.begin (current, mode,
                            primary_row.get_rgba (), secondary_row.get_rgba (),
                            speed,
                            direction_row.selected == 1 ? 2 : 1,
                            (obj, res) => {
            try {
                device.apply.end (res);
            } catch (Error e) {
                fail (e);
            }
        });
    }

    private void fail (Error e) {
        if (!closing) {
            report (e.message);
        }
    }

    private void show_brightness () {
        brightness_value.label = "%.0f%%".printf (brightness.get_value ());
    }
}
