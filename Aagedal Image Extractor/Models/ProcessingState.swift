import Foundation

enum ProcessingState: Equatable {
    case pending
    case extracting(progress: Double)
    case converting(progress: Double)
    case runningOCR(progress: Double)
    case completed(imageCount: Int)
    case failed(message: String)

    var isProcessing: Bool {
        switch self {
        case .extracting, .converting, .runningOCR: true
        default: false
        }
    }

    var isFinished: Bool {
        switch self {
        case .completed, .failed: true
        default: false
        }
    }

    var progressValue: Double {
        switch self {
        case .pending: 0
        case .extracting(let p): p * 0.5
        case .converting(let p): 0.5 + p * 0.3
        case .runningOCR(let p): 0.8 + p * 0.2
        case .completed: 1.0
        case .failed: 0
        }
    }

    var statusText: String {
        switch self {
        case .pending: "Pending"
        case .extracting: "Extracting images…"
        case .converting: "Converting…"
        case .runningOCR: "Running OCR…"
        case .completed(let count): "\(count) image\(count == 1 ? "" : "s") extracted"
        case .failed(let message): "Failed: \(message)"
        }
    }
}
