import AppKit
import SwiftUI

struct SetupGuideView: View {
    @Bindable var viewModel: DocumentListViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text("Setup Required")
                    .font(.title2.bold())

                Text("PDF image extraction requires **pdfimages** from the Poppler package.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            VStack(alignment: .leading, spacing: 20) {
                homebrewStep
                popplerStep
            }
            .padding()
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 460)

            HStack(spacing: 16) {
                Button("Refresh Status") {
                    viewModel.refreshDependencies()
                }
                .buttonStyle(.bordered)

                Button("Skip — DOCX only") {
                    viewModel.setupDismissed = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Step 1: Homebrew

    @ViewBuilder
    private var homebrewStep: some View {
        StepRow(number: 1, title: "Install Homebrew", isComplete: viewModel.homebrewInstalled) {
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

    // MARK: - Step 2: Poppler

    @ViewBuilder
    private var popplerStep: some View {
        StepRow(number: 2, title: "Install Poppler", isComplete: viewModel.pdfimagesAvailable) {
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
                        Text("Installing poppler…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("This may take a few minutes.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
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
}

// MARK: - StepRow

struct StepRow<Content: View>: View {
    let number: Int
    let title: String
    let isComplete: Bool
    let content: Content

    init(number: Int, title: String, isComplete: Bool, @ViewBuilder content: () -> Content) {
        self.number = number
        self.title = title
        self.isComplete = isComplete
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green : Color.accentColor)
                    .frame(width: 28, height: 28)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)

                content
            }

            Spacer(minLength: 0)
        }
    }
}
