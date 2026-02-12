#!/bin/bash
set -euo pipefail

# bundle-tools.sh
# Xcode "Run Script" build phase that copies vendor tools into the .app bundle.
# Called automatically during build. Skips gracefully if vendor/ doesn't exist.
#
# Layout:
#   Contents/Helpers/        — Mach-O binaries (pdfimages + dylibs)
#   Contents/Resources/exiftool/ — Perl script + modules (non-code, avoids codesign issues)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$PROJECT_DIR/vendor"

CONTENTS_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [[ ! -d "$VENDOR_DIR" ]]; then
    echo "warning: vendor/ directory not found at $VENDOR_DIR — skipping tool bundling"
    echo "warning: Run Scripts/prepare-vendor.sh first to prepare bundled tools"
    exit 0
fi

echo "Bundling external tools"

# Re-sign with the build's code signing identity + hardened runtime.
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    echo "  No code signing identity — using ad-hoc signing"
    IDENTITY="-"
fi

sign_binary() {
    codesign --force --sign "$IDENTITY" --options runtime "$1"
}

# --- pdfimages (Mach-O) → Contents/Helpers/ ---
if [[ -d "$VENDOR_DIR/pdfimages" ]]; then
    echo "  Copying pdfimages into Helpers..."
    rm -rf "$HELPERS_DIR"
    mkdir -p "$HELPERS_DIR"
    cp -R "$VENDOR_DIR/pdfimages/pdfimages" "$HELPERS_DIR/pdfimages"
    cp -R "$VENDOR_DIR/pdfimages/pdfimages-lib" "$HELPERS_DIR/pdfimages-lib"

    echo "  Signing with identity: $IDENTITY"
    for dylib in "$HELPERS_DIR/pdfimages-lib"/*.dylib; do
        [[ -f "$dylib" ]] || continue
        sign_binary "$dylib"
    done
    sign_binary "$HELPERS_DIR/pdfimages"
fi

# --- exiftool (Perl) → Contents/Resources/exiftool/ ---
# Placed in Resources so codesign treats them as data, not code objects.
if [[ -d "$VENDOR_DIR/exiftool" ]]; then
    echo "  Copying exiftool into Resources..."
    rm -rf "$RESOURCES_DIR/exiftool"
    cp -R "$VENDOR_DIR/exiftool" "$RESOURCES_DIR/exiftool"
fi

echo "  Done bundling external tools"
