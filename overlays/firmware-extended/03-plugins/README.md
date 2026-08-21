# 03-plugins

Runtime plugin manager: lets a user install a third-party feature onto a
flashed printer, without rebuilding the firmware.

A plugin is the same `root/` tree an overlay ships, packed as a tarball. Every
extension point in this firmware is a glob over a directory — Moonraker
components, `extended/moonraker/*.cfg`, `fluidd.d/*.conf`,
`firmware-config/functions/*.yaml`, `/etc/hooks/*.d/*.sh` — so applying a
plugin is only a matter of putting its files in place. There is no registry
and no plugin API.

## Files

| Path | Role |
| --- | --- |
| `root/usr/local/bin/extended-plugin` | install / remove / enable / disable / list / apply |
| `root/etc/init.d/S48zextended-plugins` | runs `extended-plugin apply` at boot |
| `root/usr/local/share/firmware-config/functions/31_plugins.yaml` | the two install endpoints the web UI posts to |
| `test/run.sh` | host-side tests, no printer needed |

The web UI lives in `02-firmware-config` (the Plugins card in `html/index.html`,
`/api/plugins*` in `firmware-config.py`), since that is the daemon already
running as root behind Moonraker authentication.

## Why files are copied, not symlinked

The rootfs is an overlayfs whose upper is wiped on every boot unless
`/oem/.debug` exists, so `/oem/plugins` is the source of truth and `apply`
re-copies the trees at each boot. Symlinking instead would collide with
`S49extended-config`, which prunes broken symlinks and copies config defaults
with `cp -rn` — a symlinked `.cfg` would end up being edited inside the plugin
directory rather than in the user's config.

## Ordering

`S48zextended-plugins` sorts after `S48setup-lava-env` and before
`S49extended-config`, so a plugin's config defaults are in place in time for
S49 to copy them into `printer_data`, and before nginx, Moonraker and
firmware-config start. S49 needs no knowledge of plugins for this to work.

## Safety

- `apply` refuses to overwrite any file it does not own, and never exits
  non-zero: a broken third-party plugin must not stop the printer from booting.
- `plugins-disable.txt` on a USB stick makes every plugin inert for that boot.
- Installs verify a SHA256 when the user supplies one, and print the hash when
  they do not.

Plugins run as root. That is a documented property, not an oversight — see
`docs/plugins.md`.

## Docs

- `docs/plugins.md` — installing and troubleshooting
- `docs/plugin_development.md` — writing and publishing one
