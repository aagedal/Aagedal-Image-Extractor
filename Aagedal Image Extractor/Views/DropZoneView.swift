import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let pdfimagesAvailable: Bool
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Drop PDF or DOCX files here")
                .font(.title3)
                .foregroundStyle(.secondary)

            if !pdfimagesAvailable {
                Label(
                    "pdfimages not found — install Poppler: brew install poppler",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
        }
        .padding()
    }
}
