import Foundation
import PDFKit
#if os(iOS)
import SwiftUI
import UIKit
import VisionKit
import CoreImage

enum ScanEnhanceFilter: String, CaseIterable, Identifiable {
    case magicCrispBW = "Magic Crisp B&W"
    case cleanGrayscale = "Clean Grayscale"
    case originalColor = "Original Color"

    var id: String { rawValue }
}

enum ScanPageLayoutMode: String, CaseIterable, Identifiable {
    case standardOnePerPage = "Standard (1 per Page)"
    case idCardTwoUp = "2-Sided ID Card (Front + Back on 1 Page)"

    var id: String { rawValue }
}

enum DocumentScannerService {
    private static let ciContext = CIContext(options: nil)

    /// Enhances scanned document pages on-device (removing gray phone shadows in Magic Crisp B&W mode).
    static func applyFilter(_ filter: ScanEnhanceFilter, to image: UIImage) -> UIImage {
        guard filter != .originalColor, let ciInput = CIImage(image: image) else {
            return image
        }

        guard let colorControls = CIFilter(name: "CIColorControls") else {
            return image
        }
        colorControls.setValue(ciInput, forKey: kCIInputImageKey)

        switch filter {
        case .magicCrispBW:
            colorControls.setValue(0.0, forKey: kCIInputSaturationKey)
            colorControls.setValue(1.55, forKey: kCIInputContrastKey)
            colorControls.setValue(0.08, forKey: kCIInputBrightnessKey)
        case .cleanGrayscale:
            colorControls.setValue(0.0, forKey: kCIInputSaturationKey)
            colorControls.setValue(1.18, forKey: kCIInputContrastKey)
            colorControls.setValue(0.02, forKey: kCIInputBrightnessKey)
        case .originalColor:
            break
        }

        guard let output = colorControls.outputImage,
              let cgImg = ciContext.createCGImage(output, from: output.extent) else {
            return image
        }
        return UIImage(cgImage: cgImg, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Builds a clean, zero-watermark PDF from scanned images in either Standard (1-up) or 2-Sided ID Card (2-up Front+Back) mode.
    static func buildWatermarkFreePDF(
        from images: [UIImage],
        filter: ScanEnhanceFilter,
        layoutMode: ScanPageLayoutMode = .standardOnePerPage
    ) -> Data {
        if layoutMode == .idCardTwoUp {
            return buildIDCardTwoUpPDF(from: images, filter: filter)
        }

        let usLetter = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: usLetter)

        return renderer.pdfData { ctx in
            for rawImg in images {
                ctx.beginPage()
                UIColor.white.setFill()
                ctx.fill(usLetter)

                let processed = applyFilter(filter, to: rawImg)
                let margin: CGFloat = 24
                let availRect = usLetter.insetBy(dx: margin, dy: margin)
                drawAspectFit(processed, in: availRect)
            }
        }
    }

    /// Places pairs of scans (e.g., ID Card / Driver's License / Passport Front & Back) stacked neatly on a single US Letter page.
    private static func buildIDCardTwoUpPDF(from images: [UIImage], filter: ScanEnhanceFilter) -> Data {
        let usLetter = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: usLetter)

        return renderer.pdfData { ctx in
            var idx = 0
            while idx < images.count {
                ctx.beginPage()
                UIColor.white.setFill()
                ctx.fill(usLetter)

                let topSlot = CGRect(x: 86, y: 78, width: 440, height: 280)
                let bottomSlot = CGRect(x: 86, y: 424, width: 440, height: 280)

                let frontImg = applyFilter(filter, to: images[idx])
                drawCardSlot(frontImg, in: topSlot, label: "FRONT SIDE", cg: ctx.cgContext)

                if idx + 1 < images.count {
                    let backImg = applyFilter(filter, to: images[idx + 1])
                    drawCardSlot(backImg, in: bottomSlot, label: "BACK SIDE", cg: ctx.cgContext)
                }

                idx += 2
            }
        }
    }

    private static func drawCardSlot(_ image: UIImage, in slot: CGRect, label: String, cg: CGContext) {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9.5, weight: .bold),
            .foregroundColor: UIColor.gray
        ]
        NSString(string: label).draw(at: CGPoint(x: slot.minX, y: slot.minY - 16), withAttributes: labelAttrs)

        let path = UIBezierPath(roundedRect: slot, cornerRadius: 12)
        UIColor(white: 0.98, alpha: 1.0).setFill()
        path.fill()
        UIColor(white: 0.82, alpha: 1.0).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        let inner = slot.insetBy(dx: 12, dy: 12)
        drawAspectFit(image, in: inner)
    }

    private static func drawAspectFit(_ image: UIImage, in availRect: CGRect) {
        let aspect = image.size.width / max(1, image.size.height)
        var drawRect = availRect
        if availRect.width / availRect.height > aspect {
            let w = availRect.height * aspect
            drawRect = CGRect(
                x: availRect.midX - w / 2,
                y: availRect.minY,
                width: w,
                height: availRect.height
            )
        } else {
            let h = availRect.width / aspect
            drawRect = CGRect(
                x: availRect.minX,
                y: availRect.midY - h / 2,
                width: availRect.width,
                height: h
            )
        }
        image.draw(in: drawRect)
    }
}

/// Native iOS VisionKit Document Camera wrapper (100% free built-in auto-cropping scanner).
struct NativeDocumentCameraSheet: UIViewControllerRepresentable {
    var onScanCompleted: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: NativeDocumentCameraSheet

        init(parent: NativeDocumentCameraSheet) {
            self.parent = parent
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var pages: [UIImage] = []
            for i in 0..<scan.pageCount {
                pages.append(scan.imageOfPage(at: i))
            }
            parent.onScanCompleted(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            parent.onCancel()
        }
    }
}
#endif
