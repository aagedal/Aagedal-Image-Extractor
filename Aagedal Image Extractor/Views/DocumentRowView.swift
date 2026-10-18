import SwiftUI

struct DocumentRowView: View {
    let item: DocumentItem
    let onReveal: () -> Void
    let onRemove: () -> Void
    let onRetry: () -> Void
    let canRetry: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.documentType.icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.body)
                    .lineLimit(1)
                    .help(item.sourceURL.path)

                if item.state.isProcessing {
                    ProgressView(value: item.state.progressValue)
                        .progressViewStyle(.linear)
                }

                Text(item.state.statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            if case .completed(let count) = item.state {
                Text("\(count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15), in: Capsule())
            }

            if case .failed = item.state {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Queue for retry with current settings, then click Extract")
                .accessibilityLabel("Retry \(item.fileName)")
                .disabled(!canRetry)
            }

            if item.outputDirectoryURL != nil {
                Button(action: onReveal) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
                .accessibilityLabel("Reveal output for \(item.fileName)")
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove")
            .disabled(item.state.isProcessing)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch item.state {
        case .failed: .red
        case .completed: .green
        default: .secondary
        }
    }
}
