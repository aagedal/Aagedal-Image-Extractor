import SwiftUI

struct ToolbarView: View {
    @Binding var selectedFormat: ExportFormat
    @Binding var ocrEnabled: Bool
    let pdfimagesAvailable: Bool

    var body: some View {
        HStack(spacing: 16) {
            Picker("Format", selection: $selectedFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            Toggle("OCR", isOn: $ocrEnabled)
                .toggleStyle(.checkbox)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(pdfimagesAvailable ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text("pdfimages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
