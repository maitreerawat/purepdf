import SwiftUI

#if os(iOS)
struct CompressorStudioView: View {
    @EnvironmentObject var vault: PDFVaultStore
    @State private var selectedItemID: UUID?
    @State private var preset: CompressionPreset = .standardPortal
    @State private var customDPI: Double = 110
    @State private var customQuality: Double = 0.48
    @State private var convertToGrayscale: Bool = false
    @State private var result: CompressionResult?
    @State private var isCompressing: Bool = false

    private var selectedItem: PDFVaultItem? {
        vault.items.first { $0.id == selectedItemID } ?? vault.items.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    documentPickerSection

                    presetSection

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Resolution: \(Int(customDPI)) DPI")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("JPEG Quality: \(Int(customQuality * 100))%")
                                .font(.subheadline.weight(.semibold))
                        }

                        Slider(value: $customDPI, in: 50...250, step: 5) {
                            Text("DPI")
                        }
                        .onChange(of: customDPI) { _ in result = nil }

                        Slider(value: $customQuality, in: 0.15...0.92, step: 0.03) {
                            Text("Quality")
                        }
                        .onChange(of: customQuality) { _ in result = nil }

                        Toggle("Convert to Crisp Grayscale (Extra 25% Smaller)", isOn: $convertToGrayscale)
                            .font(.subheadline)
                            .onChange(of: convertToGrayscale) { _ in result = nil }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                    Button {
                        runCompression()
                    } label: {
                        HStack {
                            if isCompressing {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "arrow.down.right.and.arrow.up.left")
                            }
                            Text(isCompressing ? "Compressing On-Device..." : "Reduce PDF File Size Now")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                    }
                    .disabled(selectedItem == nil || isCompressing)

                    if let res = result, let item = selectedItem {
                        compressionResultCard(res, sourceItem: item)
                    }
                }
                .padding()
            }
            .navigationTitle("PDF Size Reducer")
            .onAppear {
                if selectedItemID == nil {
                    selectedItemID = vault.items.first?.id
                }
            }
        }
    }

    private var documentPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1. Select PDF to Compress")
                .font(.subheadline.weight(.bold))

            if vault.items.isEmpty {
                Text("No PDFs in Vault yet. Import or scan a document first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Select Document", selection: $selectedItemID) {
                    ForEach(vault.items) { item in
                        Text("\(item.title) (\(item.formattedSize))")
                            .tag(Optional(item.id))
                    }
                }
                .pickerStyle(.menu)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("2. Choose Target Size Preset")
                .font(.subheadline.weight(.bold))

            ForEach(CompressionPreset.allCases) { p in
                Button {
                    preset = p
                    if p != .custom {
                        customDPI = p.defaultDPI
                        customQuality = p.defaultJPEGQuality
                    }
                    result = nil
                } label: {
                    HStack {
                        Image(systemName: preset == p ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(preset == p ? .orange : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(p.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        preset == p ? Color.orange.opacity(0.14) : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func compressionResultCard(_ res: CompressionResult, sourceItem: PDFVaultItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Compression Complete", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                if res.reductionPercentage > 0 {
                    Text(String(format: "-%.1f%% Smaller", res.reductionPercentage))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.18), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Original Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(res.formattedOriginal)
                        .font(.title3.weight(.semibold))
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text("New Compressed Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(res.formattedCompressed)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.green)
                }
                Spacer()
            }

            Button {
                _ = vault.savePDFData(
                    res.data,
                    title: "\(sourceItem.title)_Compressed",
                    badgeTag: "Compressed"
                )
            } label: {
                Label("Save Compressed PDF to Vault", systemImage: "tray.and.arrow.down.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func runCompression() {
        guard let item = selectedItem else { return }
        isCompressing = true
        let url = vault.fileURL(for: item)
        let dpi = customDPI
        let qual = customQuality
        let gray = convertToGrayscale

        Task.detached(priority: .userInitiated) {
            let compressed = PDFCompressionEngine.compressPDF(
                at: url,
                dpi: dpi,
                jpegQuality: qual,
                convertToGrayscale: gray
            )
            await MainActor.run {
                self.result = compressed
                self.isCompressing = false
            }
        }
    }
}
#endif
