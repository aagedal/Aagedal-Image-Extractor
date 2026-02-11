import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var viewModel: DocumentListViewModel
    @State private var isDropTargeted = false
    @State private var showFileImporter = false
    @State private var showMetadataSheet = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.hasDocuments {
                DocumentListView(
                    documents: viewModel.documents,
                    onReveal: { viewModel.revealInFinder($0) },
                    onRemove: { viewModel.removeDocument($0) }
                )
            } else if !viewModel.pdfimagesAvailable && !viewModel.setupDismissed {
                SetupGuideView(viewModel: viewModel)
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
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Import", systemImage: "plus")
                }
                .keyboardShortcut("o")
            }
            
            ToolbarItem {
                Spacer()
            }
            
            ToolbarItemGroup {
                Button {
                    Task { await viewModel.processAll() }
                } label: {
                    Label("Extract", systemImage: "play.fill")
                }
                .help("Extract Images")
                .disabled(!viewModel.hasPendingDocuments || viewModel.isProcessing)

                Button {
                    viewModel.clearFinished()
                } label: {
                    Label("Clear Finished", systemImage: "xmark.circle")
                }
                .help("Clear Finished")
                .disabled(!viewModel.documents.contains { $0.state.isFinished })
            }

            ToolbarItem {
                Spacer()
            }
            
            ToolbarItemGroup {
                Button {
                    viewModel.ocrEnabled.toggle()
                } label: {
                    Label("OCR", systemImage: viewModel.ocrEnabled ? "richtext.page.fill" : "richtext.page")
                }
                .foregroundStyle(viewModel.ocrEnabled ? Color.accentColor : .secondary)
                .help(viewModel.ocrEnabled ? "OCR Enabled" : "OCR Disabled")

                Button {
                    showMetadataSheet = true
                } label: {
                    Label("Metadata", systemImage: viewModel.metadataConfiguration.metadataEnabled ? "tag.fill" : "tag")
                }
                .help("IPTC Metadata Settings")
                .foregroundStyle(viewModel.metadataConfiguration.metadataEnabled ? Color.accentColor : .secondary)
            }
            ToolbarItem {
                Spacer()
            }
            
            ToolbarItemGroup {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }

        }
        .sheet(isPresented: $showMetadataSheet, onDismiss: { viewModel.saveMetadataConfiguration() }) {
            MetadataSettingsView(configuration: $viewModel.metadataConfiguration)
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
