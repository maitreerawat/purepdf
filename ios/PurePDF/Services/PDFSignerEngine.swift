import Foundation
import PDFKit
#if os(iOS)
import UIKit

enum SignatureInkColor: String, CaseIterable, Identifiable {
    case jetBlack = "Jet Black"
    case legalBlue = "Legal Blue"
    case royalNavy = "Fountain Navy"
    case crimsonInk = "Crimson Ink"

    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .jetBlack: return UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        case .legalBlue: return UIColor(red: 0.05, green: 0.24, blue: 0.72, alpha: 1.0)
        case .royalNavy: return UIColor(red: 0.07, green: 0.16, blue: 0.40, alpha: 1.0)
        case .crimsonInk: return UIColor(red: 0.62, green: 0.08, blue: 0.14, alpha: 1.0)
        }
    }
}

enum PDFSignerEngine {
    private static let savedSignatureKey = "purepdf.saved.signature.png"
    private static let savedSignatureListKey = "purepdf.saved.signatures.list.v1"

    static func saveSignatureImage(_ image: UIImage) {
        if let png = image.pngData() {
            UserDefaults.standard.set(png, forKey: savedSignatureKey)
            var existing = loadSavedSignatureGalleryData()
            existing.insert(png, at: 0)
            if existing.count > 6 {
                existing = Array(existing.prefix(6))
            }
            UserDefaults.standard.set(existing, forKey: savedSignatureListKey)
        }
    }

    static func loadSavedSignatureImage() -> UIImage? {
        guard let data = UserDefaults.standard.data(forKey: savedSignatureKey) else { return nil }
        return UIImage(data: data)
    }

    static func loadSavedSignatureGallery() -> [UIImage] {
        loadSavedSignatureGalleryData().compactMap { UIImage(data: $0) }
    }

    static func deleteSavedSignature(at index: Int) {
        var list = loadSavedSignatureGalleryData()
        guard index >= 0 && index < list.count else { return }
        list.remove(at: index)
        UserDefaults.standard.set(list, forKey: savedSignatureListKey)
    }

    private static func loadSavedSignatureGalleryData() -> [Data] {
        UserDefaults.standard.array(forKey: savedSignatureListKey) as? [Data] ?? []
    }

    /// Renders a high-DPI preview image of a specific PDF page for interactive drag-and-drop placement.
    static func renderPagePreview(url: URL, pageIndex: Int, maxDimension: CGFloat = 900) -> (image: UIImage, pageAspect: CGFloat)? {
        guard let doc = PDFDocument(url: url),
              let page = doc.page(at: pageIndex) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let aspect = bounds.width / max(1, bounds.height)
        let scale = min(maxDimension / max(1, bounds.width), maxDimension / max(1, bounds.height))
        let targetSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let img = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            let cg = ctx.cgContext
            cg.saveGState()
            cg.translateBy(x: 0, y: targetSize.height)
            cg.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()
        }
        return (img, aspect)
    }

    /// Renders a transparent signature image from freehand stroke paths using smooth quadratic curves.
    static func renderSignatureImage(
        strokes: [[CGPoint]],
        canvasSize: CGSize,
        inkColor: UIColor,
        lineWidth: CGFloat = 3.2
    ) -> UIImage? {
        guard !strokes.isEmpty, canvasSize.width > 10, canvasSize.height > 10 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setStrokeColor(inkColor.cgColor)
            cg.setLineWidth(lineWidth)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            for stroke in strokes where stroke.count > 1 {
                cg.beginPath()
                cg.move(to: stroke[0])
                if stroke.count == 2 {
                    cg.addLine(to: stroke[1])
                } else {
                    for i in 1..<(stroke.count - 1) {
                        let prev = stroke[i]
                        let next = stroke[i + 1]
                        let mid = CGPoint(x: (prev.x + next.x) * 0.5, y: (prev.y + next.y) * 0.5)
                        cg.addQuadCurve(to: mid, control: prev)
                    }
                    if let last = stroke.last {
                        cg.addLine(to: last)
                    }
                }
                cg.strokePath()
            }
        }
    }

    /// Flattens a drawn signature image, rotation angle, and optional custom text / date stamp onto a target page of a PDF.
    /// `normalizedPosition` is in [0, 1] x [0, 1] relative to the top-left of the page mediaBox.
    static func stampSignature(
        onPDF sourceURL: URL,
        targetPageIndex: Int,
        signatureImage: UIImage?,
        normalizedPosition: CGPoint,
        signatureWidthRatio: CGFloat,
        rotationDegrees: Double = 0.0,
        customStampText: String,
        includeDateStamp: Bool
    ) -> Data? {
        guard let doc = PDFDocument(url: sourceURL), doc.pageCount > 0 else { return nil }
        let firstBounds = doc.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: firstBounds)

        return renderer.pdfData { ctx in
            for idx in 0..<doc.pageCount {
                guard let page = doc.page(at: idx) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                ctx.beginPage(withBounds: bounds, pageInfo: [:])

                let cg = ctx.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: bounds.height)
                cg.scaleBy(x: 1.0, y: -1.0)
                page.draw(with: .mediaBox, to: cg)
                cg.restoreGState()

                if idx == targetPageIndex {
                    let centerX = bounds.minX + normalizedPosition.x * bounds.width
                    let centerY = bounds.minY + normalizedPosition.y * bounds.height
                    let sigW = bounds.width * max(0.12, min(0.75, signatureWidthRatio))
                    var sigH: CGFloat = 0

                    cg.saveGState()
                    cg.translateBy(x: centerX, y: centerY)
                    cg.rotate(by: CGFloat(rotationDegrees * .pi / 180.0))

                    if let sig = signatureImage {
                        let aspect = sig.size.height / max(1, sig.size.width)
                        sigH = sigW * aspect
                        let localSigRect = CGRect(
                            x: -sigW / 2,
                            y: -sigH / 2,
                            width: sigW,
                            height: sigH
                        )
                        sig.draw(in: localSigRect)
                    }

                    var stampLines: [String] = []
                    if !customStampText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        stampLines.append(customStampText)
                    }
                    if includeDateStamp {
                        let df = DateFormatter()
                        df.dateStyle = .medium
                        stampLines.append("Signed: \(df.string(from: Date()))")
                    }

                    if !stampLines.isEmpty {
                        let combined = stampLines.joined(separator: "  •  ")
                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 11.0, weight: .semibold),
                            .foregroundColor: UIColor(red: 0.08, green: 0.15, blue: 0.35, alpha: 0.92)
                        ]
                        let strSize = (combined as NSString).size(withAttributes: attrs)
                        let textPt = CGPoint(
                            x: -strSize.width / 2,
                            y: (sigH / 2) + 4
                        )
                        (combined as NSString).draw(at: textPt, withAttributes: attrs)
                    }

                    cg.restoreGState()
                }
            }
        }
    }
}
#endif
