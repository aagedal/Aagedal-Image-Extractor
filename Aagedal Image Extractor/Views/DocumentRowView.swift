import SwiftUI

struct DocumentRowView: View {
    let item: DocumentItem
    let onReveal: () -> Void
    let onRemove: () -> Void

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

            if item.state.isFinished {
                Button(action: onReveal) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove")
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
