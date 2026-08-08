public class Lucent.RazerManager : Object {

    private RazerDevices proxy;

    public RazerManager () throws Error {
        proxy = Bus.get_proxy_sync<RazerDevices> (BusType.SESSION, RAZER_BUS, RAZER_PATH);
    }

    public RazerDevice? primary () throws Error {
        RazerDevice? fallback = null;

        foreach (var serial in proxy.get_devices ()) {
            try {
                var device = new RazerDevice (serial);
                if (device.is_keyboard ()) {
                    return device;
                }
                if (fallback == null) {
                    fallback = device;
                }
            } catch (Error e) {
                warning ("skipping %s: %s", serial, e.message);
            }
        }

        return fallback;
    }
}
