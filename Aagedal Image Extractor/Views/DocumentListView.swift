import SwiftUI

struct DocumentListView: View {
    let documents: [DocumentItem]
    let onReveal: (DocumentItem) -> Void
    let onRemove: (DocumentItem) -> Void
    let onRetry: (DocumentItem) -> Void
    let isProcessing: Bool

    var body: some View {
        List(documents) { item in
            DocumentRowView(
                item: item,
                onReveal: { onReveal(item) },
                onRemove: { onRemove(item) },
                onRetry: { onRetry(item) },
                canRetry: !isProcessing
            )
        }
        .listStyle(.inset)
    }
}
