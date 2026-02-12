import Foundation

enum OutputDestination: String, CaseIterable {
    case nextToOriginals
    case customDirectory

    var displayName: String {
        switch self {
        case .nextToOriginals: "Next to Originals"
        case .customDirectory: "Custom Directory"
        }
    }
}
