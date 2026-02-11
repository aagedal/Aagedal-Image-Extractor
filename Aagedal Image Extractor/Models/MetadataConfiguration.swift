import Foundation

enum TextPlacement: String, CaseIterable, Codable {
    case prepend
    case append
}

struct MetadataFieldConfig: Codable {
    var enabled: Bool = false
    var includeDocumentName: Bool = false
    var customText: String = ""
    var textPlacement: TextPlacement = .prepend
}

struct MetadataConfiguration: Codable {
    var metadataEnabled: Bool = false
    var heading = MetadataFieldConfig()
    var description = MetadataFieldConfig()
    var extendedDescription = MetadataFieldConfig(enabled: true, includeDocumentName: true)
    var keywords = MetadataFieldConfig(enabled: true, includeDocumentName: true)
    var copyright = MetadataFieldConfig()
}
