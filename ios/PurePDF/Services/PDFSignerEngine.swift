import Foundation
import PDFKit
#if os(iOS)
import UIKit

enum SignatureInkColor: String, CaseIterable, Identifiable {
    case jetBlack = "Jet Black"
    case legalBlue = "Legal Blue"
    case royalNavy = "Fountain Navy"

    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .jetBlack: return UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        case .legalBlue: return UIColor(red: 0.05, green: 0.24, blue: 0.72, alpha: 1.0)
        case .royalNavy: return UIColor(red: 0.07, green: 0.16, blue: 0.40, alpha: 1.0)
        }
    }
}

enum PDFSignerEngine {
    private static let savedSignatureKey = "purepdf.saved.signature.png"

    static func saveSignatureImage(_ image: UIImage) {
        if let png = image.pngData() {
            UserDefaults.standard.set(png, forKey: savedSignatureKey)
        }
    }

    static func loadSavedSignatureImage() -> UIImage? {
        guard let data = UserDefaults.standard.data(forKey: savedSignatureKey) else { return nil }
        return UIImage(data: data)
    }

    /// Renders a transparent signature image from freehand stroke paths.
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
                for pt in stroke.dropFirst() {
                    cg.addLine(to: pt)
                }
                cg.strokePath()
            }
        }
    }

    /// Flattens a drawn signature image and optional custom text / date stamp onto a target page of a PDF.
    /// `normalizedPosition` is in [0, 1] x [0, 1] relative to the page mediaBox.
    static func stampSignature(
        onPDF sourceURL: URL,
        targetPageIndex: Int,
        signatureImage: UIImage?,
        normalizedPosition: CGPoint,
        signatureWidthRatio: CGFloat,
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

                    if let sig = signatureImage {
                        let aspect = sig.size.height / max(1, sig.size.width)
                        let sigW = bounds.width * max(0.15, min(0.65, signatureWidthRatio))
                        let sigH = sigW * aspect
                        let sigRect = CGRect(
                            x: centerX - sigW / 2,
                            y: centerY - sigH / 2,
                            width: sigW,
                            height: sigH
                        )
                        sig.draw(in: sigRect)
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
                            .font: UIFont.systemFont(ofSize: 11.5, weight: .semibold),
                            .foregroundColor: UIColor(red: 0.08, green: 0.15, blue: 0.35, alpha: 0.92)
                        ]
                        let strSize = (combined as NSString).size(withAttributes: attrs)
                        let textPt = CGPoint(
                            x: max(20, min(bounds.width - strSize.width - 20, centerX - strSize.width / 2)),
                            y: min(bounds.height - 28, centerY + 36)
                        )
                        (combined as NSString).draw(at: textPt, withAttributes: attrs)
                    }
                }
            }
        }
    }
}
#endif
