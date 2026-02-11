import SwiftUI

struct DocumentListView: View {
    let documents: [DocumentItem]
    let onReveal: (DocumentItem) -> Void
    let onRemove: (DocumentItem) -> Void

    var body: some View {
        List(documents) { item in
            DocumentRowView(
                item: item,
                onReveal: { onReveal(item) },
                onRemove: { onRemove(item) }
            )
        }
        .listStyle(.inset)
    }
}
