conf = configuration_data()
conf.set('APP_ID', app_id)
conf.set('APP_PATH', app_path)
conf.set('VERSION', meson.project_version())

config_vala = configure_file(
  input: 'config.vala.in',
  output: 'config.vala',
  configuration: conf,
)

blueprints = custom_target('blueprints',
  input: files(
    'ui/window.blp',
    'ui/widgets/effect-tile.blp',
  ),
  output: '.',
  command: [
    find_program('blueprint-compiler'),
    'batch-compile',
    '@OUTPUT@',
    '@CURRENT_SOURCE_DIR@',
    '@INPUT@',
  ],
)

resources = gnome.compile_resources('lucent-resources',
  'lucent.gresource.xml',
  source_dir: meson.current_build_dir(),
  dependencies: blueprints,
)

sources = files(
  'main.vala',
  'application.vala',
  'dbus/razer-proxies.vala',
  'dbus/razer-device.vala',
  'dbus/razer-manager.vala',
  'model/effect.vala',
  'ui/window.vala',
  'ui/widgets/effect-tile.vala',
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
