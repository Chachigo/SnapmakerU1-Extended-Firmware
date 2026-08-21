#!/usr/bin/env bash

#
# Pack an overlay-shaped directory into an installable plugin tarball.
#
# A plugin is the same `root/` tree an overlay ships, so any overlay directory
# becomes a plugin by adding a `plugin.conf` next to its `root/`. Build-time
# parts of an overlay (`patches/`, `pre-scripts/`, `scripts/`) have no runtime
# equivalent and are left out — use the plugin's `install.sh` instead.
#
# Usage: scripts/dev/make-plugin.sh <plugin-dir> [output.tar.gz]
#

set -euo pipefail

SRC=${1:-}
[[ -n "$SRC" ]] || { echo "Usage: $0 <plugin-dir> [output.tar.gz]" >&2; exit 1; }
SRC=${SRC%/}

[[ -d "$SRC" ]] || { echo "ERROR: no such directory: $SRC" >&2; exit 1; }
[[ -f "$SRC/plugin.conf" ]] || {
    echo "ERROR: $SRC/plugin.conf not found." >&2
    echo "       See docs/plugin_development.md for the manifest reference." >&2
    exit 1
}
[[ -d "$SRC/root" ]] || { echo "ERROR: $SRC/root/ not found — a plugin ships its files there." >&2; exit 1; }

PLUGIN_NAME="" PLUGIN_VERSION=""
# shellcheck disable=SC1091
source "$SRC/plugin.conf"

[[ -n "$PLUGIN_NAME" ]] || { echo "ERROR: plugin.conf does not set PLUGIN_NAME" >&2; exit 1; }
[[ -n "$PLUGIN_VERSION" ]] || { echo "ERROR: plugin.conf does not set PLUGIN_VERSION" >&2; exit 1; }
[[ "$PLUGIN_NAME" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || {
    echo "ERROR: invalid PLUGIN_NAME '$PLUGIN_NAME' (expected [a-z0-9][a-z0-9._-]*)" >&2
    exit 1
}

for build_only in patches pre-scripts scripts; do
    [[ -d "$SRC/$build_only" ]] && \
        echo "NOTE: $SRC/$build_only/ is build-time only and will not be packed."
done

OUT=${2:-$PLUGIN_NAME-$PLUGIN_VERSION.tar.gz}
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

DIR="$STAGING/$PLUGIN_NAME-$PLUGIN_VERSION"
mkdir -p "$DIR"
cp -a "$SRC/plugin.conf" "$SRC/root" "$DIR/"
[[ -f "$SRC/install.sh" ]] && cp -a "$SRC/install.sh" "$DIR/"
[[ -f "$SRC/README.md" ]] && cp -a "$SRC/README.md" "$DIR/"

tar czf "$OUT" -C "$STAGING" "$PLUGIN_NAME-$PLUGIN_VERSION"

echo
echo "$OUT"
echo "SHA256: $(sha256sum "$OUT" | cut -d' ' -f1)"
echo
echo "Publish both, so users can verify what they install."
