import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: DocumentListViewModel

    var body: some View {
        Form {
            Section("Output Location") {
                Picker("Destination", selection: $viewModel.outputDestination) {
                    ForEach(OutputDestination.allCases, id: \.self) { destination in
                        Text(destination.displayName).tag(destination)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.outputDestination == .customDirectory {
                    HStack {
                        if let url = viewModel.customOutputDirectoryURL {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.secondary)
                            Text(url.path(percentEncoded: false))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text("No folder selected")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Button("Choose\u{2026}") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Select"
                            if panel.runModal() == .OK {
                                viewModel.customOutputDirectoryURL = panel.url
                                viewModel.saveOutputDestination()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Section("Export Format") {
                Picker("Format", selection: $viewModel.selectedFormat) {
                    ForEach(ExportFormat.availableCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Dependencies") {
                toolRow(
                    name: "pdfimages",
                    url: viewModel.pdfimagesURL,
                    purpose: "PDF image extraction",
                    bundledAvailable: viewModel.pdfimagesBundledAvailable,
                    homebrewAvailable: viewModel.pdfimagesHomebrewAvailable
                )
                toolRow(
                    name: "exiftool",
                    url: viewModel.exiftoolURL,
                    purpose: "IPTC metadata writing",
                    bundledAvailable: viewModel.exiftoolBundledAvailable,
                    homebrewAvailable: viewModel.exiftoolHomebrewAvailable
                )

                Button("Refresh Status") {
                    viewModel.refreshDependencies()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                DisclosureGroup("Advanced: Override with Homebrew") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Install newer versions via Homebrew to override the bundled tools.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("brew install poppler exiftool")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)

                            Spacer()

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    "brew install poppler exiftool", forType: .string
                                )
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy to clipboard")
                        }
                        .padding(8)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 520)
        .onChange(of: viewModel.outputDestination) {
            viewModel.saveOutputDestination()
        }
        .onChange(of: viewModel.selectedFormat) {
            viewModel.saveFormatSelection()
        }
        .onChange(of: viewModel.preferBundledTools) {
            viewModel.saveToolSourcePreference()
        }
    }

    // MARK: - Tool Row

    @ViewBuilder
    private func toolRow(
        name: String,
        url: URL?,
        purpose: String,
        bundledAvailable: Bool,
        homebrewAvailable: Bool
    ) -> some View {
        HStack {
            if let url {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.callout)
                        Text(toolSource(url))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.callout)
                        Text("Not found — \(purpose) unavailable")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if bundledAvailable && homebrewAvailable {
                Picker("Source", selection: $viewModel.preferBundledTools) {
                    Text("Bundled").tag(true as Bool)
                    Text("Homebrew").tag(false as Bool)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    private func toolSource(_ url: URL) -> String {
        let path = url.path
        if path.contains("/Contents/Helpers/") || path.contains("/Contents/Resources/") {
            return "Bundled"
        } else if path.contains("/opt/homebrew/") || path.contains("/usr/local/") || path.contains("/opt/local/") {
            return "Homebrew (\(path))"
        } else {
            return path
        }
    }
}
