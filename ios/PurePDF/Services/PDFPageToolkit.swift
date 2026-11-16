import Foundation
import PDFKit

enum PDFPageToolkit {
    /// Merges multiple PDF files into a single combined PDF document on-device.
    static func mergePDFs(urls: [URL]) -> Data? {
        let merged = PDFDocument()
        var insertIndex = 0

        for url in urls {
            guard let doc = PDFDocument(url: url) else { continue }
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i) {
                    merged.insert(page, at: insertIndex)
                    insertIndex += 1
                }
            }
        }
        return insertIndex > 0 ? merged.dataRepresentation() : nil
    }

    /// Rotates a specific page inside a PDF by 90 degrees clockwise and returns updated PDF data.
    static func rotatePage(in url: URL, pageIndex: Int) -> Data? {
        guard let doc = PDFDocument(url: url),
              let page = doc.page(at: pageIndex) else { return nil }
        page.rotation = (page.rotation + 90) % 360
        return doc.dataRepresentation()
    }

    /// Deletes a specific page from a PDF (if pageCount > 1) and returns updated PDF data.
    static func deletePage(in url: URL, pageIndex: Int) -> Data? {
        guard let doc = PDFDocument(url: url),
              doc.pageCount > 1,
              pageIndex >= 0 && pageIndex < doc.pageCount else { return nil }
        doc.removePage(at: pageIndex)
        return doc.dataRepresentation()
    }
}
