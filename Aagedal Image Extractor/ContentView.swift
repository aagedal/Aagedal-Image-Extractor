import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var viewModel: DocumentListViewModel
    @State private var isDropTargeted = false
    @State private var showFileImporter = false

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(
                selectedFormat: $viewModel.selectedFormat,
                ocrEnabled: $viewModel.ocrEnabled,
                pdfimagesAvailable: viewModel.pdfimagesAvailable
            )

            Divider()

            if viewModel.hasDocuments {
                DocumentListView(
                    documents: viewModel.documents,
                    onReveal: { viewModel.revealInFinder($0) },
                    onRemove: { viewModel.removeDocument($0) }
                )

                Divider()

                HStack {
                    Button("Clear Finished") {
                        viewModel.clearFinished()
                    }
                    .disabled(!viewModel.documents.contains { $0.state.isFinished })

                    Spacer()

                    Button("Extract Images") {
                        Task {
                            await viewModel.processAll()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.hasPendingDocuments || viewModel.isProcessing)
                }
                .padding()
            } else {
                DropZoneView(pdfimagesAvailable: viewModel.pdfimagesAvailable, isTargeted: isDropTargeted)
            }
        }
        .frame(minWidth: 500, minHeight: 350)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, UTType(filenameExtension: "docx")!],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                viewModel.addDocuments(urls: urls)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Import", systemImage: "plus")
                }
                .keyboardShortcut("o")
            }
        }
        .alert(
            "Error",
            isPresented: $viewModel.showError,
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil)
                    else { return }
                    Task { @MainActor in
                        viewModel.addDocuments(urls: [url])
                    }
                }
            }
        }
        return handled
    }
}
