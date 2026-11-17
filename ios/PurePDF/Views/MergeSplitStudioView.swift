import SwiftUI
#if os(iOS)
import UIKit

enum PageToolkitMode: String, CaseIterable, Identifiable {
    case organizer = "Visual Page Organizer"
    case merger = "Merge Multiple PDFs"

    var id: String { rawValue }
}

struct MergeSplitStudioView: View {
    @EnvironmentObject var vault: PDFVaultStore
    @State private var mode: PageToolkitMode = .organizer

    // Visual Page Organizer state
    @State private var targetItemID: UUID?
    @State private var pageThumbnails: [PDFPageThumbnailItem] = []
    @State private var selectedPageIDs: Set<UUID> = []
    @State private var draggedPage: PDFPageThumbnailItem?

    // Multi-PDF Merger Queue state
    @State private var mergeQueue: [PDFVaultItem] = []
    @State private var mergedTitle: String = "Merged_Document"

    private var targetItem: PDFVaultItem? {
        vault.items.first { $0.id == targetItemID } ?? vault.items.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Toolkit Mode", selection: $mode) {
                    ForEach(PageToolkitMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                if mode == .organizer {
                    visualPageOrganizerSection
                } else {
                    multiPdfMergerSection
                }
            }
            .padding()
        }
        .navigationTitle("Page Studio & Merger")
        .onAppear {
            if targetItemID == nil {
                targetItemID = vault.items.first?.id
            }
            reloadThumbnails()
        }
        .onChange(of: targetItemID) { _ in
            reloadThumbnails()
        }
    }

    private var visualPageOrganizerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Select Document:")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Picker("Target PDF", selection: $targetItemID) {
                    ForEach(vault.items) { doc in
                        Text("\(doc.title) (\(doc.pageCount)p)").tag(Optional(doc.id))
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            Text("Tap pages to select for Split/Delete, tap ↻ to rotate 90°, or use arrows to reorder pages visually.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(Array(pageThumbnails.enumerated()), id: \.element.id) { idx, pageItem in
                    let isSelected = selectedPageIDs.contains(pageItem.id)
                    VStack(spacing: 8) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: pageItem.thumbnail)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 175)
                                .rotationEffect(.degrees(Double(pageItem.rotationDegrees)))
                                .padding(8)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isSelected ? Color.purple : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2.5 : 1)
                                )
                                .onTapGesture {
                                    if isSelected {
                                        selectedPageIDs.remove(pageItem.id)
                                    } else {
                                        selectedPageIDs.insert(pageItem.id)
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }

                            Button {
                                if isSelected {
                                    selectedPageIDs.remove(pageItem.id)
                                } else {
                                    selectedPageIDs.insert(pageItem.id)
                                }
                            } label: {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? .purple : .gray.opacity(0.45))
                                    .padding(6)
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                guard idx > 0 else { return }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    pageThumbnails.swapAt(idx, idx - 1)
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: "arrow.left.circle.fill")
                                    .font(.title3)
                            }
                            .disabled(idx == 0)

                            Text("P.\(idx + 1)")
                                .font(.caption.weight(.bold))

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    pageThumbnails[idx].rotationDegrees = (pageThumbnails[idx].rotationDegrees + 90) % 360
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: "rotate.right.fill")
                                    .font(.caption.weight(.bold))
                                    .padding(5)
                                    .background(Color.teal.opacity(0.15), in: Circle())
                            }

                            Button {
                                guard idx < pageThumbnails.count - 1 else { return }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    pageThumbnails.swapAt(idx, idx + 1)
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title3)
                            }
                            .disabled(idx >= pageThumbnails.count - 1)
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }
            }

            if let doc = targetItem {
                VStack(spacing: 10) {
                    Button {
                        if let rebuilt = PDFPageToolkit.rebuildPDF(
                            from: vault.fileURL(for: doc),
                            orderedPages: pageThumbnails
                        ) {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            _ = vault.savePDFData(rebuilt, title: "\(doc.title)_Organized", badgeTag: "Organized")
                        }
                    } label: {
                        Label("Save New Page Order & Rotations (\(pageThumbnails.count)p)", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.teal, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }

                    if !selectedPageIDs.isEmpty {
                        HStack(spacing: 10) {
                            Button {
                                let extractedPages = pageThumbnails.filter { selectedPageIDs.contains($0.id) }
                                if let splitData = PDFPageToolkit.rebuildPDF(
                                    from: vault.fileURL(for: doc),
                                    orderedPages: extractedPages
                                ) {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    _ = vault.savePDFData(splitData, title: "\(doc.title)_Split_\(extractedPages.count)p", badgeTag: "Split")
                                    selectedPageIDs.removeAll()
                                }
                            } label: {
                                Label("Extract Selected (\(selectedPageIDs.count)p)", systemImage: "doc.on.doc.fill")
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.purple, in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.white)
                            }

                            Button(role: .destructive) {
                                withAnimation {
                                    pageThumbnails.removeAll { selectedPageIDs.contains($0.id) }
                                    selectedPageIDs.removeAll()
                                }
                            } label: {
                                Label("Remove Selected", systemImage: "trash.fill")
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.red)
                            }
                            .disabled(selectedPageIDs.count >= pageThumbnails.count)
                        }
                    }
                }
            }
        }
    }

    private var multiPdfMergerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("1. Tap PDFs in Vault to Add to Merge Queue")
                .font(.subheadline.weight(.bold))

            ForEach(vault.items) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        mergeQueue.append(item)
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.purple)
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(item.pageCount)p • \(item.formattedSize)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            if !mergeQueue.isEmpty {
                Divider()
                HStack {
                    let totalPages = mergeQueue.reduce(0) { $0 + $1.pageCount }
                    Text("2. Merge Queue (\(mergeQueue.count) files • \(totalPages) total pages)")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Button("Clear", role: .destructive) {
                        mergeQueue.removeAll()
                    }
                    .font(.caption)
                }

                ForEach(Array(mergeQueue.enumerated()), id: \.offset) { idx, qItem in
                    HStack(spacing: 10) {
                        Text("#\(idx + 1)")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.purple)
                            .frame(width: 26)
                        Text(qItem.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            guard idx > 0 else { return }
                            withAnimation { mergeQueue.swapAt(idx, idx - 1) }
                        } label: {
                            Image(systemName: "arrow.up.circle")
                        }
                        .disabled(idx == 0)

                        Button {
                            guard idx < mergeQueue.count - 1 else { return }
                            withAnimation { mergeQueue.swapAt(idx, idx + 1) }
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .disabled(idx >= mergeQueue.count - 1)

                        Button(role: .destructive) {
                            mergeQueue.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }

                TextField("Merged PDF Name", text: $mergedTitle)
                    .textFieldStyle(.roundedBorder)

                Button {
                    let urls = mergeQueue.map { vault.fileURL(for: $0) }
                    if let data = PDFPageToolkit.mergePDFs(urls: urls) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        _ = vault.savePDFData(data, title: mergedTitle, badgeTag: "Merged")
                        mergeQueue.removeAll()
                    }
                } label: {
                    Label("Merge \(mergeQueue.count) PDFs Now", systemImage: "square.stack.3d.up.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(mergeQueue.count >= 2 ? Color.purple : Color.gray, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .disabled(mergeQueue.count < 2)
            }
        }
    }

    private func reloadThumbnails() {
        selectedPageIDs.removeAll()
        guard let item = targetItem else {
            pageThumbnails = []
            return
        }
        pageThumbnails = PDFPageToolkit.loadPageThumbnails(from: vault.fileURL(for: item))
    }
}
#endif
