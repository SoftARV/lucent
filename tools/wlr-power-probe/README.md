# wlr output power probe

Stage 0 of `docs/screen-follow-portability.md`. Answers on hardware what the
wlroots power protocol only promises on paper, before any of it is built into
`lucent-daemon`.

```sh
make
./probe 30            # watch for 30 s, then blank the panel by any means
./run-cycle.sh        # or drive one full DPMS cycle automatically
```

It is **read-only**: it never calls `set_mode`, so it cannot itself be what
turns a panel off. `run-cycle.sh` does drive the panel, via Hyprland's
dispatcher, and restores it from an `EXIT` trap.

`wlr-output-power-management-unstable-v1.xml` is vendored from wlr-protocols
(MIT, © 2019 Purism SPC) so this builds without that package installed.

Results are recorded in `docs/screen-follow-portability.md`.
