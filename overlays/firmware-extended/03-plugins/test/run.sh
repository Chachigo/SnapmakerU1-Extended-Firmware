#!/usr/bin/env bash

#
# Tests extended-plugin against a fake rootfs, so it runs on the build host
# without a printer. PLUGIN_ROOT and PLUGIN_PREFIX redirect both the plugin
# store and the tree plugins are applied into.
#

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
MANAGER="$HERE/../root/usr/local/bin/extended-plugin"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export PLUGIN_ROOT="$WORK/store"
export PLUGIN_PREFIX="$WORK/rootfs"
export EXTENDED_CONFIG_DIR="$WORK/rootfs/home/lava/printer_data/config/extended"
export VERSION_FILE="$WORK/BUILD_VERSION"
export CURL=/bin/false

mkdir -p "$PLUGIN_ROOT" "$PLUGIN_PREFIX" "$EXTENDED_CONFIG_DIR"
echo "1.0.0-test-gabcdef0" > "$VERSION_FILE"

FAILURES=0
plugin() { "$MANAGER" "$@"; }

ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

assert_file()    { [[ -f "$1" ]] && ok "exists: ${1#$WORK/}" || fail "missing: ${1#$WORK/}"; }
assert_no_file() { [[ -e "$1" ]] && fail "should be gone: ${1#$WORK/}" || ok "gone: ${1#$WORK/}"; }
assert_ok()      { if "$@" > "$WORK/out" 2>&1; then ok "$*"; else fail "$* (see below)"; cat "$WORK/out"; fi; }
assert_fails()   { if "$@" > "$WORK/out" 2>&1; then fail "$* should have failed"; cat "$WORK/out"; else ok "rejected: $*"; fi; }

# --- fixture -----------------------------------------------------------------

FIXTURE="$WORK/src/demo"
mkdir -p "$FIXTURE/root/etc/nginx/fluidd.d" \
         "$FIXTURE/root/usr/local/share/firmware-config/extended/moonraker"
cat > "$FIXTURE/plugin.conf" <<'CONF'
PLUGIN_NAME=demo
PLUGIN_VERSION=1.0.0
PLUGIN_LABEL="Demo Plugin"
PLUGIN_AUTHOR="Test"
PLUGIN_SERVICES=""
CONF
echo "location /demo/ { }" > "$FIXTURE/root/etc/nginx/fluidd.d/demo.conf"
echo "[demo]" > "$FIXTURE/root/usr/local/share/firmware-config/extended/moonraker/90_demo.cfg"

TARBALL="$WORK/demo-1.0.0.tar.gz"
tar czf "$TARBALL" -C "$WORK/src" demo
SHA=$(sha256sum "$TARBALL" | cut -d' ' -f1)

NGINX="$PLUGIN_PREFIX/etc/nginx/fluidd.d/demo.conf"
CFG="$PLUGIN_PREFIX/usr/local/share/firmware-config/extended/moonraker/90_demo.cfg"

# --- 1. install with a matching checksum -------------------------------------

echo "install (good checksum)"
assert_ok plugin install "$TARBALL" "$SHA"
assert_file "$NGINX"
assert_file "$CFG"
assert_file "$PLUGIN_ROOT/demo/.files"
grep -qxF "$NGINX" "$PLUGIN_ROOT/demo/.files" \
    && ok ".files records the applied path" || fail ".files is missing $NGINX"
plugin list | grep -q "demo .*enabled" && ok "list reports enabled" || fail "list does not report enabled"
plugin list --json | grep -q '"name":"demo"' && ok "list --json emits the plugin" || fail "list --json is wrong"

# --- 2. a bad checksum installs nothing --------------------------------------

echo "install (bad checksum)"
assert_fails plugin install "$TARBALL" 0000000000000000000000000000000000000000000000000000000000000000
assert_file "$NGINX"          # the already-installed copy must survive
assert_no_file "$PLUGIN_ROOT/.tmp"

# --- 3. disable / enable ------------------------------------------------------

echo "disable / enable"
assert_ok plugin disable demo
assert_no_file "$NGINX"
assert_file "$PLUGIN_ROOT/demo/plugin.conf"   # still installed, just inert
assert_ok plugin apply                        # a boot while disabled stays inert
assert_no_file "$NGINX"
assert_ok plugin enable demo
assert_file "$NGINX"

# --- 4. apply is idempotent and survives a wiped rootfs ----------------------

echo "apply after an overlayfs wipe"
rm -rf "$PLUGIN_PREFIX/etc" "$PLUGIN_PREFIX/usr"
assert_ok plugin apply
assert_file "$NGINX"
assert_file "$CFG"

# --- 5. never clobber a firmware file ----------------------------------------

echo "overwrite guard"
plugin disable demo > /dev/null 2>&1
mkdir -p "$(dirname "$NGINX")"
echo "FIRMWARE FILE" > "$NGINX"
plugin enable demo > "$WORK/out" 2>&1
if grep -q "FIRMWARE FILE" "$NGINX"; then
    ok "existing firmware file left intact"
else
    fail "firmware file was overwritten"
fi
grep -q "refusing to overwrite" "$WORK/out" && ok "refusal is reported" || fail "no refusal reported"
rm -f "$NGINX"
assert_ok plugin apply
assert_file "$NGINX"

# --- 6. remove cleans the rootfs and the copied config defaults --------------

echo "remove"
# stand in for what S49extended-config copies out of the defaults tree
mkdir -p "$EXTENDED_CONFIG_DIR/moonraker"
cp "$CFG" "$EXTENDED_CONFIG_DIR/moonraker/90_demo.cfg"
touch "$EXTENDED_CONFIG_DIR/moonraker/90_demo.cfg.default"

assert_ok plugin remove demo
assert_no_file "$NGINX"
assert_no_file "$CFG"
assert_no_file "$PLUGIN_ROOT/demo"
assert_no_file "$EXTENDED_CONFIG_DIR/moonraker/90_demo.cfg"
assert_no_file "$EXTENDED_CONFIG_DIR/moonraker/90_demo.cfg.default"

# --- 7. reject a broken manifest ---------------------------------------------

echo "broken manifest"
BROKEN="$WORK/src2/broken"
mkdir -p "$BROKEN/root/etc"
echo "PLUGIN_NAME=broken" > "$BROKEN/plugin.conf"   # no PLUGIN_VERSION
echo x > "$BROKEN/root/etc/broken.conf"
tar czf "$WORK/broken.tar.gz" -C "$WORK/src2" broken
assert_fails plugin install "$WORK/broken.tar.gz"
assert_no_file "$PLUGIN_PREFIX/etc/broken.conf"
assert_no_file "$PLUGIN_ROOT/broken"

# --- 8. min-firmware gate -----------------------------------------------------

echo "min firmware"
sed -i 's/^PLUGIN_VERSION=.*/PLUGIN_VERSION=1.0.0/' "$FIXTURE/plugin.conf"
echo 'PLUGIN_MIN_FIRMWARE=9.9.9' >> "$FIXTURE/plugin.conf"
tar czf "$WORK/demo-min.tar.gz" -C "$WORK/src" demo
assert_fails plugin install "$WORK/demo-min.tar.gz"
assert_no_file "$NGINX"

echo "dev builds have no comparable version, so the gate stays open"
echo "feature-branch-gabcdef0" > "$VERSION_FILE"
assert_ok plugin install "$WORK/demo-min.tar.gz"
assert_file "$NGINX"

# --- 9. config defaults reach printer_data at install ------------------------
#
# Without this a runtime install ships a moonraker .cfg that nothing includes
# until the next reboot, and the firmware-config toggle's `uncomment` finds no
# file to act on.

echo "config defaults"
USER_CFG="$EXTENDED_CONFIG_DIR/moonraker/90_demo.cfg"
assert_file "$USER_CFG"
[[ "$(cat "$USER_CFG")" == "[demo]" ]] && ok "default content copied" || fail "wrong content"

echo "a user edit survives a plugin update"
echo "[demo]
edited: yes" > "$USER_CFG"
assert_ok plugin install "$TARBALL" "$SHA"
grep -q "edited: yes" "$USER_CFG" \
    && ok "user edit preserved" || fail "user edit was clobbered"

echo "removal takes the copy with it"
assert_ok plugin remove demo
assert_no_file "$USER_CFG"
assert_ok plugin install "$TARBALL" "$SHA"
assert_file "$USER_CFG"

# --- 10. nginx is reloaded, not restarted ------------------------------------
#
# extended-plugin runs from a firmware-config request served through nginx, so a
# stop/start would kill the connection streaming the install's own output.

echo "service actions"
export INITD_DIR="$WORK/initd"
mkdir -p "$INITD_DIR"
for svc in S50nginx S61moonraker; do
    printf '#!/bin/sh\necho "%s $1" >> "%s"\n' "$svc" "$WORK/svc.log" > "$INITD_DIR/$svc"
    chmod 755 "$INITD_DIR/$svc"
done
sed -i 's/^PLUGIN_SERVICES=.*/PLUGIN_SERVICES="S50nginx S61moonraker"/' "$FIXTURE/plugin.conf"
sed -i '/^PLUGIN_MIN_FIRMWARE=/d' "$FIXTURE/plugin.conf"
tar czf "$WORK/demo-svc.tar.gz" -C "$WORK/src" demo

: > "$WORK/svc.log"
assert_ok plugin install "$WORK/demo-svc.tar.gz"
grep -qx "S50nginx reload" "$WORK/svc.log" \
    && ok "nginx is reloaded" || fail "nginx got: $(grep S50nginx "$WORK/svc.log")"
grep -qx "S50nginx restart" "$WORK/svc.log" \
    && fail "nginx was restarted - this kills the streaming connection" || ok "nginx never restarted"
grep -qx "S61moonraker restart" "$WORK/svc.log" \
    && ok "moonraker is restarted" || fail "moonraker got: $(grep S61moonraker "$WORK/svc.log")"

echo
if [[ $FAILURES -eq 0 ]]; then
    echo "All checks passed."
else
    echo "$FAILURES check(s) failed."
fi
exit $FAILURES
