install_data('dev.miguel.Lucent.desktop',
  install_dir: get_option('datadir') / 'applications',
)

install_data('dev.miguel.Lucent.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo',
)

install_data('icons/hicolor/scalable/apps/dev.miguel.Lucent.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
)

install_data('icons/hicolor/symbolic/apps/dev.miguel.Lucent-symbolic.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'symbolic' / 'apps',
)

install_data('dev.miguel.Lucent.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
)

# Also compiled into the build dir so the daemon can run uninstalled with
# GSETTINGS_SCHEMA_DIR pointing at it.
gnome.compile_schemas(depend_files: files('dev.miguel.Lucent.gschema.xml'))

# Grants the hidraw node to the logged-in user; without it the daemon starts
# but reports itself unavailable. Must sort before systemd's 73-seat-late.rules,
# which is what turns the uaccess tag into an ACL -- see the file's own comment.
install_data('60-lucent-razer.rules',
  install_dir: get_option('prefix') / 'lib' / 'udev' / 'rules.d',
)

configure_file(
  input: 'lucent-daemon.service.in',
  output: 'lucent-daemon.service',
  configuration: {'BINDIR': get_option('prefix') / get_option('bindir')},
  install_dir: get_option('prefix') / 'lib' / 'systemd' / 'user',
)
