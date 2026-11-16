import SwiftUI
import PDFKit

#if os(iOS)
struct PDFKitRepresentedView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor.secondarySystemBackground
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != url {
            pdfView.document = PDFDocument(url: url)
        }
    }
}

struct PDFPreviewSheet: View {
    let item: PDFVaultItem
    @EnvironmentObject var vault: PDFVaultStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitRepresentedView(url: vault.fileURL(for: item))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: vault.fileURL(for: item)) {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                    }
                }
        }
    }
}
#endif
