// App Icon setup

// This project uses a single-slot AppIcon asset (ios-marketing 1024×1024) suitable for simulator runs and local builds. To install or update the icon from a source PNG:
//
// - Put your source image at /Users/dtolb/code/tolbnet/BlueSkyTemplates/bluesky-icon.png (or pass a path to the script)
// - Run:
//
// ./scripts/set_app_icon.sh [optional/path/to/source.png]
//
// What the script does:
// - Copies the original source to App/Resources/source/bluesky-icon-1254.png for round-tripping
// - Resizes to 1024×1024 and writes App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// - Creates a minimal Contents.json if missing
// - Flattens alpha if present (App Store rejects transparency)
//
// Notes:
// - For App Store submission you typically need a full set of iPhone/iPad icon sizes. This repo currently ships only the ios-marketing slot (1024²) to keep things simple. If you plan to submit to the store, extend the AppIcon.appiconset with the full set.
// - iOS applies rounded corners at render time. Do not pre-round your source; if your asset has subtle darkened corners already, it will generally still look fine since iOS's mask radius sits inside those edges.
