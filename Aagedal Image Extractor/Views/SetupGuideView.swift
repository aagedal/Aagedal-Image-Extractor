import AppKit
import SwiftUI

struct SetupGuideView: View {
    @Bindable var viewModel: DocumentListViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)

                Text("pdfimages Not Found")
                    .font(.title2.bold())

                Text("The bundled **pdfimages** tool could not be located. This is needed for PDF image extraction.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            VStack(alignment: .leading, spacing: 20) {
                reinstallStep
                homebrewFallbackStep
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

    // MARK: - Step 1: Reinstall

    @ViewBuilder
    private var reinstallStep: some View {
        StepRow(number: 1, title: "Reinstall the Application", isComplete: viewModel.pdfimagesAvailable) {
            if viewModel.pdfimagesAvailable {
                Label("pdfimages is available", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Text("Download and reinstall Aagedal Image Extractor to restore the bundled tools.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 2: Homebrew Fallback

    @ViewBuilder
    private var homebrewFallbackStep: some View {
        StepRow(number: 2, title: "Or Install via Homebrew", isComplete: viewModel.pdfimagesAvailable) {
            if viewModel.pdfimagesAvailable {
                Label("pdfimages is available", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
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
                    Text("Alternatively, install via Homebrew:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Install Poppler") {
                        Task { await viewModel.installPoppler() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!viewModel.homebrewInstalled)

                    if !viewModel.homebrewInstalled {
                        Text("Requires Homebrew — visit brew.sh to install it first.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

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
