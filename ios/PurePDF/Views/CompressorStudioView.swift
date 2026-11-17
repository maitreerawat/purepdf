import SwiftUI
#if os(iOS)
import UIKit

struct CompressorStudioView: View {
    @EnvironmentObject var vault: PDFVaultStore
    @State private var selectedItemID: UUID?
    @State private var preset: CompressionPreset = .autoTargetKB
    @State private var targetKB: Int = 450
    @State private var customDPI: Double = 110
    @State private var customQuality: Double = 0.48
    @State private var convertToGrayscale: Bool = false
    @State private var result: CompressionResult?
    @State private var isCompressing: Bool = false

    private let quickTargetOptions = [200, 300, 450, 750, 1000]

    private var selectedItem: PDFVaultItem? {
        vault.items.first { $0.id == selectedItemID } ?? vault.items.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    documentPickerSection

                    presetSection

                    if preset == .autoTargetKB {
                        autoTargetKBControlCard
                    } else {
                        manualSliderControlCard
                    }

                    Button {
                        runCompression()
                    } label: {
                        HStack {
                            if isCompressing {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: preset == .autoTargetKB ? "wand.and.stars" : "arrow.down.right.and.arrow.up.left")
                            }
                            Text(
                                isCompressing
                                    ? "Solving Optimal DPI & Quality..."
                                    : (preset == .autoTargetKB ? "Auto-Fit Under \(targetKB) KB Now" : "Reduce PDF File Size Now")
                            )
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
            Text("2. Choose Compression Mode")
                .font(.subheadline.weight(.bold))

            ForEach(CompressionPreset.allCases) { p in
                Button {
                    preset = p
                    if p != .custom && p != .autoTargetKB {
                        customDPI = p.defaultDPI
                        customQuality = p.defaultJPEGQuality
                    }
                    result = nil
                } label: {
                    HStack {
                        Image(systemName: preset == p ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(preset == p ? .orange : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(p.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if p == .autoTargetKB {
                                    Text("AUTO")
                                        .font(.system(size: 9, weight: .black))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                            }
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

    private var autoTargetKBControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Target Maximum Size: \(targetKB) KB", systemImage: "scalemass.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickTargetOptions, id: \.self) { kb in
                        Button {
                            targetKB = kb
                            result = nil
                        } label: {
                            Text("<\(kb) KB")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    targetKB == kb ? Color.orange : Color(.tertiarySystemBackground),
                                    in: Capsule()
                                )
                                .foregroundStyle(targetKB == kb ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Stepper("Fine-Tune Ceiling: \(targetKB) KB", value: $targetKB, in: 50...5000, step: 50)
                .font(.caption.weight(.semibold))
                .onChange(of: targetKB) { _ in result = nil }

            Toggle("Convert to Crisp Grayscale (Extra 25% Smaller)", isOn: $convertToGrayscale)
                .font(.subheadline)
                .onChange(of: convertToGrayscale) { _ in result = nil }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var manualSliderControlCard: some View {
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
    }

    private func compressionResultCard(_ res: CompressionResult, sourceItem: PDFVaultItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    res.metTargetKB ? "Target Achieved!" : "Maximum Possible Reduction",
                    systemImage: "checkmark.seal.fill"
                )
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

            Text("Selected Optimal Settings: \(res.appliedDPI) DPI • \(res.appliedQualityPercent)% JPEG Quality")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

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
                UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        let mode = preset
        let ceilingKB = targetKB
        let dpi = customDPI
        let qual = customQuality
        let gray = convertToGrayscale

        Task.detached(priority: .userInitiated) {
            let compressed: CompressionResult?
            if mode == .autoTargetKB {
                compressed = PDFCompressionEngine.autoSolveTargetKB(
                    at: url,
                    targetKB: ceilingKB,
                    convertToGrayscale: gray
                )
            } else {
                compressed = PDFCompressionEngine.compressPDF(
                    at: url,
                    dpi: dpi,
                    jpegQuality: qual,
                    convertToGrayscale: gray
                )
            }
            await MainActor.run {
                self.result = compressed
                self.isCompressing = false
            }
        }
    }
}
#endif
