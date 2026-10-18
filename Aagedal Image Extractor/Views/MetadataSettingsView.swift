import SwiftUI

struct MetadataSettingsView: View {
    @Binding var configuration: MetadataConfiguration
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            scrollableFields
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 500)
        .frame(idealWidth: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Image Metadata")
                .font(.headline)
            Spacer()
            Toggle("Enable", isOn: $configuration.metadataEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Enable metadata writing")
        }
        .padding()
    }

    // MARK: - Field Sections

    private var scrollableFields: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Enabled fields replace existing values in exported images. Fields with no generated or custom text are left unchanged. JPEG XL receives XMP metadata; other formats receive XMP and IPTC where supported.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                fieldSection(
                    title: "Headline",
                    subtitle: "XMP Headline / IPTC Headline",
                    config: $configuration.heading
                )
                fieldSection(
                    title: "Description",
                    subtitle: "XMP Description / IPTC Caption/Abstract",
                    config: $configuration.description
                )
                fieldSection(
                    title: "Extended Description",
                    subtitle: "XMP IPTC Core: Accessibility Description",
                    config: $configuration.extendedDescription,
                    hint: "Include document name adds the source filename and, for PDF images, the page number."
                )
                fieldSection(
                    title: "Keywords",
                    subtitle: "XMP Subject / IPTC Keywords",
                    config: $configuration.keywords,
                    hint: "Separate keywords with commas or semicolons. Replaces the existing keyword list."
                )
                fieldSection(
                    title: "Copyright",
                    subtitle: "XMP Rights / IPTC Copyright Notice",
                    config: $configuration.copyright
                )
                metadataPreview
            }
            .padding()
        }
        .disabled(!configuration.metadataEnabled)
        .opacity(configuration.metadataEnabled ? 1.0 : 0.5)
    }

    // MARK: - Single Field Section

    private func fieldSection(
        title: String,
        subtitle: String,
        config: Binding<MetadataFieldConfig>,
        hint: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Toggle(isOn: config.enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).bold()
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                Spacer()
            }

            if config.wrappedValue.enabled {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Include document name", isOn: config.includeDocumentName)
                        .toggleStyle(.checkbox)
                        .font(.callout)

                    if let hint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    HStack {
                        TextField("Custom text", text: config.customText)
                            .textFieldStyle(.roundedBorder)

                        if !config.wrappedValue.customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Picker("Placement", selection: config.textPlacement) {
                                Text("Before").tag(TextPlacement.prepend)
                                Text("After").tag(TextPlacement.append)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var metadataPreview: some View {
        let fields = MetadataWriter.resolve(configuration: configuration,
                                            documentFileName: "Example.pdf", pageNumber: 3).previewFields
        return VStack(alignment: .leading, spacing: 8) {
            Text("Example: Example.pdf, page 3").font(.headline)
            Text("Before/After places custom text before or after the document name. Page numbers are included only in Extended Description for PDF images.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if fields.isEmpty {
                Text("No metadata fields will be written.")
                    .foregroundStyle(.secondary)
            }
            ForEach(fields, id: \.title) { field in
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.title).font(.caption.bold())
                    Text(field.value).textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}
