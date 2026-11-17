import Foundation
import PDFKit
#if os(iOS)
import UIKit

struct PDFPageThumbnailItem: Identifiable, Equatable {
    let id: UUID = UUID()
    let originalPageIndex: Int
    var rotationDegrees: Int // 0, 90, 180, 270
    let thumbnail: UIImage

    static func == (lhs: PDFPageThumbnailItem, rhs: PDFPageThumbnailItem) -> Bool {
        lhs.id == rhs.id && lhs.originalPageIndex == rhs.originalPageIndex && lhs.rotationDegrees == rhs.rotationDegrees
    }
}

enum PDFPageToolkit {
    /// Generates thumbnail items for all pages in a PDF so the user can visually drag-to-reorder, rotate, or split.
    static func loadPageThumbnails(from url: URL, thumbnailSize: CGSize = CGSize(width: 240, height: 320)) -> [PDFPageThumbnailItem] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var items: [PDFPageThumbnailItem] = []
        for idx in 0..<doc.pageCount {
            guard let page = doc.page(at: idx) else { continue }
            let thumb = page.thumbnail(of: thumbnailSize, for: .mediaBox)
            items.append(
                PDFPageThumbnailItem(
                    originalPageIndex: idx,
                    rotationDegrees: page.rotation,
                    thumbnail: thumb
                )
            )
        }
        return items
    }

    /// Rebuilds a PDF applying the user's visual page order, per-page rotations, and optional subset selection.
    static func rebuildPDF(
        from sourceURL: URL,
        orderedPages: [PDFPageThumbnailItem]
    ) -> Data? {
        guard let srcDoc = PDFDocument(url: sourceURL), !orderedPages.isEmpty else { return nil }
        let outDoc = PDFDocument()

        for (insertIdx, item) in orderedPages.enumerated() {
            guard let pageCopy = srcDoc.page(at: item.originalPageIndex)?.copy() as? PDFPage else { continue }
            pageCopy.rotation = item.rotationDegrees
            outDoc.insert(pageCopy, at: insertIdx)
        }
        return outDoc.dataRepresentation()
    }

    /// Merges multiple PDF files into a single combined PDF document on-device.
    static func mergePDFs(urls: [URL]) -> Data? {
        let merged = PDFDocument()
        var insertIndex = 0

        for url in urls {
            guard let doc = PDFDocument(url: url) else { continue }
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i)?.copy() as? PDFPage {
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
#endif
