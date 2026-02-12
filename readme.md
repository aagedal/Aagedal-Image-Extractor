# Aagedal Image Extractor

A macOS app for batch extracting images from PDF and DOCX files. Supports JPEG and TIFF output, optional OCR to produce searchable PDFs, and IPTC metadata writing.

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

- **Drag-and-drop** PDF and DOCX files for processing
- **Export formats**: JPEG, TIFF
- **OCR**: Generate a searchable PDF alongside extracted images (macOS Vision framework)
- **IPTC metadata**: Write heading, description, keywords, and copyright fields to extracted images via exiftool
- **Output options**: Save next to originals or to a custom directory
- **Bundled tools**: Ships with pdfimages and exiftool — no manual installation required
- **Homebrew override**: Optionally use Homebrew-installed versions of pdfimages and exiftool instead of the bundled copies

## Requirements

- macOS 15.0 or later

## Building from Source

1. Open `Aagedal Image Extractor.xcodeproj` in Xcode.
2. Run `Scripts/prepare-vendor.sh` to download and prepare the bundled pdfimages binaries and exiftool.
3. Build and run.

The build phase script `Scripts/bundle-tools.sh` automatically copies the vendored tools into the app bundle.

## Acknowledgements

This app relies on the following open-source tools:

- **[pdfimages (Poppler)](https://poppler.freedesktop.org/)** — Extracts images from PDF files. Poppler is licensed under the GNU General Public License (GPL).
- **[ExifTool](https://exiftool.org/)** by Phil Harvey — Reads and writes metadata in image files. ExifTool is licensed under the Artistic License or the GNU General Public License.
- **[jxl-coder-swift](https://github.com/niclas-eberle/jxl-coder-swift)** — JPEG XL encoding support via Swift Package Manager.

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for the full text.
