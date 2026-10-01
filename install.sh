#!/bin/sh
# Builds asmmesh (running the self-tests first), copies it to /Applications,
# pins it to the Dock and launches it. Safe to run again after changes.
set -e
cd "$(dirname "$0")"

make selftest
# Build and sign the bundle outside iCloud Drive: iCloud keeps adding Finder info
# to files on the Desktop, and codesign refuses a bundle that has any.
BUILD="${TMPDIR:-/tmp}/asmmesh-build"
rm -rf asmmesh.app "$BUILD"   # always re-sign a fresh bundle
mkdir -p "$BUILD"
make APP="$BUILD/asmmesh.app"

DEST="/Applications/asmmesh.app"
echo "Installing to $DEST..."
pkill -x asmmesh 2>/dev/null || true
sleep 1
rm -rf "$DEST"
ditto "$BUILD/asmmesh.app" "$DEST"

# Pin to the Dock once (skip if it is already there).
if ! defaults read com.apple.dock persistent-apps 2>/dev/null | grep -q "asmmesh.app"; then
    echo "Adding to the Dock..."
    defaults write com.apple.dock persistent-apps -array-add \
      "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>file://$DEST/</string><key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>"
    killall Dock
fi

open "$DEST"
echo "asmmesh is running - look for the mesh icon in the menu bar and in the Dock."
