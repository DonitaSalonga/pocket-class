import SwiftUI
import QuickLook

/// A downloaded file ready to preview.
struct PreviewItem: Identifiable { let id = UUID(); let title: String; let url: URL }

/// Quick Look preview of a local file with a ShareLink for "Open in" and sharing.
struct FilePreview: View {
    let item: PreviewItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            QuickLookView(url: item.url).ignoresSafeArea(edges: .bottom)
                .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { ShareLink(item: item.url) }
                }
        }
    }
}

private struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
