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

    /// Encrypts a PDF on-device with a user/owner password using native PDFKit options.
    static func encryptPDF(at sourceURL: URL, password: String) -> Data? {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let doc = PDFDocument(url: sourceURL) else { return nil }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("purepdf_locked_\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let options: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: trimmed,
            .ownerPasswordOption: trimmed
        ]
        guard doc.write(to: tempURL, withOptions: options) else { return nil }
        return try? Data(contentsOf: tempURL)
    }

    /// Unlocks an encrypted PDF on-device given its password and returns an unencrypted copy.
    static func unlockPDF(at sourceURL: URL, password: String) -> Data? {
        guard let doc = PDFDocument(url: sourceURL) else { return nil }
        if doc.isLocked {
            guard doc.unlock(withPassword: password) else { return nil }
        }
        return doc.dataRepresentation()
    }
}
#endif
