#!/bin/bash
# Build a runnable Tokcat.app with just the Command Line Tools — no Xcode,
# no XcodeGen. `swift build` compiles the app executable (the `tokcat`
# target, whose AppMain.swift symlinks ../../Tokcat/TokcatApp.swift), and
# this script assembles the bundle by hand: Info.plist, icon, the SwiftPM
# resource bundles, and the Sparkle framework SwiftPM leaves in the build
# dir. Ad-hoc signed, like the release builds.
#
# Usage: scripts/build-local-app.sh [release|debug]
# Output: native/build/Tokcat.app (override with TOKCAT_APP_OUT=...)
set -euo pipefail

CONFIG="${1:-release}"
case "$CONFIG" in
  release) SWIFT_CONFIG="release" ;;
  debug)   SWIFT_CONFIG="debug" ;;
  *) echo "usage: $0 [release|debug]" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"  # repo root
PKG="$ROOT/native/LocalPackage"
APP_SRC="$ROOT/native/Tokcat"
OUT="${TOKCAT_APP_OUT:-$ROOT/native/build/Tokcat.app}"

cd "$PKG"
swift build -c "$SWIFT_CONFIG"

BUILD=".build/$SWIFT_CONFIG"
BIN="$BUILD/tokcat"
SPARKLE="$BUILD/Sparkle.framework"
MODEL_BUNDLE="$BUILD/LocalPackage_Model.bundle"
UI_BUNDLE="$BUILD/LocalPackage_UserInterface.bundle"
for artifact in "$BIN" "$SPARKLE" "$MODEL_BUNDLE" "$UI_BUNDLE"; do
  [ -e "$artifact" ] || { echo "missing build artifact: $artifact" >&2; exit 1; }
done

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$OUT/Contents/Frameworks"
cp "$BIN" "$OUT/Contents/MacOS/tokcat"
cp -R "$SPARKLE" "$OUT/Contents/Frameworks/"
cp -R "$MODEL_BUNDLE" "$UI_BUNDLE" "$OUT/Contents/Resources/"
cp "$APP_SRC/icon.icns" "$OUT/Contents/Resources/icon.icns"

# Info.plist: substitute the XcodeGen build settings its placeholders stand
# for (the values live in native/project.yml).
MARKETING_VERSION=$(sed -n 's/^ *MARKETING_VERSION: //p' "$ROOT/native/project.yml")
CURRENT_PROJECT_VERSION=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: //p' "$ROOT/native/project.yml")
sed \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.handlecusion.tokcat/" \
    -e "s/\$(DEVELOPMENT_LANGUAGE)/en/" \
    -e "s/\$(MARKETING_VERSION)/$MARKETING_VERSION/" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$CURRENT_PROJECT_VERSION/" \
    "$APP_SRC/Info.plist" > "$OUT/Contents/Info.plist"

# The executable references Sparkle by @rpath; point it at the embedded
# framework (any rpath SwiftPM left over from the build dir is meaningless
# once the binary moves into the bundle).
BIN_OUT="$OUT/Contents/MacOS/tokcat"
while read -r rp; do
  install_name_tool -delete_rpath "$rp" "$BIN_OUT" 2>/dev/null || true
done < <(otool -l "$BIN_OUT" | awk '/LC_RPATH/{f=1;next} f&&/ path /{print $2; f=0}')
install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN_OUT"

# Ad-hoc sign, nested code first. Bundle id stays com.handlecusion.tokcat on
# purpose: that is the UserDefaults domain the Tauri-era settings and the
# TauriMigration import live in.
codesign --force --deep --sign - "$OUT" >/dev/null

echo "Built $OUT"
echo "Try it: open $OUT"
