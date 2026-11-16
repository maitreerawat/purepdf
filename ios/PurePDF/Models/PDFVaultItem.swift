import Foundation
import PDFKit
#if os(iOS)
import UIKit
#endif

/// Represents a local PDF document stored in the user's on-device PurePDF Vault.
/// Zero cloud sync, zero telemetry, 100% private local storage.
struct PDFVaultItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var fileName: String
    var createdAt: Date
    var byteSize: Int64
    var pageCount: Int
    var badgeTag: String // e.g. "Scanned", "Compressed", "Signed", "Merged", "Sample"

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}

#if os(iOS)
@MainActor
final class PDFVaultStore: ObservableObject {
    @Published var items: [PDFVaultItem] = []
    @Published var statusBanner: String?

    private let metadataKey = "purepdf.vault.items.v1"

    var vaultDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("PurePDF_Vault", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() {
        loadItems()
        if items.isEmpty {
            createStarterSamplePDF()
        }
    }

    func fileURL(for item: PDFVaultItem) -> URL {
        vaultDirectory.appendingPathComponent(item.fileName)
    }

    func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: metadataKey),
              let decoded = try? JSONDecoder().decode([PDFVaultItem].self, from: data) else {
            items = []
            return
        }
        // Keep only files that still exist on disk
        items = decoded.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
    }

    private func persistMetadata() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: metadataKey)
        }
    }

    @discardableResult
    func savePDFData(_ data: Data, title: String, badgeTag: String) -> PDFVaultItem? {
        let sanitized = title
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "/", with: "-")
        let uniqueName = "\(sanitized)_\(Int(Date().timeIntervalSince1970)).pdf"
        let destURL = vaultDirectory.appendingPathComponent(uniqueName)

        do {
            try data.write(to: destURL, options: .atomic)
            let doc = PDFDocument(data: data)
            let item = PDFVaultItem(
                id: UUID(),
                title: sanitized,
                fileName: uniqueName,
                createdAt: Date(),
                byteSize: Int64(data.count),
                pageCount: doc?.pageCount ?? 1,
                badgeTag: badgeTag
            )
            items.insert(item, at: 0)
            persistMetadata()
            statusBanner = "Saved \"\(item.title)\" (\(item.formattedSize))"
            return item
        } catch {
            statusBanner = "Failed to save PDF: \(error.localizedDescription)"
            return nil
        }
    }

    func importExternalPDF(from url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer {
            if secured { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url) else { return }
        let name = url.deletingPathExtension().lastPathComponent
        _ = savePDFData(data, title: name, badgeTag: "Imported")
    }

    func delete(_ item: PDFVaultItem) {
        let url = fileURL(for: item)
        try? FileManager.default.removeItem(at: url)
        items.removeAll { $0.id == item.id }
        persistMetadata()
    }

    /// Generates a rich 2-page sample PDF on first launch so every tool (Size Reducer, Signer, OCR, Merge/Split)
    /// can be tested immediately on iPhone or in the Xcode iOS Simulator.
    func createStarterSamplePDF() {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { ctx in
            for pageIndex in 1...2 {
                ctx.beginPage()
                let cg = ctx.cgContext

                // Subtle header bar
                cg.setFillColor(UIColor(red: 0.08, green: 0.35, blue: 0.32, alpha: 1.0).cgColor)
                cg.fill(CGRect(x: 36, y: 36, width: pageRect.width - 72, height: 68))

                let headerAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                NSString(string: "PurePDF — Sample Agreement & OCR Benchmark (Page \(pageIndex) of 2)")
                    .draw(at: CGPoint(x: 54, y: 58), withAttributes: headerAttrs)

                let bodyAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13.5, weight: .regular),
                    .foregroundColor: UIColor.darkGray
                ]
                let bodyText = """
                100% Free, Zero-Watermark, Zero-Ad, On-Device PDF Studio for iPhone.

                Why PurePDF Exists:
                Most mobile scanner and PDF utility apps lock basic document tasks behind $9.99/week subscriptions, inject watermarks onto your pages, or upload sensitive personal documents (passports, leases, tax forms, medical records) to external servers.

                PurePDF runs 100% locally on your iPhone using native Apple frameworks:
                • VisionKit Document Camera: Auto-edge detection & perspective correction.
                • CoreGraphics PDF Size Reducer: Shrinks multi-megabyte PDFs to <300 KB or <500 KB for strict web portals.
                • Vision Neural Engine OCR: Extracts searchable, copyable text completely offline.
                • Finger & Apple Pencil Signer: Draw, save, and stamp vector ink signatures and dates anywhere.
                • Page Toolkit: Merge multiple PDFs, reorder, rotate, or split pages in seconds.

                Sample Contract Clause (Try extracting this with OCR or stamping your signature below):
                "The undersigned participant confirms that all document processing occurred strictly inside local device memory with zero external network transmission."

                Authorized Signature: _______________________________     Date: _______________
                """
                NSString(string: bodyText).draw(
                    in: CGRect(x: 48, y: 130, width: pageRect.width - 96, height: 420),
                    withAttributes: bodyAttrs
                )

                // Embed a high-resolution synthetic gradient bitmap so the PDF Size Reducer has real pixels to compress
                let imgSize = CGSize(width: 900, height: 360)
                UIGraphicsBeginImageContextWithOptions(imgSize, true, 1.0)
                if let imgCtx = UIGraphicsGetCurrentContext() {
                    for row in stride(from: 0, to: Int(imgSize.height), by: 4) {
                        let ratio = CGFloat(row) / imgSize.height
                        UIColor(
                            hue: 0.45 + 0.25 * ratio,
                            saturation: 0.55,
                            brightness: 0.85 - 0.25 * ratio,
                            alpha: 1.0
                        ).setFill()
                        imgCtx.fill(CGRect(x: 0, y: CGFloat(row), width: imgSize.width, height: 4))
                    }
                    let badgeAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 28, weight: .heavy),
                        .foregroundColor: UIColor.white
                    ]
                    NSString(string: "High-Res Embedded Figure #\(pageIndex) (Try Compressing Me!)")
                        .draw(at: CGPoint(x: 44, y: 155), withAttributes: badgeAttrs)
                }
                let sampleBitmap = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()

                sampleBitmap?.draw(in: CGRect(x: 48, y: 520, width: pageRect.width - 96, height: 210))
            }
        }

        _ = savePDFData(data, title: "Welcome_PurePDF_Sample", badgeTag: "Sample")
    }
}
#endif
