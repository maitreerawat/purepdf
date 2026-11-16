import SwiftUI
import PhotosUI
import VisionKit

#if os(iOS)
struct ScannerStudioView: View {
    @EnvironmentObject var vault: PDFVaultStore
    @State private var scannedPages: [UIImage] = []
    @State private var selectedFilter: ScanEnhanceFilter = .magicCrispBW
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enhancement Filter (Zero Watermark)")
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
                            Image(systemName: "doc.viewfinder")
                                .font(.system(size: 46))
                                .foregroundStyle(.teal)
                            Text("No Pages Scanned Yet")
                                .font(.headline)
                            Text("Use your iPhone camera for automatic quad edge crop & shadow removal, or generate a test receipt page to preview filters.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Load Demo Receipt Page") {
                                addSimulatedScanPage()
                            }
                            .font(.caption.weight(.bold))
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(28)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Pages (\(scannedPages.count))")
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
                                                .frame(height: 220)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                                )
                                            Text("Page \(idx + 1)")
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
                                    filter: selectedFilter
                                )
                                _ = vault.savePDFData(pdfData, title: documentTitle, badgeTag: "Scanned")
                                scannedPages.removeAll()
                            } label: {
                                Label("Save Watermark-Free PDF (\(scannedPages.count) Pages)", systemImage: "checkmark.circle.fill")
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
}
#endif
