#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PROJECT_ROOT/desktop_app/build}"
INSTALL_DIR="${REFOCUS_INSTALL_DIR:-$HOME/Applications}"
SCHEME="RefocusApp"
APP_PROJECT="$PROJECT_ROOT/desktop_app/RefocusApp.xcodeproj"

echo "==> Building $SCHEME (Release)…"
xcodebuild \
  -project "$APP_PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build >/tmp/refocus_build.log

SOURCE_APP="$DERIVED_DATA_PATH/Build/Products/Release/RefocusApp.app"
if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Build succeeded but $SOURCE_APP was not found. Check /tmp/refocus_build.log" >&2
  exit 1
fi
if [[ ! -f "$SOURCE_APP/Contents/Helpers/refocus_native_host" ]]; then
  echo "Native host helper was not bundled. Open the Xcode log at /tmp/refocus_build.log for the \"Bundle Native Host\" phase output." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
TARGET_APP="$INSTALL_DIR/Refocus.app"
echo "==> Installing to $TARGET_APP"
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"

echo "Done. Launch $TARGET_APP to test the latest build."
