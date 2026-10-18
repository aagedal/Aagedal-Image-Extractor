These unmodified regression documents come from Apache POI's `test-data` directory,
retrieved 2026-10-18. The upstream LICENSE and NOTICE are included here.

- `PngPicture.doc`: https://github.com/apache/poi/blob/trunk/test-data/document/PngPicture.doc
- `pictures.ppt`: https://github.com/apache/poi/blob/trunk/test-data/slideshow/pictures.ppt
- `SimpleWithImages.xls`: https://github.com/apache/poi/blob/trunk/test-data/spreadsheet/SimpleWithImages.xls

They exercise real Word picture storage, PowerPoint's mixed raster/metafile Pictures
stream, and Excel drawing groups. Synthetic fixtures in `LegacyOfficeChecks.swift`
cover v3/v4 compound storage, mini streams, sector-spanning records, split BIFF
records, duplicate payloads, malformed chains, truncation and encryption rejection.
