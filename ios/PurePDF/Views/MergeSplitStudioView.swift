import SwiftUI

#if os(iOS)
struct MergeSplitStudioView: View {
    @EnvironmentObject var vault: PDFVaultStore
    @State private var selectedIDs: Set<UUID> = []
    @State private var mergedTitle: String = "Merged_Document"
    @State private var targetItemID: UUID?
    @State private var targetPageNumber: Int = 1

    private var targetItem: PDFVaultItem? {
        vault.items.first { $0.id == targetItemID } ?? vault.items.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Merge Multiple PDFs into One")
                        .font(.headline)
                    Text("Tap 2 or more PDFs below to combine them in order with zero watermarks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(vault.items) { item in
                        let isSelected = selectedIDs.contains(item.id)
                        Button {
                            if isSelected {
                                selectedIDs.remove(item.id)
                            } else {
                                selectedIDs.insert(item.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? .purple : .secondary)
                                Text(item.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(item.pageCount)p • \(item.formattedSize)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(
                                isSelected ? Color.purple.opacity(0.14) : Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("Merged PDF Name", text: $mergedTitle)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        let chosenURLs = vault.items
                            .filter { selectedIDs.contains($0.id) }
                            .map { vault.fileURL(for: $0) }
                        if let data = PDFPageToolkit.mergePDFs(urls: chosenURLs) {
                            _ = vault.savePDFData(data, title: mergedTitle, badgeTag: "Merged")
                            selectedIDs.removeAll()
                        }
                    } label: {
                        Label("Merge Selected PDFs (\(selectedIDs.count))", systemImage: "square.stack.3d.up.fill")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(selectedIDs.count >= 2 ? Color.purple : Color.gray, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .disabled(selectedIDs.count < 2)
                }

                Divider()

                if let item = targetItem {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Rotate or Remove Page")
                            .font(.headline)

                        Picker("Target PDF", selection: $targetItemID) {
                            ForEach(vault.items) { doc in
                                Text("\(doc.title) (\(doc.pageCount)p)").tag(Optional(doc.id))
                            }
                        }
                        .pickerStyle(.menu)

                        Stepper("Page Number: \(targetPageNumber) of \(item.pageCount)", value: $targetPageNumber, in: 1...max(1, item.pageCount))

                        HStack(spacing: 12) {
                            Button {
                                if let rotated = PDFPageToolkit.rotatePage(
                                    in: vault.fileURL(for: item),
                                    pageIndex: targetPageNumber - 1
                                ) {
                                    _ = vault.savePDFData(rotated, title: "\(item.title)_Rotated", badgeTag: "Rotated")
                                }
                            } label: {
                                Label("Rotate 90°", systemImage: "rotate.right.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.teal, in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.white)
                            }

                            Button(role: .destructive) {
                                if let trimmed = PDFPageToolkit.deletePage(
                                    in: vault.fileURL(for: item),
                                    pageIndex: targetPageNumber - 1
                                ) {
                                    _ = vault.savePDFData(trimmed, title: "\(item.title)_Trimmed", badgeTag: "Split")
                                }
                            } label: {
                                Label("Delete Page", systemImage: "trash.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.red)
                            }
                            .disabled(item.pageCount <= 1)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Merge & Page Toolkit")
        .onAppear {
            if targetItemID == nil {
                targetItemID = vault.items.first?.id
            }
        }
    }
}
#endif
