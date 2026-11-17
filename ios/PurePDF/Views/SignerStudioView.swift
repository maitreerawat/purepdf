import SwiftUI
#if os(iOS)
import UIKit

struct SignerStudioView: View {
    @EnvironmentObject var vault: PDFVaultStore
    @State private var selectedItemID: UUID?
    @State private var strokes: [[CGPoint]] = []
    @State private var activeStroke: [CGPoint] = []
    @State private var inkColor: SignatureInkColor = .legalBlue
    @State private var targetPageIndex: Int = 0

    // Interactive normalized placement state on the live PDF page [0.0 ... 1.0]
    @State private var normalizedPosition: CGPoint = CGPoint(x: 0.42, y: 0.76)
    @State private var dragStartPosition: CGPoint? = nil
    @State private var signatureWidthRatio: CGFloat = 0.36
    @State private var pinchBaseWidthRatio: CGFloat? = nil
    @State private var rotationDegrees: Double = 0.0
    @State private var rotationBaseDegrees: Double? = nil

    @State private var customText: String = ""
    @State private var includeDateStamp: Bool = true
    @State private var activeSignatureImage: UIImage? = PDFSignerEngine.loadSavedSignatureImage()
    @State private var savedGallery: [UIImage] = PDFSignerEngine.loadSavedSignatureGallery()
    @State private var showPadDrawer: Bool = true

    private var selectedItem: PDFVaultItem? {
        vault.items.first { $0.id == selectedItemID } ?? vault.items.first
    }

    private var formattedStampLine: String {
        var parts: [String] = []
        let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }
        if includeDateStamp {
            let df = DateFormatter()
            df.dateStyle = .medium
            parts.append("Signed: \(df.string(from: Date()))")
        }
        return parts.joined(separator: "  •  ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    documentAndPageBar

                    liveInteractivePageSection

                    signaturePadSection

                    stampDetailsSection

                    Button {
                        applyAndSaveSignedPDF()
                    } label: {
                        Label("Stamp Signature & Save Signed PDF", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.indigo, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .disabled(selectedItem == nil)
                }
                .padding()
            }
            .navigationTitle("Interactive PDF Signer")
            .onAppear {
                if selectedItemID == nil {
                    selectedItemID = vault.items.first?.id
                }
                savedGallery = PDFSignerEngine.loadSavedSignatureGallery()
            }
        }
    }

    private var documentAndPageBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Select PDF to Sign", selection: $selectedItemID) {
                    ForEach(vault.items) { item in
                        Text("\(item.title) (\(item.pageCount)p)").tag(Optional(item.id))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedItemID) { _ in
                    targetPageIndex = 0
                }

                Spacer()

                if let item = selectedItem, item.pageCount > 1 {
                    HStack(spacing: 8) {
                        Button {
                            targetPageIndex = max(0, targetPageIndex - 1)
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.title3)
                        }
                        .disabled(targetPageIndex <= 0)

                        Text("Page \(targetPageIndex + 1)/\(item.pageCount)")
                            .font(.caption.weight(.bold))

                        Button {
                            targetPageIndex = min(item.pageCount - 1, targetPageIndex + 1)
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.title3)
                        }
                        .disabled(targetPageIndex >= item.pageCount - 1)
                    }
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var liveInteractivePageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Drag, Pinch & Rotate Directly on Page", systemImage: "hand.draw.fill")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Button("Reset Position") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        normalizedPosition = CGPoint(x: 0.42, y: 0.76)
                        signatureWidthRatio = 0.36
                        rotationDegrees = 0.0
                    }
                }
                .font(.caption.weight(.semibold))
            }

            if let item = selectedItem,
               let preview = PDFSignerEngine.renderPagePreview(
                   url: vault.fileURL(for: item),
                   pageIndex: min(targetPageIndex, max(0, item.pageCount - 1))
               ) {
                GeometryReader { geo in
                    let containerW = geo.size.width
                    let pageH = containerW / max(0.3, preview.pageAspect)
                    let centerX = normalizedPosition.x * containerW
                    let centerY = normalizedPosition.y * pageH
                    let boxW = containerW * signatureWidthRatio
                    let sigAspect: CGFloat = {
                        if let img = activeSignatureImage, img.size.width > 0 {
                            return img.size.height / img.size.width
                        }
                        return 0.42
                    }()
                    let boxH = max(38, boxW * sigAspect)

                    ZStack {
                        Image(uiImage: preview.image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: containerW, height: pageH)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

                        // Center snap guide lines when near 50%
                        if abs(normalizedPosition.x - 0.5) < 0.025 {
                            Path { path in
                                path.move(to: CGPoint(x: containerW * 0.5, y: 0))
                                path.addLine(to: CGPoint(x: containerW * 0.5, y: pageH))
                            }
                            .stroke(Color.indigo.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        }

                        // Draggable, Pinchable, Rotatable Signature + Stamp Overlay
                        ZStack(alignment: .bottomTrailing) {
                            VStack(spacing: 3) {
                                if let sigImg = activeSignatureImage {
                                    Image(uiImage: sigImg)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: boxW, height: boxH)
                                } else {
                                    Text("Draw or Pick Signature Below")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.indigo)
                                        .frame(width: boxW, height: boxH)
                                }

                                if !formattedStampLine.isEmpty {
                                    Text(formattedStampLine)
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.35))
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                            }
                            .padding(8)
                            .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.indigo, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                            )

                            // Corner Resize Handle
                            Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, .indigo)
                                .offset(x: 8, y: 8)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            let base = pinchBaseWidthRatio ?? signatureWidthRatio
                                            if pinchBaseWidthRatio == nil {
                                                pinchBaseWidthRatio = signatureWidthRatio
                                            }
                                            let deltaRatio = value.translation.width / max(1, containerW)
                                            signatureWidthRatio = min(0.72, max(0.15, base + deltaRatio))
                                        }
                                        .onEnded { _ in
                                            pinchBaseWidthRatio = nil
                                        }
                                )
                        }
                        .rotationEffect(.degrees(rotationDegrees))
                        .position(x: centerX, y: centerY)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if dragStartPosition == nil {
                                        dragStartPosition = normalizedPosition
                                    }
                                    guard let start = dragStartPosition else { return }
                                    let nx = min(0.90, max(0.10, start.x + value.translation.width / max(1, containerW)))
                                    let ny = min(0.92, max(0.08, start.y + value.translation.height / max(1, pageH)))
                                    normalizedPosition = CGPoint(x: nx, y: ny)
                                }
                                .onEnded { _ in
                                    dragStartPosition = nil
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                        )
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { scale in
                                    let base = pinchBaseWidthRatio ?? signatureWidthRatio
                                    if pinchBaseWidthRatio == nil {
                                        pinchBaseWidthRatio = signatureWidthRatio
                                    }
                                    signatureWidthRatio = min(0.72, max(0.15, base * scale))
                                }
                                .onEnded { _ in
                                    pinchBaseWidthRatio = nil
                                }
                        )
                        .simultaneousGesture(
                            RotationGesture()
                                .onChanged { angle in
                                    let base = rotationBaseDegrees ?? rotationDegrees
                                    if rotationBaseDegrees == nil {
                                        rotationBaseDegrees = rotationDegrees
                                    }
                                    rotationDegrees = base + angle.degrees
                                }
                                .onEnded { _ in
                                    rotationBaseDegrees = nil
                                }
                        )
                    }
                    .frame(width: containerW, height: pageH)
                }
                .aspectRatio(preview.pageAspect, contentMode: .fit)
            }
        }
    }

    private var signaturePadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Signature Pad & Saved Vault")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Button(showPadDrawer ? "Hide Pad" : "Draw New") {
                    withAnimation { showPadDrawer.toggle() }
                }
                .font(.caption.weight(.semibold))
            }

            if !savedGallery.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(savedGallery.enumerated()), id: \.offset) { idx, img in
                            Button {
                                activeSignatureImage = img
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 96, height: 44)
                                    .padding(6)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.indigo.opacity(0.45), lineWidth: 1.5)
                                    )
                            }
                            .contextMenu {
                                Button("Delete Saved Signature", role: .destructive) {
                                    PDFSignerEngine.deleteSavedSignature(at: idx)
                                    savedGallery = PDFSignerEngine.loadSavedSignatureGallery()
                                }
                            }
                        }
                    }
                }
            }

            if showPadDrawer {
                Picker("Ink Color", selection: $inkColor) {
                    ForEach(SignatureInkColor.allCases) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .pickerStyle(.segmented)

                GeometryReader { geo in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white)
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.indigo.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6]))

                        Path { path in
                            let yLine = geo.size.height * 0.74
                            path.move(to: CGPoint(x: 24, y: yLine))
                            path.addLine(to: CGPoint(x: geo.size.width - 24, y: yLine))
                        }
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)

                        if strokes.isEmpty && activeStroke.isEmpty {
                            Text("Draw your signature here with finger or Apple Pencil")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }

                        Canvas { context, _ in
                            var all = strokes
                            if !activeStroke.isEmpty { all.append(activeStroke) }
                            for s in all where s.count > 1 {
                                var p = Path()
                                p.move(to: s[0])
                                for pt in s.dropFirst() { p.addLine(to: pt) }
                                context.stroke(p, with: .color(Color(inkColor.uiColor)), lineWidth: 3.2)
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { val in
                                    activeStroke.append(val.location)
                                }
                                .onEnded { _ in
                                    strokes.append(activeStroke)
                                    activeStroke.removeAll()
                                    if let rendered = PDFSignerEngine.renderSignatureImage(
                                        strokes: strokes,
                                        canvasSize: geo.size,
                                        inkColor: inkColor.uiColor
                                    ) {
                                        activeSignatureImage = rendered
                                        PDFSignerEngine.saveSignatureImage(rendered)
                                        savedGallery = PDFSignerEngine.loadSavedSignatureGallery()
                                    }
                                }
                        )
                    }
                }
                .frame(height: 140)

                HStack {
                    Button("Clear Drawing Pad", role: .destructive) {
                        strokes.removeAll()
                        activeStroke.removeAll()
                    }
                    .font(.caption.weight(.semibold))
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var stampDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stamp Options & Fine Rotation")
                .font(.subheadline.weight(.bold))

            HStack {
                Text("Angle: \(Int(rotationDegrees))°")
                    .font(.caption.weight(.semibold))
                    .frame(width: 75, alignment: .leading)
                Slider(value: $rotationDegrees, in: -45...45, step: 1)
                Button("0°") { rotationDegrees = 0 }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
            }

            TextField("Optional Name / Title Stamp (e.g. Maitree Rawat)", text: $customText)
                .textFieldStyle(.roundedBorder)

            Toggle("Include Today's Date Stamp", isOn: $includeDateStamp)
                .font(.subheadline)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func applyAndSaveSignedPDF() {
        guard let item = selectedItem else { return }
        guard let signedData = PDFSignerEngine.stampSignature(
            onPDF: vault.fileURL(for: item),
            targetPageIndex: min(targetPageIndex, max(0, item.pageCount - 1)),
            signatureImage: activeSignatureImage,
            normalizedPosition: normalizedPosition,
            signatureWidthRatio: signatureWidthRatio,
            rotationDegrees: rotationDegrees,
            customStampText: customText,
            includeDateStamp: includeDateStamp
        ) else { return }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        _ = vault.savePDFData(signedData, title: "\(item.title)_Signed", badgeTag: "Signed")
    }
}
#endif
