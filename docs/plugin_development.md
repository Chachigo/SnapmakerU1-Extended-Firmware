---
title: Writing a Plugin
---

# Writing a Plugin

A plugin is a `.tar.gz` containing a `root/` directory and a `plugin.conf`.
`root/` mirrors the printer's filesystem: whatever is in it gets copied there.
There is no API to call and no registry to sign up for — every extension point
in this firmware is picked up by a glob, so a plugin only has to put its files
in the right places.

This is the same layout an overlay uses, so **an existing [mod](mods.md)
becomes a plugin by adding a `plugin.conf`**, with no change to how it builds.

Read [Plugins](plugins.md) first for what plugins are and how users install
them.

## Layout

```text
my-plugin/
├── plugin.conf         # required, the manifest
├── install.sh          # optional, runs once at install time
├── README.md           # optional, packed but not used by the printer
└── root/               # required, copied into the printer's filesystem
    └── ...
```

## The six places a plugin can hook into

Everything below is a file drop. Nothing registers itself; each subsystem
globs a directory.

### 1. A Moonraker component — backend logic

```text
root/home/lava/moonraker/moonraker/components/my_plugin.py
```

Moonraker loads a component when a config section of the same name exists.
Write it as any Moonraker component: a `load_component(config)` function, plus
`config.get_server().register_endpoint(...)` for any HTTP API you want to
expose under `/server/`.

### 2. A Moonraker config section — turns the component on

```text
root/usr/local/share/firmware-config/extended/moonraker/90_my_plugin.cfg
```

`moonraker.conf` includes `extended/moonraker/*.cfg`. Files under
`usr/local/share/firmware-config/extended/` are *defaults*:
`S49extended-config` copies them into `printer_data/config/extended/` on boot
without ever overwriting a copy the user has edited, and keeps a `.default`
alongside so they can see what changed.

Pick a numeric prefix above the ones the firmware ships (`01`–`06` are taken)
to keep include order predictable.

```ini
# Enabled from firmware-config: Settings > Monitoring & Debugging > My Plugin.
[my_plugin]
```

Ship it commented out if the feature should start off, and have your
firmware-config toggle uncomment it — that is what `extended-config.py comment`
and `uncomment` are for.

### 3. A web page

```text
root/usr/local/share/my-plugin/html/index.html
```

Plain static files. There is no build step anywhere in this firmware — no npm,
no bundler — so write the page by hand and keep it self-contained.

### 4. An nginx route — makes the page reachable

```text
root/etc/nginx/fluidd.d/my-plugin.conf
```

The stock vhost includes `/etc/nginx/fluidd.d/*.conf`:

```nginx
location = /my-plugin {
    return 302 /my-plugin/;
}

location /my-plugin/ {
    alias /usr/local/share/my-plugin/html/;
    index index.html;
}
```

### 5. A firmware-config entry — settings and links

```text
root/usr/local/share/firmware-config/functions/90_settings_my_plugin.yaml
```

Every YAML in `functions/` is deep-merged at startup, so a plugin supplies only
its own `items` and they land in a group the firmware already declares
(`web`, `camera`, `remote_access`, `snapmaker_components`, `print_preferences`,
`tweaks`, `troubleshooting`, `monitoring_debugging`):

```yaml
links:
  my_plugin:
    url: /my-plugin/
    icon: "🔧"
    label: My Plugin
    condition:
      setting: my_plugin
      value: "true"

settings:
  monitoring_debugging:
    items:
      my_plugin:
        label: My Plugin
        description: One sentence on what it does.
        get_cmd:
          - /usr/local/bin/extended-config.py
          - get
          - /oem/printer_data/config/extended/extended2.cfg
          - monitoring
          - my_plugin
          - "false"
        options:
          "true":
            label: Enabled
            cmd:
              - bash
              - -xc
              - |
                /usr/local/bin/extended-config.py add /oem/printer_data/config/extended/extended2.cfg monitoring my_plugin true &&
                /usr/local/bin/extended-config.py uncomment /oem/printer_data/config/extended/moonraker/90_my_plugin.cfg my_plugin &&
                /etc/init.d/S61moonraker restart
          "false":
            label: Disabled
            cmd:
              - bash
              - -xc
              - |
                /usr/local/bin/extended-config.py add /oem/printer_data/config/extended/extended2.cfg monitoring my_plugin false &&
                /usr/local/bin/extended-config.py comment /oem/printer_data/config/extended/moonraker/90_my_plugin.cfg my_plugin &&
                /etc/init.d/S61moonraker restart
        default: "false"
```

See [Firmware Configuration](firmware_config.md) for the full schema —
`actions`, `quick_actions`, `status` groups, and text `inputs` on options.

The `links` block is what puts your page in **Quick Links**. It appears as soon
as the plugin is installed: `extended-plugin` makes firmware-config re-read this
directory, so nothing has to be restarted or rebooted. Note the `condition` —
the link is only shown while the matching setting reports that value, so a
plugin the user has disabled does not leave a dead link behind.

Use a numeric prefix in the `90`–`99` range. Prefixes are a shared namespace
with no coordination, and the firmware uses the low numbers.

### 6. Service hooks — run code around Klipper and Moonraker

```text
root/etc/hooks/moonraker.d/90-my-plugin.sh
root/etc/hooks/klipper.d/90-my-plugin.sh
root/etc/hooks/lmd.d/90-my-plugin.sh
```

Sourced in lexical order by the corresponding init script, with the action
(`start`, `stop`, `restart`) in `$1`. This is the supported way to run
something alongside a stock service. See
[Service Hooks](design/service_hooks.md).

For print lifecycle events (`PRINT_START`, `PRINT_END`, `CANCEL_PRINT`) use
[Klipper Print Hooks](klipper_hooks.md) instead.

## What a plugin cannot do

- **Patch a stock firmware file.** Plugins only add files. Applying a plugin
  refuses to overwrite anything it does not own, which is what keeps a bad
  plugin from bricking a printer and what keeps two plugins from silently
  fighting. If your feature genuinely needs to modify a stock file, it has to
  be an overlay — a [mod](mods.md), or a PR into `overlays/firmware-extended/`.
- **Run at build time.** `patches/`, `pre-scripts/` and `scripts/` from an
  overlay have no plugin equivalent. Use `install.sh` for anything that has to
  happen once on the printer.
- **Ship host binaries.** Anything executable must be ARM64, or a script.
- **Count on `/etc` persisting.** The rootfs overlay is wiped on every boot.
  Write runtime state under `printer_data/` or `/oem/`, never into your own
  `root/` tree, which is re-copied over it on each boot.

## `plugin.conf`

Sourced as shell, so quote anything containing spaces.

| Variable | Required | Meaning |
| --- | --- | --- |
| `PLUGIN_NAME` | yes | Identifier, `[a-z0-9][a-z0-9._-]*`. Also the directory under `/oem/plugins/`. |
| `PLUGIN_VERSION` | yes | Your version string. Shown in the UI; not parsed. |
| `PLUGIN_LABEL` | no | Human-readable name (default: `$PLUGIN_NAME`). |
| `PLUGIN_AUTHOR` | no | Shown in the UI. |
| `PLUGIN_URL` | no | Homepage, linked from the UI. |
| `PLUGIN_PAGE` | no | Path of the page your plugin serves, e.g. `/my-plugin/`. Shown as an open-in-new-tab icon next to the plugin. Must start with `/`. |
| `PLUGIN_DESCRIPTION` | no | One line, shown in the UI. |
| `PLUGIN_MIN_FIRMWARE` | no | Minimum firmware version, e.g. `1.5.2`. Install is refused below it. Only enforced on release builds, where `/etc/BUILD_VERSION` starts with a comparable version; development builds skip the check. |
| `PLUGIN_SERVICES` | no | Init scripts restarted after install, remove, enable and disable, e.g. `"S50nginx S61moonraker"`. nginx is *reloaded* rather than restarted — see below. |

```bash
PLUGIN_NAME=my-plugin
PLUGIN_VERSION=1.0.0
PLUGIN_LABEL="My Plugin"
PLUGIN_AUTHOR="Alice"
PLUGIN_URL="https://github.com/alice/my-plugin"
PLUGIN_PAGE="/my-plugin/"
PLUGIN_DESCRIPTION="One sentence on what it does."
PLUGIN_SERVICES="S50nginx S61moonraker"
```

List in `PLUGIN_SERVICES` only what your plugin actually needs restarted.
Restarting Moonraker drops the web interface for a few seconds.

Name nginx as `S50nginx` as usual — `extended-plugin` reloads it instead of
restarting it. Installs normally run from a Firmware Config request served
*through* nginx, and a stop/start would kill the connection carrying the
install's own output: the plugin lands correctly but the browser reports
`upload failed`. A reload picks up your `fluidd.d/*.conf` and leaves open
connections alone.

## `install.sh`

Optional, must be executable. It runs once at install time, as root, with the
plugin directory as the working directory, after the files are unpacked but
before they are applied. A non-zero exit aborts the install and the plugin is
not left behind.

Use it for the one thing a file drop cannot express — a Python dependency, a
generated file, a migration from an older version:

```bash
#!/bin/sh
set -e
python3 -m pip install --no-index --find-links=./wheels my-dependency
```

There is no uninstall hook. Anything `install.sh` writes outside the plugin's
own tree stays behind after a removal, so prefer not writing outside it.

Remember the printer is offline for many users and has no compiler. Vendor
what you need into the tarball rather than downloading it at install time.

## Packaging

```bash
./scripts/dev/make-plugin.sh <plugin-dir> [output.tar.gz]
```

It validates the manifest, packs `plugin.conf`, `root/`, `install.sh` and
`README.md` into `<name>-<version>.tar.gz`, skips build-time-only directories,
and prints the SHA256.

You do not have to use it — any gzipped tarball works, whether it contains the
plugin directory or its contents directly.

## Publishing

Attach the tarball to a GitHub release and put **the release asset URL and the
SHA256 in the release notes**. Users paste both into the Plugins card; the
checksum is what lets them verify they got what you published.

Do not point users at `https://github.com/<user>/<repo>/archive/refs/tags/*.tar.gz`
unless your repository root *is* the plugin — that archive contains your whole
repository, and its checksum is not stable across GitHub regenerating it.

Say in your README which firmware version you tested against. Plugins survive
firmware upgrades, so yours will keep running on firmware it has never seen.

## Worked example

`overlays/mods/chachigo/02-ntfy/` in this repository is a real feature that is
both an overlay and a plugin. It uses five of the six slots:

```text
02-ntfy/
├── plugin.conf
└── root/
    ├── etc/nginx/fluidd.d/ntfy.conf                            # 4, route
    ├── home/lava/moonraker/moonraker/components/ntfy.py        # 1, backend
    └── usr/local/share/
        ├── firmware-config/extended/moonraker/06_ntfy.cfg      # 2, config
        ├── firmware-config/functions/12_settings_ntfy.yaml     # 5, toggle
        └── ntfy/html/index.html                                # 3, page
```

Pack and install it:

```bash
./scripts/dev/make-plugin.sh overlays/mods/chachigo/02-ntfy
scp ntfy-1.0.0.tar.gz root@<printer-ip>:/tmp/
ssh root@<printer-ip> 'extended-plugin install /tmp/ntfy-1.0.0.tar.gz'
```

The page is then at `http://<printer-ip>/ntfy/` and the toggle appears in
Firmware Config under *Monitoring & Debugging*, with no rebuild and no reflash.

## Testing without a printer

`extended-plugin` reads `PLUGIN_ROOT` and `PLUGIN_PREFIX` from the
environment, so an install can be exercised against a throwaway directory on
your own machine:

```bash
export PLUGIN_ROOT=/tmp/plugin-store PLUGIN_PREFIX=/tmp/plugin-rootfs
mkdir -p "$PLUGIN_ROOT" "$PLUGIN_PREFIX"
overlays/firmware-extended/03-plugins/root/usr/local/bin/extended-plugin \
    install my-plugin-1.0.0.tar.gz
find /tmp/plugin-rootfs -type f
```

That confirms the manifest parses and the files land where you expect. It does
not run your Moonraker component, so still test on a printer before publishing.

`overlays/firmware-extended/03-plugins/test/run.sh` runs the same way and is
the reference for how installs, the overwrite guard, and removal are expected
to behave.
