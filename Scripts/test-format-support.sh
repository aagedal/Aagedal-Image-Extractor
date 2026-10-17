#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/image-extractor-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
SOURCES="$PROJECT_DIR/Aagedal Image Extractor"
swiftc -parse-as-library -module-cache-path "$TEST_DIR/modules" \
    "$SOURCES/Models/AppError.swift" \
    "$SOURCES/Models/DocumentItem.swift" \
    "$SOURCES/Models/ProcessingState.swift" \
    "$SOURCES/Models/ExportFormat.swift" \
    "$SOURCES/Services/ProcessRunner.swift" \
    "$SOURCES/Services/ArchiveImageExtractor.swift" \
    "$SOURCES/Services/PDFImageExtractor.swift" \
    "$PROJECT_DIR/Tests/FormatSupportChecks.swift" \
    -o "$TEST_DIR/format-checks"
"$TEST_DIR/format-checks"

# Optional: test the real converter against an existing Xcode build and its JPEG XL dependency.
if [[ $# -gt 0 ]]; then
    PRODUCTS="$1/Build/Products/Debug"
    JXLC_HEADERS="$1/SourcePackages/checkouts/jxl-coder-swift/Sources/jxlc/include"
    swiftc -parse-as-library -default-isolation MainActor -module-cache-path "$TEST_DIR/modules" \
        -I "$PRODUCTS" -I "$JXLC_HEADERS" -L "$PRODUCTS" \
        "$SOURCES/Models/AppError.swift" "$SOURCES/Models/ExportFormat.swift" \
        "$SOURCES/Models/MetadataConfiguration.swift" "$SOURCES/Services/MetadataWriter.swift" \
        "$SOURCES/Services/ProcessRunner.swift" \
        "$SOURCES/Services/ImageConverter.swift" "$PROJECT_DIR/Tests/RasterExportChecks.swift" \
        "$PRODUCTS/JxlCoder.o" "$PRODUCTS/jxlc.o" \
        -lbrotlicommon -lbrotlidec -lbrotlienc -lhwy -ljxl_threads -ljxl -ljxl_cms -lskcms -ljpegli \
        -lc++ -framework Accelerate -o "$TEST_DIR/raster-checks"
    "$TEST_DIR/raster-checks" "$(command -v exiftool || true)"
fi

# Exercise the real batch pipeline with a controlled pdfimages subprocess, without JXL.
swiftc -parse-as-library -default-isolation MainActor -module-cache-path "$TEST_DIR/modules" \
    "$SOURCES"/Models/*.swift \
    "$SOURCES/Services/ProcessRunner.swift" \
    "$SOURCES/Services/ArchiveImageExtractor.swift" \
    "$SOURCES/Services/PDFImageExtractor.swift" \
    "$SOURCES/Services/MetadataWriter.swift" \
    "$SOURCES/Services/OCRService.swift" \
    "$SOURCES/Services/SearchablePDFBuilder.swift" \
    "$SOURCES/Services/PdfImagesLocator.swift" \
    "$SOURCES/Services/ExiftoolLocator.swift" \
    "$SOURCES/Services/HomebrewService.swift" \
    "$SOURCES/ViewModels/DocumentListViewModel.swift" \
    "$PROJECT_DIR/Tests/BatchProcessingChecks.swift" \
    -o "$TEST_DIR/batch-checks"
"$TEST_DIR/batch-checks"
