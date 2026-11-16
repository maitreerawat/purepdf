# PurePDF — 100% Free, Zero-Watermark, On-Device iPhone Scanner, OCR, Signer & PDF Size Reducer

**PurePDF** is a native iOS (`Swift` + `SwiftUI`) document studio built to replace predatory $9.99/week subscription scanner and PDF utility apps with a **100% free, zero-ad, zero-watermark, 100% offline/on-device** experience.

Every byte of processing runs locally on the iPhone using native Apple hardware-accelerated frameworks (`VisionKit`, `Vision` Neural Engine, `PDFKit`, and `CoreGraphics`)—meaning **$0.00 in server bills, zero third-party API keys, and absolute document privacy**.

---

## Key Features

1. **Smart PDF Size Reducer (`PDFCompressionEngine.swift`)**
   - Shrinks bloated PDFs on-device to pass strict government, visa, university, and job portal limits.
   - Built-in presets: **Strict Portal (`<300 KB`)**, **Standard Upload (`<500 KB`)**, **Balanced Email (`<1.5 MB`)**, **High Quality (`200 DPI`)**, plus custom **DPI (`50–250 DPI`)** and **JPEG Quality (`15%–92%`)** sliders and an optional **Crisp Grayscale** bit-depth reducer.
   - Real-time **Before vs. After** byte size comparison and percentage saved badge.

2. **Watermark-Free Document Scanner (`DocumentScannerService.swift`)**
   - Uses Apple's native `VNDocumentCameraViewController` (`VisionKit`) for automatic perspective crop and edge detection, plus `PhotosPicker` import.
   - Includes **Magic Crisp B&W** (shadow removal & high-contrast enhancement), **Clean Grayscale**, and **Original Color** filters.
   - Exports multi-page PDFs with **zero watermarks**.

3. **Finger & Apple Pencil PDF Signer (`PDFSignerEngine.swift`)**
   - Draw smooth vector ink signatures in **Jet Black**, **Legal Blue**, or **Fountain Navy**.
   - Automatically saves your signature locally on-device for 1-tap reuse.
   - Position and scale your signature on any page, add an optional **Name/Title Stamp** and **Today's Date Stamp**, and flatten directly into a signed PDF.

4. **100% Offline Neural Engine OCR (`OCRService.swift`)**
   - Powered by Apple's on-device `VNRecognizeTextRequest` (`.accurate` recognition level with language correction).
   - Extracts copyable, selectable text from every page of any PDF with confidence scores and 1-tap **Copy All**.

5. **Merge, Rotate & Page Toolkit (`PDFPageToolkit.swift`)**
   - Combine multiple PDFs into a single document, rotate pages by $90^\circ$, or delete unwanted pages.

---

## Project Structure

```text
purepdf/
├── PurePDF.xcodeproj/                  # Native Xcode project
├── Package.swift                       # Swift Package manifest for VS Code / SourceKit-LSP
├── .vscode/                            # VS Code tasks & Swift extension config
└── PurePDF/
    ├── Info.plist                      # Local camera & photo permissions
    ├── PurePDFApp.swift                # @main SwiftUI app entry point
    ├── Models/
    │   └── PDFVaultItem.swift          # Local on-device PDF Vault & starter sample PDF generator
    ├── Services/
    │   ├── PDFCompressionEngine.swift  # On-device DPI & JPEG PDF Size Reducer
    │   ├── DocumentScannerService.swift# VisionKit camera wrapper & Magic B&W filter
    │   ├── OCRService.swift            # Vision Neural Engine offline OCR
    │   ├── PDFSignerEngine.swift       # Freehand signature renderer & PDF stamper
    │   └── PDFPageToolkit.swift        # Multi-PDF merge, page rotate & delete
    └── Views/
        ├── HomeView.swift              # Main TabView & Bento dashboard
        ├── ScannerStudioView.swift     # Camera & photo scanner UI
        ├── CompressorStudioView.swift  # PDF Size Reducer UI
        ├── SignerStudioView.swift      # Finger signature & PDF stamp UI
        ├── OCRStudioView.swift         # Offline OCR extraction UI
        ├── MergeSplitStudioView.swift  # Multi-PDF combiner & page tools UI
        └── PDFKitRepresentedView.swift # Native PDFView preview sheet
```

---

## How to Open in VS Code or Run on Your iPhone for $0

### Option 1: Edit & Build in VS Code
1. Open this folder (`purepdf`) in **VS Code** or **Antigravity**.
2. Press `Cmd + Shift + B` to run the configured build task, or run `open PurePDF.xcodeproj` in the terminal.

### Option 2: Run on iOS Simulator or Your Physical iPhone (Free Personal Team)
1. Open `PurePDF.xcodeproj` in **Xcode**.
2. In **Signing & Capabilities**, select your free **Personal Team** (your standard Apple ID—$0 cost, no paid developer membership required to install on your own iPhone).
3. Select an iPhone Simulator or your connected iPhone and press **`Cmd + R`**.
