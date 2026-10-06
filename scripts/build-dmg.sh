#!/bin/sh
# 使用方法：sh scripts/build-dmg.sh [version]
set -eu
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION=${1:-$(cat "$ROOT_DIR/VERSION")}
case "$VERSION" in
    ''|*[!0-9A-Za-z.-]*) echo "Invalid version" >&2; exit 1 ;;
esac
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$(mktemp -d "$ROOT_DIR/.build/dmg-staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT HUP INT TERM
sh "$ROOT_DIR/scripts/build-app.sh"
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/VolumeControl.app/Contents/Info.plist")
if [ "$APP_VERSION" != "$VERSION" ]; then
    echo "App version $APP_VERSION does not match package version $VERSION" >&2
    exit 1
fi
mkdir -p "$DIST_DIR"
ditto "$ROOT_DIR/VolumeControl.app" "$STAGING_DIR/VolumeControl.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$ROOT_DIR/README.md" "$STAGING_DIR/README.txt"
hdiutil create -volname "VolumeControl $VERSION" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DIST_DIR/VolumeControl-$VERSION-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$ROOT_DIR/VolumeControl.app" "$DIST_DIR/VolumeControl-$VERSION-universal.zip"
(cd "$DIST_DIR" && shasum -a 256 "VolumeControl-$VERSION-universal.dmg" "VolumeControl-$VERSION-universal.zip" > SHA256SUMS.txt)
echo "Built release assets in $DIST_DIR"
