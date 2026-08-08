[GtkTemplate (ui = "/dev/miguel/Lucent/ui/widgets/effect-tile.ui")]
public class Lucent.EffectTile : Gtk.ToggleButton {

    public Effect effect { get; construct; }
    public string icon { get; construct; }
    public string title { get; construct; }

    public EffectTile (Effect effect) {
        Object (effect: effect,
                icon: effect.icon (),
                title: effect.title ());
    }
}
