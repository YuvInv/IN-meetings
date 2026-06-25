#!/usr/bin/env bash
#
# Build a LOCAL, UNSIGNED drag-to-/Applications .dmg for install + onboarding testing.
#
# ⚠️ NOT for distribution. This is NOT notarized and NOT Developer-ID signed — the real notarized
# installer is the deferred "Ship" phase, gated on an Apple Developer Program membership (see
# docs/distribution-setup.md). This target exists only so the install → first-launch → onboarding
# flow can be exercised the way a teammate would, from /Applications, without the paid account.
#
# On the machine that built it, the .dmg has no quarantine flag, so it opens normally. If you copy the
# .dmg to ANOTHER Mac (download / AirDrop), Gatekeeper will quarantine it — first launch then needs
# right-click → Open, or:  xattr -dr com.apple.quarantine "/Applications/INV Meetings.app"
#
# Pass a RELEASE build: a Debug build uses Xcode's debug-dylib split (ENABLE_DEBUG_DYLIB) and isn't meant
# to run outside DerivedData, so it may not launch from /Applications. `make dmg` builds Release for this.
#
# Usage: scripts/make-dmg.sh [path-to-"INV Meetings.app"]   (defaults to the Release build product)

set -euo pipefail

APP_PRODUCT="${1:-./DerivedData/Build/Products/Release/INV Meetings.app}"
VOL_NAME="INV Meetings"
OUT_DIR="dist"
DMG_PATH="$OUT_DIR/INMeetings.dmg"

if [ ! -d "$APP_PRODUCT" ]; then
    echo "error: app not found at '$APP_PRODUCT' — run 'make build-mac' first." >&2
    exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Stage the app next to an /Applications symlink so the .dmg shows the familiar drag-to-install layout.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP_PRODUCT" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG_PATH" >/dev/null

SIZE="$(du -h "$DMG_PATH" | cut -f1)"
echo "Built: $DMG_PATH ($SIZE) — unsigned, local testing only."
