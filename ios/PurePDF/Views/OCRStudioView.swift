import SwiftUI
#if os(iOS)
import UIKit

struct OCRStudioView: View {
    @EnvironmentObject var vault: PDFVaultStore
    @State private var selectedItemID: UUID?
    @State private var pagesOutput: [OCRPageOutput] = []
    @State private var isRunningOCR = false
    @State private var copiedBanner = false
    @State private var searchQuery: String = ""

    private var selectedItem: PDFVaultItem? {
        vault.items.first { $0.id == selectedItemID } ?? vault.items.first
    }

    private var filteredPages: [OCRPageOutput] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return pagesOutput }
        return pagesOutput.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    private var combinedText: String {
        pagesOutput
            .map { "--- Page \($0.pageNumber) ---\n\($0.text)" }
            .joined(separator: "\n\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Select PDF for On-Device OCR", selection: $selectedItemID) {
                        ForEach(vault.items) { item in
                            Text("\(item.title) (\(item.pageCount)p)").tag(Optional(item.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                    Button {
                        runOfflineOCR()
                    } label: {
                        HStack {
                            if isRunningOCR {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "text.viewfinder")
                            }
                            Text(isRunningOCR ? "Running Apple Vision Neural Engine..." : "Extract Text (100% Offline OCR)")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                    }
                    .disabled(selectedItem == nil || isRunningOCR)

                    if !pagesOutput.isEmpty {
                        HStack(spacing: 10) {
                            Button {
                                UIPasteboard.general.string = combinedText
                                copiedBanner = true
                            } label: {
                                Label(copiedBanner ? "Copied All!" : "Copy All Text", systemImage: "doc.on.doc.fill")
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)

                            if let item = selectedItem {
                                Button {
                                    if let searchableData = OCRService.buildSearchablePDF(
                                        from: vault.fileURL(for: item),
                                        ocrPages: pagesOutput
                                    ) {
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                        _ = vault.savePDFData(
                                            searchableData,
                                            title: "\(item.title)_SearchableOCR",
                                            badgeTag: "Searchable OCR"
                                        )
                                    }
                                } label: {
                                    Label("Save Searchable PDF", systemImage: "doc.text.magnifyingglass")
                                        .font(.caption.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        TextField("Search inside extracted text...", text: $searchQuery)
                            .textFieldStyle(.roundedBorder)

                        ForEach(filteredPages) { page in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Page \(page.pageNumber)")
                                        .font(.subheadline.weight(.bold))
                                    Spacer()
                                    Text(String(format: "Confidence: %.0f%%", page.averageConfidence * 100))
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.blue.opacity(0.14), in: Capsule())
                                }
                                Text(page.text)
                                    .font(.system(.footnote, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(14)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Offline Neural OCR")
            .onAppear {
                if selectedItemID == nil {
                    selectedItemID = vault.items.first?.id
                }
            }
        }
    }

    private func runOfflineOCR() {
        guard let item = selectedItem else { return }
        isRunningOCR = true
        copiedBanner = false
        let url = vault.fileURL(for: item)

        Task {
            let extracted = await OCRService.extractText(fromPDF: url)
            await MainActor.run {
                self.pagesOutput = extracted
                self.isRunningOCR = false
            }
        }
    }
}
#endif
