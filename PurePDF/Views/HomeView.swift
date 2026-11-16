import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
enum StudioTab: Hashable {
    case dashboard
    case scanner
    case compressor
    case signer
    case ocr
    case merge
}

struct HomeView: View {
    @EnvironmentObject var vault: PDFVaultStore
    @State private var selectedTab: StudioTab = .dashboard
    @State private var showingFileImporter = false
    @State private var previewItem: PDFVaultItem?

    var body: some View {
        TabView(selection: $selectedTab) {
            dashboardTab
                .tabItem {
                    Label("Studio", systemImage: "sparkles.rectangle.stack.fill")
                }
                .tag(StudioTab.dashboard)

            ScannerStudioView()
                .tabItem {
                    Label("Scan", systemImage: "doc.viewfinder")
                }
                .tag(StudioTab.scanner)

            CompressorStudioView()
                .tabItem {
                    Label("Reduce Size", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .tag(StudioTab.compressor)

            SignerStudioView()
                .tabItem {
                    Label("Sign PDF", systemImage: "signature")
                }
                .tag(StudioTab.signer)

            OCRStudioView()
                .tabItem {
                    Label("OCR Text", systemImage: "text.viewfinder")
                }
                .tag(StudioTab.ocr)
        }
        .tint(Color(red: 0.06, green: 0.52, blue: 0.46))
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    vault.importExternalPDF(from: url)
                }
            }
        }
        .sheet(item: $previewItem) { item in
            PDFPreviewSheet(item: item)
                .environmentObject(vault)
        }
    }

    private var dashboardTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    privacyHeroCard

                    if let banner = vault.statusBanner {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text(banner)
                                .font(.footnote.weight(.medium))
                            Spacer()
                            Button {
                                vault.statusBanner = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }

                    Text("All-in-One Free Tools")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        toolCard(
                            title: "Document Scanner",
                            subtitle: "Auto-crop & crisp B&W, zero watermark",
                            icon: "doc.viewfinder.fill",
                            color: .teal
                        ) {
                            selectedTab = .scanner
                        }

                        toolCard(
                            title: "PDF Size Reducer",
                            subtitle: "Shrink to <300KB or <500KB for portals",
                            icon: "arrow.down.right.and.arrow.up.left",
                            color: .orange
                        ) {
                            selectedTab = .compressor
                        }

                        toolCard(
                            title: "Finger PDF Signer",
                            subtitle: "Draw ink signature & stamp date",
                            icon: "signature",
                            color: .indigo
                        ) {
                            selectedTab = .signer
                        }

                        toolCard(
                            title: "On-Device OCR",
                            subtitle: "Extract copyable text offline",
                            icon: "text.viewfinder",
                            color: .blue
                        ) {
                            selectedTab = .ocr
                        }
                    }

                    NavigationLink {
                        MergeSplitStudioView()
                            .environmentObject(vault)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 46, height: 46)
                                .background(Color.purple, in: RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Merge PDFs & Page Toolkit")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Combine multiple PDFs, rotate 90°, or delete pages")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    }

                    vaultSection
                }
                .padding()
            }
            .navigationTitle("PurePDF")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Import PDF", systemImage: "folder.badge.plus")
                    }
                }
            }
        }
    }

    private var privacyHeroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("100% Free • Zero Ads • Zero Cloud", systemImage: "lock.shield.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.18), in: Capsule())
                Spacer()
            }
            Text("Your private documents never leave your iPhone.")
                .font(.title3.weight(.bold))
            Text("Powered natively by Apple VisionKit, PDFKit & Neural Engine OCR—zero watermarks, zero subscriptions.")
                .font(.caption)
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.42, blue: 0.38),
                    Color(red: 0.09, green: 0.24, blue: 0.42)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    private func toolCard(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(color, in: RoundedRectangle(cornerRadius: 12))

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var vaultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("On-Device PDF Vault (\(vault.items.count))")
                    .font(.headline)
                Spacer()
                Button("Import PDF") {
                    showingFileImporter = true
                }
                .font(.caption.weight(.semibold))
            }

            ForEach(vault.items) { item in
                HStack(spacing: 12) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.title2)
                        .foregroundStyle(.teal)
                        .frame(width: 42, height: 42)
                        .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(item.badgeTag)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.teal.opacity(0.15), in: Capsule())
                            Text("\(item.pageCount)p • \(item.formattedSize)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        previewItem = item
                    } label: {
                        Image(systemName: "eye.fill")
                            .padding(8)
                            .background(Color(.tertiarySystemBackground), in: Circle())
                    }

                    ShareLink(item: vault.fileURL(for: item)) {
                        Image(systemName: "square.and.arrow.up")
                            .padding(8)
                            .background(Color(.tertiarySystemBackground), in: Circle())
                    }

                    Button(role: .destructive) {
                        vault.delete(item)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
#endif
