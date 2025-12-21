#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$PROJECT_ROOT/dist}"
PKG_ROOT="$DIST_DIR/pkgroot"
PKG_SCRIPTS="$PROJECT_ROOT/packaging/pkg_scripts"
COMPONENT_PLIST="$PROJECT_ROOT/packaging/RefocusApp.component.plist"
INSTALL_DIR="${REFOCUS_INSTALL_DIR:-$HOME/Applications}"
PKG_IDENTIFIER="${PKG_IDENTIFIER:-com.refocus.pkg}"

echo "==> Building Refocus.app for packaging..."
mkdir -p "$DIST_DIR"

# Build the app with a separate derived data path for pkg builds
DERIVED_DATA_PATH="$PROJECT_ROOT/desktop_app/build-pkg" "$PROJECT_ROOT/scripts/reinstall_refocus_app.sh"

SOURCE_APP="$INSTALL_DIR/Refocus.app"
if [[ ! -d "$SOURCE_APP" ]]; then
    echo "Error: Refocus.app not found at $SOURCE_APP" >&2
    exit 1
fi

# Verify native host is bundled
if [[ ! -f "$SOURCE_APP/Contents/Helpers/refocus_native_host" ]]; then
    echo "Error: Native host not found in app bundle" >&2
    exit 1
fi

# Verify pkg_scripts directory exists
if [[ ! -d "$PKG_SCRIPTS" ]]; then
    echo "Error: Package scripts directory not found at $PKG_SCRIPTS" >&2
    exit 1
fi

# Verify postinstall is executable
if [[ ! -x "$PKG_SCRIPTS/postinstall" ]]; then
    echo "Making postinstall executable..."
    chmod +x "$PKG_SCRIPTS/postinstall"
fi

APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_APP/Contents/Info.plist")
echo "==> App version: $APP_VERSION"

rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications"
cp -R "$SOURCE_APP" "$PKG_ROOT/Applications/Refocus.app"

PKG_OUTPUT="$DIST_DIR/Refocus-${APP_VERSION}.pkg"

echo "==> Building package..."
pkgbuild \
    --root "$PKG_ROOT" \
    --install-location / \
    --scripts "$PKG_SCRIPTS" \
    --component-plist "$COMPONENT_PLIST" \
    --identifier "$PKG_IDENTIFIER" \
    --version "$APP_VERSION" \
    "$PKG_OUTPUT"

echo "==> Package created at $PKG_OUTPUT"
echo ""
echo "To install: sudo installer -pkg \"$PKG_OUTPUT\" -target /"
