import SwiftUI

#if os(iOS)
struct SignerStudioView: View {
    @EnvironmentObject var vault: PDFVaultStore
    @State private var selectedItemID: UUID?
    @State private var strokes: [[CGPoint]] = []
    @State private var activeStroke: [CGPoint] = []
    @State private var inkColor: SignatureInkColor = .legalBlue
    @State private var targetPageIndex: Int = 0
    @State private var normalizedX: Double = 0.38
    @State private var normalizedY: Double = 0.78
    @State private var signatureWidthRatio: Double = 0.34
    @State private var customText: String = ""
    @State private var includeDateStamp: Bool = true
    @State private var savedSignaturePreview: UIImage? = PDFSignerEngine.loadSavedSignatureImage()

    private var selectedItem: PDFVaultItem? {
        vault.items.first { $0.id == selectedItemID } ?? vault.items.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Select PDF to Sign", selection: $selectedItemID) {
                        ForEach(vault.items) { item in
                            Text("\(item.title) (\(item.pageCount)p)").tag(Optional(item.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                    signatureCanvasSection

                    placementControlsSection

                    Button {
                        applyAndSaveSignedPDF()
                    } label: {
                        Label("Stamp Signature & Save Signed PDF", systemImage: "signature")
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
            .navigationTitle("PDF Signer & Filler")
            .onAppear {
                if selectedItemID == nil {
                    selectedItemID = vault.items.first?.id
                }
            }
        }
    }

    private var signatureCanvasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("1. Draw Your Signature")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Button("Clear Pad", role: .destructive) {
                    strokes.removeAll()
                    activeStroke.removeAll()
                }
                .font(.caption)
            }

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
                        Text("Sign here with your finger or Apple Pencil")
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
                                    PDFSignerEngine.saveSignatureImage(rendered)
                                    savedSignaturePreview = rendered
                                }
                            }
                    )
                }
            }
            .frame(height: 155)
        }
    }

    private var placementControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2. Placement & Optional Text / Date Stamp")
                .font(.subheadline.weight(.bold))

            if let item = selectedItem, item.pageCount > 1 {
                Stepper("Target Page: \(targetPageIndex + 1) of \(item.pageCount)", value: $targetPageIndex, in: 0...(item.pageCount - 1))
                    .font(.subheadline)
            }

            HStack {
                Text("Horizontal Position: \(Int(normalizedX * 100))%")
                    .font(.caption)
                Slider(value: $normalizedX, in: 0.15...0.85)
            }

            HStack {
                Text("Vertical Position: \(Int(normalizedY * 100))%")
                    .font(.caption)
                Slider(value: $normalizedY, in: 0.10...0.90)
            }

            HStack {
                Text("Signature Size: \(Int(signatureWidthRatio * 100))%")
                    .font(.caption)
                Slider(value: $signatureWidthRatio, in: 0.18...0.60)
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
        let sigImg: UIImage?
        if !strokes.isEmpty {
            sigImg = PDFSignerEngine.renderSignatureImage(
                strokes: strokes,
                canvasSize: CGSize(width: 340, height: 155),
                inkColor: inkColor.uiColor
            )
        } else {
            sigImg = savedSignaturePreview
        }

        guard let signedData = PDFSignerEngine.stampSignature(
            onPDF: vault.fileURL(for: item),
            targetPageIndex: min(targetPageIndex, max(0, item.pageCount - 1)),
            signatureImage: sigImg,
            normalizedPosition: CGPoint(x: normalizedX, y: normalizedY),
            signatureWidthRatio: CGFloat(signatureWidthRatio),
            customStampText: customText,
            includeDateStamp: includeDateStamp
        ) else { return }

        _ = vault.savePDFData(signedData, title: "\(item.title)_Signed", badgeTag: "Signed")
    }
}
#endif
