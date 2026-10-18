#!/bin/bash
set -euo pipefail

# prepare-vendor.sh
# One-time developer script that prepares bundled pdfimages, cjxl and exiftool
# from the local Homebrew installation and the official ExifTool repository.
#
# Usage: ./Scripts/prepare-vendor.sh
# Output: vendor/pdfimages/, vendor/cjxl/ and vendor/exiftool/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$PROJECT_DIR/vendor"

EXIFTOOL_VERSION="13.50"
EXIFTOOL_URL="https://github.com/exiftool/exiftool/archive/refs/tags/${EXIFTOOL_VERSION}.tar.gz"

# Homebrew prefix (arm64 vs x86_64)
if [[ -d /opt/homebrew ]]; then
    BREW_PREFIX="/opt/homebrew"
elif [[ -d /usr/local/Homebrew ]]; then
    BREW_PREFIX="/usr/local"
else
    echo "Error: Homebrew not found" >&2
    exit 1
fi

PDFIMAGES="$BREW_PREFIX/bin/pdfimages"
if [[ ! -x "$PDFIMAGES" ]]; then
    echo "Error: pdfimages not found at $PDFIMAGES" >&2
    echo "Install it first: brew install poppler" >&2
    exit 1
fi

if [[ ! -x "$BREW_PREFIX/bin/cjxl" ]]; then
    echo "Error: cjxl not found. Install it first: brew install jpeg-xl" >&2
    exit 1
fi

echo "=== Preparing vendor directory ==="
rm -rf "$VENDOR_DIR"
mkdir -p "$VENDOR_DIR/pdfimages/pdfimages-lib"
mkdir -p "$VENDOR_DIR/exiftool"

# Collect and relocate the installed Poppler dependency graph, including licenses.
python3 "$SCRIPT_DIR/prepare-jpeg-xl.py" --name pdfimages \
    --source "$PDFIMAGES" --output "$VENDOR_DIR/pdfimages"
PDFIMAGES_BIN="$VENDOR_DIR/pdfimages/pdfimages"
LIB_DIR="$VENDOR_DIR/pdfimages/pdfimages-lib"

# ---------------------------------------------------------------------------
# Part 2: JPEG XL
# ---------------------------------------------------------------------------
python3 "$SCRIPT_DIR/prepare-jpeg-xl.py" --source "$BREW_PREFIX/bin/cjxl"

# ---------------------------------------------------------------------------
# Part 3: exiftool
# ---------------------------------------------------------------------------
echo "--- Downloading exiftool $EXIFTOOL_VERSION ---"
TMPDIR_ET=$(mktemp -d)
trap "rm -rf '$TMPDIR_ET'" EXIT

curl -fSL "$EXIFTOOL_URL" -o "$TMPDIR_ET/exiftool.tar.gz"
tar xzf "$TMPDIR_ET/exiftool.tar.gz" -C "$TMPDIR_ET"

ET_DIR="$TMPDIR_ET/exiftool-${EXIFTOOL_VERSION}"
if [[ ! -d "$ET_DIR" ]]; then
    echo "Error: Expected directory $ET_DIR not found after extraction" >&2
    exit 1
fi

# Copy script and modules
cp "$ET_DIR/exiftool" "$VENDOR_DIR/exiftool/exiftool"
cp -R "$ET_DIR/lib" "$VENDOR_DIR/exiftool/lib"

# Remove non-essential files that cause codesign failures (.pod, README, etc.)
find "$VENDOR_DIR/exiftool" -name "*.pod" -delete
find "$VENDOR_DIR/exiftool" -name "README" -delete

# Patch shebang to use system perl
sed -i '' '1s|^#!.*|#!/usr/bin/perl|' "$VENDOR_DIR/exiftool/exiftool"
chmod +x "$VENDOR_DIR/exiftool/exiftool"

# ---------------------------------------------------------------------------
# Part 4: Ad-hoc codesign everything
# ---------------------------------------------------------------------------
echo "--- Ad-hoc codesigning ---"

# Sign dylibs first (dependencies before dependents)
for dylib in "$LIB_DIR"/*.dylib; do
    codesign --force --sign - "$dylib"
done

# Sign pdfimages binary
codesign --force --sign - "$PDFIMAGES_BIN"

# Sign exiftool (Perl script — Mach-O signature not needed, but codesign handles it)
codesign --force --sign - "$VENDOR_DIR/exiftool/exiftool" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
echo ""
echo "=== Verification ==="
echo "--- pdfimages dependencies ---"
otool -L "$PDFIMAGES_BIN"

echo ""
echo "--- Checking for remaining Homebrew references ---"
REMAINING=$(otool -L "$PDFIMAGES_BIN" "$LIB_DIR"/*.dylib 2>/dev/null | grep -c "/opt/homebrew" || true)
if [[ "$REMAINING" -gt 0 ]]; then
    echo "WARNING: Found $REMAINING remaining Homebrew references!"
    otool -L "$PDFIMAGES_BIN" "$LIB_DIR"/*.dylib | grep "/opt/homebrew"
else
    echo "OK: No Homebrew references found"
fi

echo ""
echo "--- exiftool shebang ---"
head -1 "$VENDOR_DIR/exiftool/exiftool"

echo ""
echo "=== Done ==="
echo "vendor/pdfimages/: $(du -sh "$VENDOR_DIR/pdfimages" | awk '{print $1}')"
echo "vendor/exiftool/:  $(du -sh "$VENDOR_DIR/exiftool" | awk '{print $1}')"
echo "Total:             $(du -sh "$VENDOR_DIR" | awk '{print $1}')"
