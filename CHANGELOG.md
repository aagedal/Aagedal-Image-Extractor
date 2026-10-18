# Changelog

## 1.2.0

- Extract images from more Office and OpenDocument formats, EPUB, ZIP/CBZ, and RTF/RTFD. Legacy Office 97–2003 DOC/PPT/XLS images are extracted natively, without LibreOffice.
- Export PNG with transparency and lossless JPEG XL, including reversible JPEG recompression and preservation of supported 16-bit images and ICC profiles.
- Keep extraction settings consistent throughout each batch and preserve earlier exports in separate numbered folders.
- Preview generated metadata in settings and retry failed documents with updated settings.
- Bundle JPEG XL encoding alongside pdfimages and ExifTool.
- Resolve bundled tools' libraries automatically and include Poppler dependency license notices.

The macOS download is for Apple silicon and requires macOS 15 or later. No separate LibreOffice installation is required.
