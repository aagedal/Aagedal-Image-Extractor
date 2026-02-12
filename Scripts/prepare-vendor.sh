#!/bin/bash
set -euo pipefail

# prepare-vendor.sh
# One-time developer script that prepares bundled pdfimages and exiftool
# from the local Homebrew installation and exiftool.org.
#
# Usage: ./Scripts/prepare-vendor.sh
# Output: vendor/pdfimages/ and vendor/exiftool/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$PROJECT_DIR/vendor"

EXIFTOOL_VERSION="13.50"
EXIFTOOL_URL="https://exiftool.org/Image-ExifTool-${EXIFTOOL_VERSION}.tar.gz"

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

echo "=== Preparing vendor directory ==="
rm -rf "$VENDOR_DIR"
mkdir -p "$VENDOR_DIR/pdfimages/pdfimages-lib"
mkdir -p "$VENDOR_DIR/exiftool"

# ---------------------------------------------------------------------------
# Part 1: pdfimages + dylibs
# ---------------------------------------------------------------------------
echo "--- Copying pdfimages binary ---"
cp -L "$PDFIMAGES" "$VENDOR_DIR/pdfimages/pdfimages"

# Collect all non-system dylibs transitively
echo "--- Collecting dylibs ---"

# Parallel arrays: dylib names and their Homebrew source paths
DYLIB_NAMES=(
    libpoppler.157.dylib
    libfreetype.6.dylib
    libfontconfig.1.dylib
    libjpeg.8.dylib
    libopenjp2.7.dylib
    liblcms2.2.dylib
    libpng16.16.dylib
    libtiff.6.dylib
    libnss3.dylib
    libnssutil3.dylib
    libsmime3.dylib
    libssl3.dylib
    libplds4.dylib
    libplc4.dylib
    libnspr4.dylib
    libgpgme.45.dylib
    libgpgmepp.7.dylib
    libassuan.9.dylib
    libgpg-error.0.dylib
    libintl.8.dylib
    libzstd.1.dylib
    liblzma.5.dylib
)

DYLIB_PATHS=(
    "$BREW_PREFIX/opt/poppler/lib/libpoppler.157.dylib"
    "$BREW_PREFIX/opt/freetype/lib/libfreetype.6.dylib"
    "$BREW_PREFIX/opt/fontconfig/lib/libfontconfig.1.dylib"
    "$BREW_PREFIX/opt/jpeg-turbo/lib/libjpeg.8.dylib"
    "$BREW_PREFIX/opt/openjpeg/lib/libopenjp2.7.dylib"
    "$BREW_PREFIX/opt/little-cms2/lib/liblcms2.2.dylib"
    "$BREW_PREFIX/opt/libpng/lib/libpng16.16.dylib"
    "$BREW_PREFIX/opt/libtiff/lib/libtiff.6.dylib"
    "$BREW_PREFIX/opt/nss/lib/libnss3.dylib"
    "$BREW_PREFIX/opt/nss/lib/libnssutil3.dylib"
    "$BREW_PREFIX/opt/nss/lib/libsmime3.dylib"
    "$BREW_PREFIX/opt/nss/lib/libssl3.dylib"
    "$BREW_PREFIX/opt/nspr/lib/libplds4.dylib"
    "$BREW_PREFIX/opt/nspr/lib/libplc4.dylib"
    "$BREW_PREFIX/opt/nspr/lib/libnspr4.dylib"
    "$BREW_PREFIX/opt/gpgme/lib/libgpgme.45.dylib"
    "$BREW_PREFIX/opt/gpgmepp/lib/libgpgmepp.7.dylib"
    "$BREW_PREFIX/opt/libassuan/lib/libassuan.9.dylib"
    "$BREW_PREFIX/opt/libgpg-error/lib/libgpg-error.0.dylib"
    "$BREW_PREFIX/opt/gettext/lib/libintl.8.dylib"
    "$BREW_PREFIX/opt/zstd/lib/libzstd.1.dylib"
    "$BREW_PREFIX/opt/xz/lib/liblzma.5.dylib"
)

LIB_DIR="$VENDOR_DIR/pdfimages/pdfimages-lib"

for i in "${!DYLIB_NAMES[@]}"; do
    name="${DYLIB_NAMES[$i]}"
    src="${DYLIB_PATHS[$i]}"
    if [[ ! -f "$src" ]]; then
        echo "Warning: $src not found, skipping" >&2
        continue
    fi
    echo "  Copying $name"
    cp -L "$src" "$LIB_DIR/$name"
done

# ---------------------------------------------------------------------------
# Rewrite install names
# ---------------------------------------------------------------------------
echo "--- Rewriting dylib install names ---"

# First: set each dylib's own install name to @rpath/<name>
for name in "${DYLIB_NAMES[@]}"; do
    dylib="$LIB_DIR/$name"
    [[ -f "$dylib" ]] || continue

    install_name_tool -id "@rpath/$name" "$dylib"

    # Add @loader_path/ rpath so sibling dylibs can find each other
    install_name_tool -add_rpath "@loader_path/" "$dylib" 2>/dev/null || true
done

# Second: rewrite all cross-references from Homebrew paths to @rpath/
for name in "${DYLIB_NAMES[@]}"; do
    dylib="$LIB_DIR/$name"
    [[ -f "$dylib" ]] || continue

    # Get all dependencies
    otool -L "$dylib" | tail -n +2 | awk '{print $1}' | while read -r dep; do
        # Skip system libraries and already-rewritten paths
        if [[ "$dep" == /usr/lib/* ]] || [[ "$dep" == /System/* ]] || [[ "$dep" == @* ]]; then
            continue
        fi
        # Find which of our bundled dylibs this matches
        dep_basename=$(basename "$dep")
        if [[ -f "$LIB_DIR/$dep_basename" ]]; then
            install_name_tool -change "$dep" "@rpath/$dep_basename" "$dylib"
        fi
    done
done

# Third: rewrite pdfimages binary
echo "--- Rewriting pdfimages binary ---"
PDFIMAGES_BIN="$VENDOR_DIR/pdfimages/pdfimages"

# Delete existing rpath and add new one
install_name_tool -delete_rpath "@loader_path/../lib" "$PDFIMAGES_BIN" 2>/dev/null || true
install_name_tool -add_rpath "@loader_path/pdfimages-lib" "$PDFIMAGES_BIN"

# Rewrite any non-system, non-rpath references
otool -L "$PDFIMAGES_BIN" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    if [[ "$dep" == /usr/lib/* ]] || [[ "$dep" == /System/* ]] || [[ "$dep" == @rpath/* ]]; then
        continue
    fi
    dep_basename=$(basename "$dep")
    if [[ -f "$LIB_DIR/$dep_basename" ]]; then
        install_name_tool -change "$dep" "@rpath/$dep_basename" "$PDFIMAGES_BIN"
    fi
done

# ---------------------------------------------------------------------------
# Part 2: exiftool
# ---------------------------------------------------------------------------
echo "--- Downloading exiftool $EXIFTOOL_VERSION ---"
TMPDIR_ET=$(mktemp -d)
trap "rm -rf '$TMPDIR_ET'" EXIT

curl -fSL "$EXIFTOOL_URL" -o "$TMPDIR_ET/exiftool.tar.gz"
tar xzf "$TMPDIR_ET/exiftool.tar.gz" -C "$TMPDIR_ET"

ET_DIR="$TMPDIR_ET/Image-ExifTool-${EXIFTOOL_VERSION}"
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
# Part 3: Ad-hoc codesign everything
# ---------------------------------------------------------------------------
echo "--- Ad-hoc codesigning ---"

# Sign dylibs first (dependencies before dependents)
for name in "${DYLIB_NAMES[@]}"; do
    dylib="$LIB_DIR/$name"
    [[ -f "$dylib" ]] || continue
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
