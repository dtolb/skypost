#!/usr/bin/env bash
# set_app_icon.sh — resize and install the app icon into the asset catalog
#
# Usage:
#   scripts/set_app_icon.sh [/absolute/or/relative/path/to/source.png]
#
# If no path is provided, defaults to the repo-root path used in this project:
#   /Users/dtolb/code/tolbnet/BlueSkyTemplates/bluesky-icon.png
#
# What this does:
# - Copies your source PNG into App/Resources/source/ for round-tripping later
# - Resizes the source to 1024×1024 and writes AppIcon.png into
#   App/Resources/Assets.xcassets/AppIcon.appiconset/
# - Creates a minimal Contents.json for the AppIcon.appiconset if missing
#
# Requirements: macOS 'sips' tool (built-in)

set -euo pipefail

REPO_ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_SRC="/Users/dtolb/code/tolbnet/BlueSkyTemplates/bluesky-icon.png"
SRC_PATH="${1:-$DEFAULT_SRC}"
ASSET_DIR="$REPO_ROOT_DIR/App/Resources/Assets.xcassets/AppIcon.appiconset"
SRC_DIR="$REPO_ROOT_DIR/App/Resources/source"
DEST_ICON="$ASSET_DIR/AppIcon.png"

if [[ ! -f "$SRC_PATH" ]]; then
  echo "[set_app_icon] ERROR: Source PNG not found at: $SRC_PATH" >&2
  exit 1
fi

mkdir -p "$ASSET_DIR" "$SRC_DIR"

# Preserve the original in-tree for future resizes/variants.
cp -f "$SRC_PATH" "$SRC_DIR/bluesky-icon-1254.png" || true

# Resize to 1024×1024 for the ios-marketing slot.
# Note: sips -z <height> <width>
/usr/bin/sips -z 1024 1024 "$SRC_PATH" --out "$DEST_ICON" >/dev/null

# If the output has an alpha channel, flatten it (App Store rejects transparency).
HAS_ALPHA=$(/usr/bin/sips -g hasAlpha "$DEST_ICON" 2>/dev/null | awk '/hasAlpha:/ {print $2}')
if [[ "$HAS_ALPHA" == "yes" ]]; then
  echo "[set_app_icon] Detected alpha channel; flattening to opaque PNG"
  /usr/bin/sips -s format png --setProperty formatOptions normal "$DEST_ICON" --out "$DEST_ICON" >/dev/null
fi

# Create a minimal Contents.json if it's missing.
if [[ ! -f "$ASSET_DIR/Contents.json" ]]; then
  cat >"$ASSET_DIR/Contents.json" <<'JSON'
{
  "images": [
    {
      "idiom": "ios-marketing",
      "size": "1024x1024",
      "scale": "1x",
      "filename": "AppIcon.png"
    }
  ],
  "info": {
    "version": 1,
    "author": "xcode"
  }
}
JSON
fi

echo "[set_app_icon] Installed icon to $DEST_ICON"
