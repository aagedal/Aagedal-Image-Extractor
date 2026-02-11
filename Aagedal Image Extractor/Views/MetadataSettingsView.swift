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
            Text("IPTC Metadata")
                .font(.headline)
            Spacer()
            Toggle("Enable", isOn: $configuration.metadataEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding()
    }

    // MARK: - Field Sections

    private var scrollableFields: some View {
        ScrollView {
            VStack(spacing: 16) {
                fieldSection(
                    title: "Headline",
                    subtitle: "IPTC Headline",
                    config: $configuration.heading
                )
                fieldSection(
                    title: "Description",
                    subtitle: "IPTC Caption/Abstract",
                    config: $configuration.description
                )
                fieldSection(
                    title: "Extended Description",
                    subtitle: "IPTC Ext: Accessibility Description",
                    config: $configuration.extendedDescription,
                    hint: "Auto-generates file name and page number"
                )
                fieldSection(
                    title: "Keywords",
                    subtitle: "IPTC Keywords",
                    config: $configuration.keywords,
                    hint: "Separate keywords with commas or semicolons"
                )
                fieldSection(
                    title: "Copyright",
                    subtitle: "IPTC Copyright Notice",
                    config: $configuration.copyright
                )
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

                        if !config.wrappedValue.customText.trimmingCharacters(in: .whitespaces).isEmpty {
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
