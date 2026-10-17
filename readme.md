# Aagedal Image Extractor

A macOS app for batch extracting embedded images from PDF, Microsoft Office, OpenDocument, EPUB, ZIP/CBZ, and RTF/RTFD files. Supports original-format, JPEG, TIFF, PNG, and lossless JPEG XL output, optional OCR to produce searchable PDFs, and IPTC metadata writing.

<img width="815" height="863" alt="SCR-20260212-mzyw" src="https://github.com/user-attachments/assets/66ffe894-47bc-445b-81c9-646557f7b339" />

## Installation
#### Homebrew
```
brew install aagedal/casks/aagedal-image-extractor
```
#### Latest release
[Version 1.1.0
](https://github.com/aagedal/Aagedal-Image-Extractor/releases/download/v.1.1.0/Aagedal-Image-Extractor_1-1-0.zip)


## Features

- **Drag-and-drop** documents, ebooks, rich-text packages, and image archives for processing
- **Office**: DOCX/DOCM/DOTX/DOTM, PPTX/PPTM/POTX/POTM/PPSX/PPSM, XLSX/XLSM/XLTX/XLTM
- **OpenDocument**: ODT/ODP/ODS and OTT/OTP/OTS templates
- **Other inputs**: EPUB, ZIP, CBZ, RTF, RTFD, plus legacy DOC/PPT/XLS with LibreOffice installed
- **Export formats**: Keep original format, JPEG, TIFF, PNG (preserves transparency), lossless JPEG XL
- **OCR**: Generate a searchable PDF alongside extracted images (macOS Vision framework)
- **IPTC metadata**: Write heading, description, keywords, and copyright fields to extracted images via exiftool
- **Output options**: Save next to originals or to a custom directory
- **Consistent batches**: Export format, OCR, metadata, tools, and output destination are captured when extraction starts; settings changes apply to the next batch. Remove queued documents to skip them, and add documents for the next batch.
- **Preserve previous exports**: Repeated exports and documents with matching names receive separate numbered output folders
- **Bundled tools**: Ships with pdfimages, cjxl and exiftool — no manual installation required
- **Homebrew override**: Optionally use Homebrew-installed versions of pdfimages and exiftool instead of the bundled copies

## Requirements

- macOS 15.0 or later

## Building from Source

1. Open `Aagedal Image Extractor.xcodeproj` in Xcode.
2. Install build prerequisites with `brew install poppler jpeg-xl`, then run `Scripts/prepare-vendor.sh` to prepare bundled pdfimages, cjxl and exiftool.
3. Build and run.

The build phase script `Scripts/bundle-tools.sh` automatically copies the vendored tools into the app bundle.

Office and OpenDocument extraction reads embedded image files, including media in headers and slide masters; it does not render document pages, slides, charts, or linked images. Macro-enabled files are read as archives; macros are not executed. EPUB extraction follows image entries in package manifests, including covers, and does not download remote images. Encrypted EPUB images and password-encrypted documents are not supported; obfuscated EPUB fonts do not prevent extraction of unencrypted images. ZIP/CBZ extraction searches nested folders, preserves images with equal basenames, and ignores hidden metadata folders and symbolic links.

RTF extraction reads standard hex and binary picture payloads (PNG, JPEG, EMF, WMF, PICT and DIB). RTFD imports image attachments using macOS; non-image attachments are ignored. Some RTF documents include multiple representations of a picture, which may be exported separately. Raster conversion depends on macOS image decoding; embedded vector formats such as EMF and WMF, and raw DIB payloads, may fail conversion with an image-specific error. Choose **Keep original format** to retain those image files without raster conversion. Metadata writing, when enabled, still modifies exported files and depends on ExifTool support for their formats. OCR is available for PDF inputs only.

Legacy DOC/PPT/XLS support requires **LibreOffice**, installed in `/Applications` or `~/Applications` (or `soffice` in `/opt/homebrew/bin` or `/usr/local/bin`). Install it with `brew install --cask libreoffice` or the LibreOffice installer. The app uses a private temporary LibreOffice profile, converts to DOCX/PPTX/XLSX, and extracts the resulting embedded images. Conversion may change image representations; original-format output preserves the converted images rather than guaranteeing the legacy source bytes. LibreOffice is not bundled.

JPEG XL uses the reference **cjxl** encoder with lossless compression (distance 0, effort 7, up to 8 threads). JPEG inputs, including JPEGs embedded in PDFs, use reversible JPEG recompression: exporting a resulting JXL back to JPEG reconstructs the original JPEG bytes when reconstruction data is available. PNG inputs go directly to cjxl; other supported single-frame integer RGB/grayscale images use an ImageIO PNG intermediate that retains up to 16-bit samples, transparency and embedded ICC profiles. Floating-point, CMYK intermediates, and multi-page images are rejected rather than silently reducing their fidelity; choose original-format export for these. PNG animation is passed through to cjxl. Container-specific source metadata may not survive the PNG intermediate, and enabled metadata writing can change exported metadata.

The encoder is bundled for release builds and can be overridden with Homebrew (`brew install jpeg-xl`) in Dependencies. Developers can prepare only this tool with `python3 Scripts/prepare-jpeg-xl.py`; its transitive dylibs are copied and relocated so the bundle runs independently of Homebrew. A missing or failed encoder leaves the source image intact.

For PDF original-format export, `pdfimages -all` preserves JPEG, JPEG 2000, JBIG2 and CCITT encodings where available; other images are decoded to PNG/TIFF. JBIG2 globals (`.jb2g`) and CCITT parameter files (`.params`) are saved alongside their images and are not counted as additional images. Original format therefore means the extraction tool's native output, not a promise that every PDF image has a standalone original file.

Run `Scripts/test-format-support.sh` for standalone format, extraction, and batch-processing regression checks, including real RTF/RTFD fixtures and a controlled LibreOffice conversion boundary. Requires Xcode command line tools; no bundled tools or package downloads needed.
Install `jpeg-xl` and pass the path to an existing Xcode Debug derived data directory to also test PNG conversion, original-byte preservation, JPEG reconstruction, 16-bit Display P3 fidelity, encoder failures, and transparency, for example `Scripts/test-format-support.sh /tmp/aagedal-image-extractor-build`.

## Acknowledgements

This app relies on the following open-source tools:

- **[pdfimages (Poppler)](https://poppler.freedesktop.org/)** — Extracts images from PDF files. Poppler is licensed under the GNU General Public License (GPL).
- **[ExifTool](https://exiftool.org/)** by Phil Harvey — Reads and writes metadata in image files. ExifTool is licensed under the Artistic License or the GNU General Public License.
- **[libjxl / cjxl](https://github.com/libjxl/libjxl)** — Reference JPEG XL encoder. BSD 3-Clause license.
- **[jxl-coder-swift](https://github.com/awxkee/jxl-coder-swift)** — JPEG XL decoding and JPEG reconstruction support via Swift Package Manager.

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for the full text.
