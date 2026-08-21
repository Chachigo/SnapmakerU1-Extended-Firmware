# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

**A host-side firmware repacker, not a firmware source tree.** It downloads
Snapmaker's stock `U1_*_upgrade.bin`, unpacks the Rockchip image, unsquashes the
rootfs, applies a stack of *overlays* into it, then re-squashes and repacks a
new `.bin` the user flashes. Nothing here is compiled into a kernel or an init
system from source; almost everything is a patch, a file drop, or a shell script
that runs against the unpacked rootfs.

Two execution contexts, and confusing them is the most common mistake:

| | Host (build machine, in Docker, as root) | Printer (ARM64, BusyBox init) |
| --- | --- | --- |
| Runs | `dev.sh`, `Makefile`, `scripts/**`, overlay `scripts/` | `/etc/init.d/S*`, Python daemons, Moonraker components |
| Tools | GNU coreutils, GNU find, bash 5 | **BusyBox** `find`/`grep`/`sed`/`tar`, coreutils `sha256sum`/`sort`/`cp`/`mkdir`, real bash |
| Persists | yes | **no** — see below |

## Commands

```bash
./dev.sh make build PROFILE=extended       # the main build; output firmware/firmware.bin
./dev.sh make build PROFILE=extended-chachigo   # ... plus the mods/chachigo overlays
./dev.sh make mods                         # list available firmwares and mods
./dev.sh make overlays PROFILE=extended    # print the exact overlay list a profile resolves to
./dev.sh make firmware                     # download + checksum the stock bin
./dev.sh make extract                      # unpack stock firmware to tmp/extracted-<version>/
./dev.sh make test                         # C tool tests (make -C tools test)
./dev.sh bash                              # shell inside the build container
./dev.sh ./scripts/dev/upgrade-firmware.sh root@<ip> extended   # build and push over SSH
```

`dev.sh` builds `.github/dev/Dockerfile` and re-execs the command inside it with
the repo bind-mounted at the same path. `create_firmware.sh` refuses to run as
non-root, so it must go through the container.

*If the Docker daemon is unavailable here, rootless podman works and gives uid 0
inside the container:*
`podman build -t snapmaker-u1-dev .github/dev && podman run --rm -w "$PWD" -v "$PWD:$PWD" snapmaker-u1-dev make build PROFILE=extended`

### Tests

There is no repo-wide test runner. `make test` only covers `tools/`. Individual
overlays keep their own checks under `<overlay>/test/`, run directly and by
convention only — **CI does not run them**:

```bash
./overlays/firmware-extended/03-plugins/test/run.sh
python3 overlays/mods/chachigo/02-ntfy/test/ntfy_test.py
```

CI (`.github/workflows/pull_request.yaml`) builds **only `PROFILE=extended`**.
Mods are never built or tested in CI.

## Overlays

`PROFILE` is parsed on `-`: first token is the firmware name, the rest are mod
names (`Makefile:11-18`). Overlay directories are discovered with `wildcard`, so
**a new overlay directory needs no registration** — just create it.

Applied in this order: `overlays/common/*/`, then
`overlays/firmware-<name>/*/`, then `overlays/mods/<mod>/*/` for each mod in the
order given. Within each numbered overlay directory:

```
pre-scripts/*.sh  →  patches/**.patch (patch -p1)  →  root/. copied into rootfs  →  scripts/*.sh
```

- `root/` mirrors the rootfs. **Modes are not fixed up on copy** — commit init
  scripts and binaries already `chmod 755`.
- `patches/` paths mirror the firmware path; generate against `make extract`
  output and trim to the needed hunks.
- `scripts/` run in the `create_firmware.sh` environment (`$ROOTFS_DIR`,
  `$CREATE_FIRMWARE`, `scripts/helpers` on `PATH`). Use them only for what a
  file copy or patch cannot express.

A build guard fails if any non-ARM ELF binary ends up in the rootfs.

## Runtime architecture on the printer

**The rootfs is an overlayfs whose upper (`/oem/overlay`) is wiped on every
boot** unless `/oem/.debug` exists (`/etc/init.d/S01aoverlayfs`). Only `/oem`
and `printer_data` persist. Anything that must survive a reboot either lives
under `/oem` or is re-created at each boot by an init script.

Nothing in this firmware has a plugin registry. Every extension point is a glob
over a directory, which is why adding a feature is almost always a file drop:

| Drop a file at | Picked up by |
| --- | --- |
| `home/lava/moonraker/moonraker/components/<n>.py` | Moonraker, when a config section of that name exists |
| `usr/local/share/firmware-config/extended/moonraker/NN_<n>.cfg` | `S49extended-config` copies it out; `[include extended/moonraker/*.cfg]` |
| `usr/local/share/firmware-config/functions/NN_<n>.yaml` | `load_functions_from_dir()` deep-merges every YAML |
| `etc/nginx/fluidd.d/<n>.conf` | `include /etc/nginx/fluidd.d/*.conf` in the stock vhost |
| `etc/hooks/{klipper,moonraker,lmd}.d/*.sh` | **sourced** (not executed) by the stock init script, action in `$1` |
| `usr/local/share/extended-pkg/<n>` | `extended-pkg`, for pinned third-party binaries |

`S49extended-config` copies `usr/local/share/firmware-config/extended/` into
`printer_data/config/extended/` with `cp -rn` — it never overwrites a user's
edit, and it keeps `.default` copies of anything that differs. Because
`printer_data` outlives a flash, **removing a feature from the firmware leaves
its `.cfg` behind**, which Moonraker then reports as an unparsed section.
`force-cleanup.sha256` is the project's mechanism for retiring such files.

### Two config layers

- `extended2.cfg` (INI, in `printer_data/config/extended/`), read and written by
  `extended-config.py` (`get`/`add`/`comment`/`uncomment`). Init scripts gate
  themselves on it.
- `firmware-config/functions/*.yaml`, the schema for the web UI at
  `/firmware-config/` (`links`, `settings`, `actions`, `quick_actions`,
  `status`). Documented in `docs/firmware_config.md`.

Both are runtime. **There is no build-time feature toggle** — what goes in an
image is decided entirely by `PROFILE`.

### Plugins

`overlays/firmware-extended/03-plugins/` adds runtime-installable community
plugins. A plugin is the same `root/` tree an overlay ships, packed as a
tarball, stored in `/oem/plugins/<name>/` and re-copied into the live rootfs at
each boot by `S48zextended-plugins`. See `docs/plugins.md` and
`docs/plugin_development.md`; `scripts/dev/make-plugin.sh` packs one.

Mods and plugins are the same layout at different points in the pipeline: a mod
becomes a plugin by adding a `plugin.conf`, with no change to how it builds.

## Gotchas that have already cost time

- **BusyBox `find` has no `-printf`** and no `-xtype`. Use
  `find . -type f | sed 's|^\./||'`. `grep`, `sed` and `tar` are BusyBox too;
  `sha256sum`, `sort`, `cp`, `mkdir`, `rmdir` are coreutils.
- **`local a=$1 b="$a/x"` breaks under `set -u`** in bash 5: `local` declares
  every name before running any assignment, so `$a` is unbound on the same line.
  Split the declaration.
- **Never `restart` nginx from anything reachable through the web UI.**
  `S50nginx restart` is stop/start and kills in-flight connections, including
  the one streaming the response. `S50nginx reload` is graceful and is enough to
  pick up a new `fluidd.d/*.conf`.
- **`firmware-config.py` reads `functions/*.yaml` once at startup.** Code that
  adds a YAML at runtime must trigger a re-read; restarting the daemon from one
  of its own requests kills that request.
- **`pack_firmware.sh` refuses to overwrite an existing output** — and only
  checks at the very end, after the whole build. Clear `firmware/firmware.bin`
  first. If a build fails only there, re-run `pack_firmware.sh` alone rather
  than rebuilding: `create_firmware.sh` *appends* the git SHA to
  `UPFILE_VERSION`, so a full re-run writes it twice.
- `/etc/BUILD_VERSION` is a `git describe` string (`0.9.0-…-gabcdef0` on a
  release, `<branch>-<abbrev>` on a dev build). Only the first form is
  comparable.

## Docs

User docs in `docs/` are a Jekyll site published to Cloudflare Pages.
`docs/design/` holds the architecture notes worth reading before touching a
subsystem: `service_hooks.md`, `third_party.md`, `rfid.md`, `spoolman.md`.

## License

GPL-3.0. `CONTRIBUTING.md` requires contributors to certify sole ownership of
their changes; individual components under `tools/` may carry their own license.
