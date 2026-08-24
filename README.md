# Snapmaker U1 Extended Firmware — Community Plugins

The [Snapmaker U1 Extended Firmware](https://github.com/paxx12-snapmaker-u1/SnapmakerU1-Extended-Firmware),
unchanged, plus one addition: **community plugins**.

A plugin is a firmware feature you install on a printer that is already
flashed — no rebuild, no reflash, from the author's own repository. It lets
people publish features that don't belong in an official release but that
others still want.

This is a fork. Everything else — the camera stack, Fluidd and Mainsail, RFID,
Spoolman, the VPN and cloud integrations, Klipper tweaks — is the upstream
project's work and behaves exactly as it does there.

> **Not affiliated with Snapmaker.** Neither is the upstream project.
>
> **Warning**: While installing custom firmware does not automatically void the
> product warranty, any damage caused by or attributable to the installation or
> use of custom firmware is not covered under warranty. Use at your own risk.
> See [Snapmaker Terms of Use](https://www.snapmaker.com/terms-of-use).
>
> If you hit a problem, reproduce it on stock firmware before contacting
> Snapmaker support. Report it here, not to upstream, unless you can reproduce
> it on an unmodified upstream build.

## What this fork adds

A runtime plugin manager. Nothing else.

- Install a plugin from a URL or by uploading a `.tar.gz`, from
  **Firmware Config → Plugins**, or over SSH with `extended-plugin`.
- Enable, disable and remove plugins without rebuilding the firmware.
- Optional SHA256 verification of what you download.
- Plugins survive reboots and firmware upgrades; they live on the persistent
  `/oem` partition and are re-applied at each boot.

A plugin uses the same layout an overlay does, so an existing
[mod](docs/mods.md) becomes a plugin by adding one file. Authors publish from
their own repository, on their own schedule.

- [Plugins](docs/plugins.md) — installing, troubleshooting, the security model
- [Writing a Plugin](docs/plugin_development.md) — the six extension points,
  the manifest, packaging and publishing

**Plugins run as root and are not reviewed by this project or by upstream.**
Install only what you trust. `docs/plugins.md` is explicit about this.

## Available plugins

Plugins live in their own repositories, on their author's own release schedule.
Install one from **Firmware Config → Plugins** using the `.tar.gz` URL and
SHA256 published with its release.

- **[Schedule Print](https://github.com/Chachigo/snapmaker-u1-schedule-print)**
  — start a print job at a chosen time.

Written one? [Writing a Plugin](docs/plugin_development.md) covers the layout,
the manifest and publishing. Open an issue to have it listed here.

## Install

Download the `.bin` from [Releases](../../releases), put it on a FAT32 USB
stick, then on the printer: `Settings` → `About` → `Firmware Version` →
`Local Update`.

See the upstream [Installation Guide](docs/install.md) for the full procedure,
and [Recovery](docs/firmware_config.md) if something goes wrong.

To go back, flash any build from
[upstream's releases](https://github.com/paxx12-snapmaker-u1/SnapmakerU1-Extended-Firmware/releases)
or the stock firmware from the
[Snapmaker U1 Wiki](https://wiki.snapmaker.com/en/snapmaker_u1/firmware/release_notes).
Your installed plugins stay in `/oem/plugins/` across a reflash; remove that
directory to be rid of them.

## Build from source

Identical to upstream — the plugin manager is a normal overlay under
`overlays/firmware-extended/`, included in every build:

```bash
./dev.sh make build PROFILE=extended
```

See [Building from Source](docs/development.md).

## Relationship to upstream

This fork tracks the upstream project's releases and re-applies the plugin
manager on top. It is not a rewrite and not a competitor: if upstream adopts
the feature, this fork has no reason to exist and will be retired.

Changes are kept to one commit against a clean upstream branch, so the
difference stays reviewable and easy to rebase. To see exactly what is added:

```bash
git remote add upstream https://github.com/paxx12-snapmaker-u1/SnapmakerU1-Extended-Firmware
git fetch upstream
git diff upstream/develop...HEAD
```

Bugs in the plugin manager belong here. Everything else belongs
[upstream](https://github.com/paxx12-snapmaker-u1/SnapmakerU1-Extended-Firmware/issues).

## Credits

All of the firmware is [paxx12](https://github.com/paxx12)'s work and that of
its [contributors](HEROES.md). This fork adds one feature and takes credit for
nothing else. If you find the firmware useful,
[support the upstream project](https://buymeacoffee.com/paxx12).

## License

GPL-3.0, as upstream. See [LICENSE](LICENSE). Modified from the upstream
project in August 2026; the modification is the community plugin manager
described above, and its full source is in this repository.
