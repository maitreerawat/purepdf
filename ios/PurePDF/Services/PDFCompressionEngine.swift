import Foundation
import PDFKit
#if os(iOS)
import UIKit
import CoreImage

/// Presets designed for real-world upload limits (government/visa portals, university submissions, email).
enum CompressionPreset: String, CaseIterable, Identifiable {
    case autoTargetKB = "Smart Target KB Auto-Solver"
    case extremePortal = "Strict Portal (<300 KB)"
    case standardPortal = "Standard Upload (<500 KB)"
    case balancedEmail = "Balanced Email (<1.5 MB)"
    case highQuality = "High Quality (Print)"
    case custom = "Custom DPI & Quality"

    var id: String { rawValue }

    var defaultDPI: Double {
        switch self {
        case .autoTargetKB: return 110
        case .extremePortal: return 78
        case .standardPortal: return 110
        case .balancedEmail: return 145
        case .highQuality: return 200
        case .custom: return 120
        }
    }

    var defaultJPEGQuality: Double {
        switch self {
        case .autoTargetKB: return 0.50
        case .extremePortal: return 0.32
        case .standardPortal: return 0.48
        case .balancedEmail: return 0.65
        case .highQuality: return 0.82
        case .custom: return 0.55
        }
    }

    var subtitle: String {
        switch self {
        case .autoTargetKB: return "Binary-searches the highest DPI & quality that fits under your exact KB limit"
        case .extremePortal: return "78 DPI • Maximum size reduction for strict web forms"
        case .standardPortal: return "110 DPI • Crisp text at ~70–85% smaller file size"
        case .balancedEmail: return "145 DPI • Ideal balance of sharpness and compact size"
        case .highQuality: return "200 DPI • Preserves fine detail while trimming bloat"
        case .custom: return "Fine-tune exact resolution (DPI) and JPEG compression"
        }
    }
}

struct CompressionResult {
    let data: Data
    let originalBytes: Int64
    let compressedBytes: Int64
    let pageCount: Int
    let appliedDPI: Int
    let appliedQualityPercent: Int
    let metTargetKB: Bool

    var savedBytes: Int64 {
        max(0, originalBytes - compressedBytes)
    }

    var reductionPercentage: Double {
        guard originalBytes > 0 else { return 0 }
        return Double(originalBytes - compressedBytes) / Double(originalBytes) * 100.0
    }

    var formattedOriginal: String {
        ByteCountFormatter.string(fromByteCount: originalBytes, countStyle: .file)
    }

    var formattedCompressed: String {
        ByteCountFormatter.string(fromByteCount: compressedBytes, countStyle: .file)
    }
}

enum PDFCompressionEngine {
    /// Automatically binary-searches across a 10-step (DPI, JPEG Quality) ladder to find the highest-fidelity PDF
    /// that strictly fits under `targetKB * 1024` bytes.
    static func autoSolveTargetKB(
        at sourceURL: URL,
        targetKB: Int,
        convertToGrayscale: Bool
    ) -> CompressionResult? {
        let targetBytes = Int64(max(30, targetKB)) * 1024
        // Ordered from highest quality (index 0) to most aggressive compression (index 9)
        let ladder: [(dpi: Double, quality: Double)] = [
            (210, 0.84),
            (180, 0.74),
            (155, 0.64),
            (135, 0.56),
            (118, 0.48),
            (102, 0.40),
            (88, 0.34),
            (74, 0.28),
            (62, 0.22),
            (50, 0.15)
        ]

        var low = 0
        var high = ladder.count - 1
        var bestFitting: CompressionResult? = nil
        var smallestFallback: CompressionResult? = nil

        while low <= high {
            let mid = (low + high) / 2
            let step = ladder[mid]
            guard let candidate = compressPDF(
                at: sourceURL,
                dpi: step.dpi,
                jpegQuality: step.quality,
                convertToGrayscale: convertToGrayscale
            ) else {
                break
            }

            if smallestFallback == nil || candidate.compressedBytes < smallestFallback!.compressedBytes {
                smallestFallback = candidate
            }

            if candidate.compressedBytes <= targetBytes {
                bestFitting = candidate
                // Try higher quality (smaller index) to get as close to targetKB as possible without exceeding it
                high = mid - 1
            } else {
                // Need stronger compression (larger index)
                low = mid + 1
            }
        }

        if let fit = bestFitting {
            return CompressionResult(
                data: fit.data,
                originalBytes: fit.originalBytes,
                compressedBytes: fit.compressedBytes,
                pageCount: fit.pageCount,
                appliedDPI: fit.appliedDPI,
                appliedQualityPercent: fit.appliedQualityPercent,
                metTargetKB: true
            )
        }

        if let fb = smallestFallback {
            return CompressionResult(
                data: fb.data,
                originalBytes: fb.originalBytes,
                compressedBytes: fb.compressedBytes,
                pageCount: fb.pageCount,
                appliedDPI: fb.appliedDPI,
                appliedQualityPercent: fb.appliedQualityPercent,
                metTargetKB: fb.compressedBytes <= targetBytes
            )
        }
        return nil
    }

    /// Compresses a PDF completely on-device by rasterizing and re-encoding pages at target DPI and JPEG quality,
    /// with optional grayscale conversion to strip color channel overhead.
    static func compressPDF(
        at sourceURL: URL,
        dpi: Double,
        jpegQuality: Double,
        convertToGrayscale: Bool
    ) -> CompressionResult? {
        guard let originalData = try? Data(contentsOf: sourceURL),
              let document = PDFDocument(data: originalData),
              document.pageCount > 0 else {
            return nil
        }

        let clampedDPI = max(45.0, min(300.0, dpi))
        let scaleFactor = CGFloat(clampedDPI / 72.0)
        let clampedQuality = CGFloat(max(0.10, min(0.95, jpegQuality)))
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])

        let firstBounds = document.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: firstBounds)

        let compressedData = renderer.pdfData { ctx in
            for idx in 0..<document.pageCount {
                guard let page = document.page(at: idx) else { continue }
                let pageBounds = page.bounds(for: .mediaBox)
                ctx.beginPage(withBounds: pageBounds, pageInfo: [:])

                let targetPixelSize = CGSize(
                    width: max(1, pageBounds.width * scaleFactor),
                    height: max(1, pageBounds.height * scaleFactor)
                )

                let imgFormat = UIGraphicsImageRendererFormat()
                imgFormat.scale = 1.0
                imgFormat.opaque = true

                let pageImageRenderer = UIGraphicsImageRenderer(size: targetPixelSize, format: imgFormat)
                var renderedImage = pageImageRenderer.image { imgCtx in
                    UIColor.white.setFill()
                    imgCtx.fill(CGRect(origin: .zero, size: targetPixelSize))

                    let cg = imgCtx.cgContext
                    cg.saveGState()
                    cg.translateBy(x: 0, y: targetPixelSize.height)
                    cg.scaleBy(x: scaleFactor, y: -scaleFactor)
                    page.draw(with: .mediaBox, to: cg)
                    cg.restoreGState()
                }

                if convertToGrayscale, let ciInput = CIImage(image: renderedImage) {
                    if let filter = CIFilter(name: "CIColorControls") {
                        filter.setValue(ciInput, forKey: kCIInputImageKey)
                        filter.setValue(0.0, forKey: kCIInputSaturationKey)
                        filter.setValue(1.08, forKey: kCIInputContrastKey)
                        if let output = filter.outputImage,
                           let cgOut = ciContext.createCGImage(output, from: output.extent) {
                            renderedImage = UIImage(cgImage: cgOut)
                        }
                    }
                }

                if let jpegData = renderedImage.jpegData(compressionQuality: clampedQuality),
                   let downsampledUIImage = UIImage(data: jpegData) {
                    downsampledUIImage.draw(in: pageBounds)
                } else {
                    renderedImage.draw(in: pageBounds)
                }
            }
        }

        return CompressionResult(
            data: compressedData,
            originalBytes: Int64(originalData.count),
            compressedBytes: Int64(compressedData.count),
            pageCount: document.pageCount,
            appliedDPI: Int(clampedDPI.rounded()),
            appliedQualityPercent: Int((clampedQuality * 100.0).rounded()),
            metTargetKB: true
        )
    }
}
#endif
