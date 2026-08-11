conf = configuration_data()
conf.set('APP_ID', app_id)
conf.set('APP_PATH', app_path)
conf.set('VERSION', meson.project_version())

config_vala = configure_file(
  input: 'config.vala.in',
  output: 'config.vala',
  configuration: conf,
)

blueprint_compiler = find_program('blueprint-compiler')

# One target per file with an explicit output. A single batch-compile target
# writing into a directory ('output: .') is not tracked reliably: other build
# steps touch that directory, so ninja sees the output as newer than the input
# and silently skips regenerating the .ui files.
blueprint_files = {
  'window.ui': 'ui/window.blp',
  'lighting-page.ui': 'ui/pages/lighting-page.blp',
  'performance-page.ui': 'ui/pages/performance-page.blp',
  'battery-page.ui': 'ui/pages/battery-page.blp',
  'effect-tile.ui': 'ui/widgets/effect-tile.blp',
  'color-row.ui': 'ui/widgets/color-row.blp',
  'daemon-notice.ui': 'ui/widgets/daemon-notice.blp',
}

blueprints = []
foreach output_name, source_name : blueprint_files
  blueprints += custom_target(output_name,
    input: files(source_name),
    output: output_name,
    command: [blueprint_compiler, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  )
endforeach

resources = gnome.compile_resources('lucent-resources',
  'lucent.gresource.xml',
  source_dir: [meson.current_build_dir(), meson.current_source_dir()],
  dependencies: blueprints,
)

sources = files(
  'main.vala',
  'application.vala',
  'dbus/razer-proxies.vala',
  'dbus/razer-device.vala',
  'dbus/razer-manager.vala',
  'dbus/laptop-proxy.vala',
  'dbus/laptop-service.vala',
  'model/effect.vala',
  'model/power-mode.vala',
  'ui/window.vala',
  'ui/pages/lighting-page.vala',
  'ui/pages/performance-page.vala',
  'ui/pages/battery-page.vala',
  'ui/widgets/effect-tile.vala',
  'ui/widgets/color-row.vala',
  'ui/widgets/daemon-notice.vala',
)

executable('lucent',
  sources, config_vala, resources,
  dependencies: [
    dependency('glib-2.0', version: '>= 2.76'),
    dependency('gobject-2.0'),
    dependency('gio-2.0'),
    dependency('gtk4', version: '>= 4.10'),
    dependency('libadwaita-1', version: '>= 1.4'),
  ],
  vala_args: ['--gresourcesdir=' + meson.current_build_dir()],
  install: true,
)

# The daemon is a separate binary rather than a flag on the one above so it
# never links GTK or libadwaita. A process that does costs tens of megabytes
# resident whether or not it opens a window, and this one is resident from
# login onwards.
hid_sources = files(
  'hid/razer-report.vala',
  'hid/hid-device.vala',
  'hid/laptop-device.vala',
  'hid/keyboard-device.vala',
  'model/power-mode.vala',
)

daemon_sources = files(
  'daemon/main.vala',
  'daemon/daemon-service.vala',
  'daemon/sleep-monitor.vala',
  'daemon/power-source.vala',
)

executable('lucent-daemon',
  hid_sources, daemon_sources, config_vala,
  dependencies: [
    dependency('glib-2.0', version: '>= 2.76'),
    dependency('gobject-2.0'),
    dependency('gio-2.0'),
    meson.get_compiler('vala').find_library('posix'),
  ],
  install: true,
)
