import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: DocumentListViewModel

    var body: some View {
        Form {
            Section("Export Format") {
                Picker("Format", selection: $viewModel.selectedFormat) {
                    ForEach(ExportFormat.availableCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Dependencies") {
                homebrewStep
                popplerStep
                exiftoolStep

                Button("Refresh Status") {
                    viewModel.refreshDependencies()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 420)
        .onChange(of: viewModel.selectedFormat) {
            viewModel.saveFormatSelection()
        }
    }

    // MARK: - Step 1: Homebrew

    @ViewBuilder
    private var homebrewStep: some View {
        StepRow(number: 1, title: "Homebrew", isComplete: viewModel.homebrewInstalled) {
            if viewModel.homebrewInstalled {
                Label("Homebrew is installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste this command in Terminal:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(HomebrewService.installCommand)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(2)
                            .textSelection(.enabled)

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                HomebrewService.installCommand, forType: .string
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

                    Button("Open Terminal") {
                        NSWorkspace.shared.open(
                            URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Step 2: Poppler (pdfimages)

    @ViewBuilder
    private var popplerStep: some View {
        StepRow(number: 2, title: "Poppler (pdfimages)", isComplete: viewModel.pdfimagesAvailable) {
            if viewModel.pdfimagesAvailable {
                Label("pdfimages is available", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else if !viewModel.homebrewInstalled {
                Text("Complete step 1 first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if viewModel.isInstallingPoppler {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Installing poppler...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("This may take a few minutes.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("brew install poppler")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("brew install poppler", forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy to clipboard")
                    }
                    .padding(8)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button("Install Poppler") {
                        Task { await viewModel.installPoppler() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if let error = viewModel.installError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    // MARK: - Step 3: exiftool

    @ViewBuilder
    private var exiftoolStep: some View {
        StepRow(number: 3, title: "exiftool", isComplete: viewModel.exiftoolAvailable) {
            if viewModel.exiftoolAvailable {
                Label("exiftool is available", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else if !viewModel.homebrewInstalled {
                Text("Complete step 1 first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("brew install exiftool")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("brew install exiftool", forType: .string)
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
        }
    }
}
