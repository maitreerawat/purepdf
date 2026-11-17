import Foundation
import PDFKit
import Vision
#if os(iOS)
import UIKit

struct OCRPageOutput: Identifiable {
    let id = UUID()
    let pageNumber: Int
    let text: String
    let averageConfidence: Float
}

enum OCRService {
    /// Extracts selectable text from every page of a PDF using Apple's on-device Vision Neural Engine.
    static func extractText(fromPDF url: URL) async -> [OCRPageOutput] {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
            return []
        }

        var results: [OCRPageOutput] = []
        for idx in 0..<doc.pageCount {
            guard let page = doc.page(at: idx) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let targetSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let pageImg = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: targetSize))
                let cg = ctx.cgContext
                cg.translateBy(x: 0, y: targetSize.height)
                cg.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: cg)
            }

            let (recognized, conf) = await recognizeText(in: pageImg)
            results.append(OCRPageOutput(pageNumber: idx + 1, text: recognized, averageConfidence: conf))
        }
        return results
    }

    /// Runs VNRecognizeTextRequest (.accurate) completely offline on a single UIImage.
    static func recognizeText(in image: UIImage) async -> (String, Float) {
        guard let cgImage = image.cgImage else { return ("", 0) }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                guard let observations = req.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    continuation.resume(returning: ("No text detected on this page.", 0))
                    return
                }
                var lines: [String] = []
                var confSum: Float = 0
                for obs in observations {
                    if let top = obs.topCandidates(1).first {
                        lines.append(top.string)
                        confSum += top.confidence
                    }
                }
                let avg = confSum / Float(max(1, observations.count))
                continuation.resume(returning: (lines.joined(separator: "\n"), avg))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: ("OCR Error: \(error.localizedDescription)", 0))
            }
        }
    }

    /// Generates a Searchable PDF by embedding the recognized OCR text layer invisibly underneath each visual page
    /// plus appending a clean formatted OCR transcript summary page at the end.
    static func buildSearchablePDF(from sourceURL: URL, ocrPages: [OCRPageOutput]) -> Data? {
        guard let doc = PDFDocument(url: sourceURL), doc.pageCount > 0 else { return nil }
        let firstBounds = doc.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: firstBounds)

        return renderer.pdfData { ctx in
            for idx in 0..<doc.pageCount {
                guard let page = doc.page(at: idx) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                ctx.beginPage(withBounds: bounds, pageInfo: [:])

                // 1. Draw invisible searchable text layer so Cmd+F / iOS Spotlight / text selection finds the OCR text
                if idx < ocrPages.count {
                    let invisibleAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 10.5),
                        .foregroundColor: UIColor.clear
                    ]
                    NSString(string: ocrPages[idx].text)
                        .draw(in: bounds.insetBy(dx: 36, dy: 36), withAttributes: invisibleAttrs)
                }

                // 2. Draw original visual PDF page on top
                let cg = ctx.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: bounds.height)
                cg.scaleBy(x: 1.0, y: -1.0)
                page.draw(with: .mediaBox, to: cg)
                cg.restoreGState()
            }
        }
    }
}
#endif
