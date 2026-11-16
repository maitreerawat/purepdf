# PurePDF — 100% Free, Zero-Watermark, On-Device Scanner, OCR, Signer & PDF Size Reducer

**PurePDF** is a 3-platform monorepo (**iOS**, **Android**, and **Web / Installable PWA**) built to replace predatory $9.99/week subscription scanner and PDF utility apps with a **100% free, zero-ad, zero-watermark, 100% on-device** experience.

Every byte of processing runs locally on the user's device—meaning **$0.00 in server bills forever, zero paid third-party APIs, and complete document privacy**.

---

## 3 Platforms Included in This Repository

```text
purepdf/
├── ios/        # 1. Native iPhone App (Swift + SwiftUI)
├── android/    # 2. Native Android App (Kotlin + Jetpack Compose)
├── web/        # 3. Universal Web App & Installable PWA (HTML5 + PDF.js + pdf-lib + Tesseract.js)
└── index.html  # Root GitHub Pages entry point -> ./web/index.html
```

| Platform | Path | Tech Stack ($0 Cost / 100% On-Device) |
|---|---|---|
| **1. iOS (iPhone & iPad)** | [`ios/`](./ios) | `Swift`, `SwiftUI`, `VisionKit` (`VNDocumentCameraViewController`), `Vision` (`VNRecognizeTextRequest` Neural Engine OCR), `PDFKit`, `CoreGraphics` |
| **2. Android** | [`android/`](./android) | `Kotlin`, `Jetpack Compose` (Material 3), `PdfRenderer` & `PdfDocument`, `ColorMatrix` B&W enhancer, bundled on-device `com.google.mlkit:text-recognition` (Zero Internet permission) |
| **3. Web & PWA** | [`web/`](./web) | `HTML5`, `Tailwind CSS`, `PDF.js` (Mozilla), `pdf-lib`, `Tesseract.js` WebAssembly OCR, offline Service Worker (`sw.js`) |

---

## 5 Core Features Across All 3 Versions

1. **Smart PDF Size Reducer**
   - Compresses PDFs on-device to pass strict government, visa, university, and job portal limits.
   - Built-in presets: **Strict Portal (`<300 KB`)**, **Standard Upload (`<500 KB`)**, **Balanced Email (`<1.5 MB`)**, **High Quality (`200 DPI`)**, plus custom **DPI** and **JPEG Quality** sliders and a **Crisp Grayscale** bit-depth reducer.
   - Live **Before vs. After** size comparison and exact percentage saved.

2. **Watermark-Free Document Scanner**
   - Camera capture & photo import with **Magic Crisp B&W** (shadow removal & high-contrast enhancement), **Clean Grayscale**, and **Original Color** filters.
   - Exports multi-page PDFs with **zero watermarks**.

3. **Finger / Stylus / Mouse PDF Signer & Date Filler**
   - Smooth signature drawing pad in **Legal Blue**, **Jet Black**, or **Fountain Navy**.
   - Adjustable placement, optional **Name/Title Stamp**, and **Today's Date Stamp**, flattened directly onto the PDF.

4. **100% Offline On-Device OCR**
   - Extracts selectable, copyable text from every page of any PDF with zero cloud calls.

5. **Multi-PDF Merger & Page Toolkit**
   - Combine multiple PDFs into a single document, rotate pages $90^\circ$, or delete pages.

---

## Quick Start

* **iOS (`ios/`):** Open `ios/PurePDF.xcodeproj` in **Xcode**, select your free Apple ID Personal Team or Simulator, and press `Cmd + R`.
* **Android (`android/`):** Open the `android/` folder in **Android Studio** and click **Run** on any Android device or emulator (`minSdk 26`).
* **Web (`web/`):** Open `web/index.html` in any browser, or enable **GitHub Pages** on the `main` branch to publish live at `https://maitreerawat.github.io/purepdf/`.
