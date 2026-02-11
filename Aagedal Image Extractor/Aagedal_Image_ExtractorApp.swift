import SwiftUI

@main
struct Aagedal_Image_ExtractorApp: App {
    @State private var viewModel = DocumentListViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .defaultSize(width: 700, height: 500)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
