---
title: Plugins
---

# Plugins

A plugin is a firmware feature installed on a printer that is already
flashed — no rebuild, no reflash. Plugins let people publish features that
don't belong in an official release but that other people still want, from
their own repository, on their own schedule.

Plugins are managed from **Firmware Config → Plugins**
(`http://<printer-ip>/firmware-config/`), which requires
[Advanced Mode](firmware_config.md).

## Security

**A plugin runs as root and has full access to your printer.** It can read and
write any file, reach your network, and run anything at boot. This project does
not review, sign, or vet community plugins.

Install plugins only from authors you trust, the same way you would with any
program you run as administrator on a computer. If an author publishes a
SHA256 checksum for their release, paste it into the checksum field — the
printer then refuses to install anything that does not match it byte for byte.
Without a checksum the install still proceeds, and the printer prints the hash
of what it actually downloaded.

## Installing

**From a URL.** Paste the plugin's `.tar.gz` URL into the Plugins card and
press *Install*. For a plugin published as a GitHub release, that is the
release asset URL.

**From a file.** Download the `.tar.gz` yourself, then drop it on the file
field and press *Upload & Install*. Use this when the printer has no internet
access.

Either way, the checksum field is optional and applies to both.

Installing restarts whichever services the plugin declares — usually nginx and
Moonraker, which briefly interrupts the web interface. **Do not install a
plugin during a print.**

## Enabling, disabling, removing

Each installed plugin has a row in the Plugins card:

- **Disable** keeps the plugin installed but removes its files from the
  running system. Use it to check whether a plugin is causing a problem.
- **Enable** puts them back.
- **Remove** deletes the plugin, its files, and the default configuration it
  contributed.

Removing a plugin does not delete settings you edited yourself elsewhere in
`printer_data/config/extended/`.

## Where plugins live

Plugins are stored in `/oem/plugins/`, which persists across reboots and
firmware upgrades. The rest of the filesystem does not: the printer runs from
an overlay that is wiped on every boot unless `/oem/.debug` is set (see
[Data Persistence](data_persistence.md)). That is why plugin files are copied
back into place at every boot, by `/etc/init.d/S48zextended-plugins`.

A plugin that survives a firmware upgrade was built against the *previous*
firmware. If something misbehaves after upgrading, disable your plugins first
and check with the author.

## Command line

The web interface drives `extended-plugin`, which is also usable over
[SSH](ssh_access.md):

```bash
extended-plugin list                          # name, version, state
extended-plugin install <url|file> [sha256]
extended-plugin update <name>                 # reinstall from the original URL
extended-plugin enable <name>
extended-plugin disable <name>
extended-plugin remove <name>
extended-plugin apply                         # re-apply all enabled plugins
```

## Troubleshooting

**A plugin does not appear to do anything.** Check `extended-plugin list`. A
state of `error` means its manifest is unreadable. Otherwise look for
`WARNING:` lines from `extended-plugin` in the boot log — the most common one
is a plugin trying to overwrite a file that belongs to the firmware or to
another plugin, which is refused.

**The printer boots but a plugin breaks something.** Disable it from the web
interface, or over SSH:

```bash
extended-plugin disable <name>
```

**The web interface is unreachable.** Put a file named `plugins-disable.txt`
on a USB stick, insert it, and reboot. Every plugin stays inert for that boot,
which gets the printer back to a stock state without deleting anything. Remove
the file and reboot to re-enable them.

**Nothing else works.** The `extended-recover.txt` and `full-recover.txt` USB
recovery files described in [Firmware Configuration](firmware_config.md) still
apply, and reflashing the firmware clears everything except `/oem/plugins/`.
To wipe plugins too:

```bash
rm -rf /oem/plugins
```

## Plugins versus mods

Both let people ship features this project does not maintain, at different
points in the pipeline:

| | [Mods](mods.md) | Plugins |
| --- | --- | --- |
| Installed | at build time, into the image | at runtime, on a flashed printer |
| Requires | building the firmware from source | nothing but the web interface |
| Lives in | this repository, under `overlays/mods/` | the author's own repository |
| Can patch stock firmware files | yes | no, only add new files |

They share a layout, so one directory can be both: adding a `plugin.conf` to a
mod makes it packageable as a plugin without changing how it builds. See
[Writing a Plugin](plugin_development.md).
