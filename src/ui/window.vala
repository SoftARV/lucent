[GtkTemplate (ui = "/dev/miguel/Lucent/window.ui")]
public class Lucent.Window : Adw.ApplicationWindow {

    [GtkChild] private unowned Adw.ToastOverlay toasts;
    [GtkChild] private unowned LightingPage lighting;
    [GtkChild] private unowned PerformancePage performance;
    [GtkChild] private unowned BatteryPage battery;

    private LaptopService laptop;
    private bool torn_down = false;

    public Window (Gtk.Application app, RazerDevice device) {
        Object (application: app);

        this.title = device.name;

        // Lighting goes through the openrazer daemon; the laptop controls go
        // through ours. Two models, two transports, one window.
        laptop = new LaptopService ();

        lighting.report.connect (toast);
        performance.report.connect (toast);
        battery.report.connect (toast);

        lighting.configure (device);
        performance.configure (laptop);
        battery.configure (laptop);
    }

    public override void dispose () {
        // Pages hold debounce timers and in-flight calls whose replies would
        // otherwise land on template children that are already gone.
        if (!torn_down) {
            torn_down = true;
            lighting.shutdown ();
            performance.shutdown ();
            battery.shutdown ();
        }
        base.dispose ();
    }

    private void toast (string message) {
        toasts.add_toast (new Adw.Toast (message));
    }
}
