import SwiftUI
import PhotosUI
import VisionKit
#if os(iOS)
import UIKit

struct ScannerStudioView: View {
    @EnvironmentObject var vault: PDFVaultStore
    @State private var scannedPages: [UIImage] = []
    @State private var selectedFilter: ScanEnhanceFilter = .magicCrispBW
    @State private var layoutMode: ScanPageLayoutMode = .standardOnePerPage
    @State private var documentTitle: String = "Scanned_Document"
    @State private var showingCamera = false
    @State private var selectedPhotos: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Button {
                            if VNDocumentCameraViewController.isSupported {
                                showingCamera = true
                            } else {
                                addSimulatedScanPage()
                            }
                        } label: {
                            Label("Scan with Camera", systemImage: "camera.viewfinder")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.teal, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }

                        PhotosPicker(
                            selection: $selectedPhotos,
                            maxSelectionCount: 15,
                            matching: .images
                        ) {
                            Label("From Photos", systemImage: "photo.on.rectangle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. Page Layout Mode (Standard vs. 2-Sided ID Card)")
                            .font(.subheadline.weight(.semibold))
                        Picker("Layout Mode", selection: $layoutMode) {
                            ForEach(ScanPageLayoutMode.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("2. Enhancement Filter (Zero Watermark)")
                            .font(.subheadline.weight(.semibold))
                        Picker("Filter", selection: $selectedFilter) {
                            ForEach(ScanEnhanceFilter.allCases) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if scannedPages.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: layoutMode == .idCardTwoUp ? "person.text.rectangle.fill" : "doc.viewfinder")
                                .font(.system(size: 46))
                                .foregroundStyle(.teal)
                            Text(layoutMode == .idCardTwoUp ? "2-Sided ID Card / Passport Mode" : "No Pages Scanned Yet")
                                .font(.headline)
                            Text(
                                layoutMode == .idCardTwoUp
                                    ? "Scan the Front and Back of an ID card, driver's license, or insurance card—PurePDF automatically stacks both sides centered on a single page!"
                                    : "Use your iPhone camera for automatic quad edge crop & shadow removal, or load demo pages to test filters."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                            HStack(spacing: 10) {
                                Button("Load Demo Receipt") {
                                    addSimulatedScanPage()
                                }
                                .font(.caption.weight(.bold))
                                .buttonStyle(.borderedProminent)

                                Button("Load Front+Back ID Demo") {
                                    layoutMode = .idCardTwoUp
                                    addSimulatedIDCardPair()
                                }
                                .font(.caption.weight(.bold))
                                .buttonStyle(.bordered)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(26)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Captured Scans (\(scannedPages.count))")
                                    .font(.headline)
                                Spacer()
                                Button("Clear All", role: .destructive) {
                                    scannedPages.removeAll()
                                }
                                .font(.caption)
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(Array(scannedPages.enumerated()), id: \.offset) { idx, img in
                                        let preview = DocumentScannerService.applyFilter(selectedFilter, to: img)
                                        VStack(spacing: 6) {
                                            Image(uiImage: preview)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(height: 190)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                                )
                                            Text(
                                                layoutMode == .idCardTwoUp
                                                    ? (idx % 2 == 0 ? "ID Front (#\(idx + 1))" : "ID Back (#\(idx + 1))")
                                                    : "Page \(idx + 1)"
                                            )
                                            .font(.caption2.weight(.semibold))
                                        }
                                    }
                                }
                            }

                            TextField("PDF File Name", text: $documentTitle)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                let pdfData = DocumentScannerService.buildWatermarkFreePDF(
                                    from: scannedPages,
                                    filter: selectedFilter,
                                    layoutMode: layoutMode
                                )
                                let badge = layoutMode == .idCardTwoUp ? "ID Card 2-Up" : "Scanned"
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                _ = vault.savePDFData(pdfData, title: documentTitle, badgeTag: badge)
                                scannedPages.removeAll()
                            } label: {
                                Label(
                                    layoutMode == .idCardTwoUp
                                        ? "Save 2-Sided ID Card PDF"
                                        : "Save Watermark-Free PDF (\(scannedPages.count) Pages)",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.teal, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Document Scanner")
            .sheet(isPresented: $showingCamera) {
                NativeDocumentCameraSheet(
                    onScanCompleted: { pages in
                        scannedPages.append(contentsOf: pages)
                        showingCamera = false
                    },
                    onCancel: {
                        showingCamera = false
                    }
                )
            }
            .onChange(of: selectedPhotos) { newItems in
                Task {
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let uiImg = UIImage(data: data) {
                            scannedPages.append(uiImg)
                        }
                    }
                    selectedPhotos.removeAll()
                }
            }
        }
    }

    private func addSimulatedScanPage() {
        let size = CGSize(width: 600, height: 800)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            UIColor(white: 0.93, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            NSString(string: "PUREPDF SCANNER RECEIPT\n-----------------------\nItem 1: Zero Watermarks   $0.00\nItem 2: Offline OCR       $0.00\nItem 3: PDF Compressor    $0.00\n-----------------------\nTOTAL CHARGED:            $0.00")
                .draw(in: CGRect(x: 45, y: 80, width: 510, height: 600), withAttributes: titleAttrs)
        }
        scannedPages.append(img)
    }

    private func addSimulatedIDCardPair() {
        let cardSize = CGSize(width: 640, height: 400)
        let renderer = UIGraphicsImageRenderer(size: cardSize)
        let front = renderer.image { ctx in
            UIColor(red: 0.88, green: 0.94, blue: 0.96, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: cardSize))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            NSString(string: "IDENTIFICATION CARD — FRONT\n\nName: MAITREE RAWAT\nID #: PURE-2026-0001\nStatus: 100% Free & On-Device")
                .draw(in: CGRect(x: 40, y: 50, width: 560, height: 300), withAttributes: attrs)
        }
        let back = renderer.image { ctx in
            UIColor(white: 0.94, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: cardSize))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: UIColor.darkGray
            ]
            NSString(string: "IDENTIFICATION CARD — BACK\n\n<<<<<<PUREPDF<<ONDEVICE<<2026<<<<<<\nZero Cloud • Zero Watermarks • Zero Ads")
                .draw(in: CGRect(x: 40, y: 80, width: 560, height: 260), withAttributes: attrs)
        }
        scannedPages.append(contentsOf: [front, back])
        documentTitle = "ID_Card_Front_And_Back"
    }
}
#endif
