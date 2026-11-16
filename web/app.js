/**
 * PurePDF Universal Web & PWA Studio
 * 100% Client-Side PDF Scanner, Size Reducer, Signer, Merger & Offline OCR.
 * Zero backend, zero cloud uploads, $0.00 forever.
 */

if (window.pdfjsLib) {
  window.pdfjsLib.GlobalWorkerOptions.workerSrc =
    "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js";
}

const state = {
  vault: [], // [{ id, title, bytes: Uint8Array, pageCount, tag }]
  selectedForMerge: new Set(),
  scannedImages: [], // [HTMLImageElement]
  lastCompressed: null, // { bytes, title }
};

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  const kb = bytes / 1024;
  if (kb < 1024) return `${kb.toFixed(1)} KB`;
  return `${(kb / 1024).toFixed(2)} MB`;
}

function showBanner(msg) {
  const banner = document.getElementById("status-banner");
  const text = document.getElementById("status-banner-text");
  text.textContent = msg;
  banner.classList.remove("hidden");
}

function downloadPdfBytes(bytes, filename) {
  const cleanName = filename.endsWith(".pdf") ? filename : `${filename}.pdf`;
  const blob = new Blob([bytes], { type: "application/pdf" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = cleanName;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

async function addPdfToVault(bytes, title, tag = "Document") {
  const uint8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let pageCount = 1;
  try {
    const pdfDoc = await PDFLib.PDFDocument.load(uint8);
    pageCount = pdfDoc.getPageCount();
  } catch (_) {}

  const item = {
    id: `pdf_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
    title: title.replace(/\.pdf$/i, ""),
    bytes: uint8,
    pageCount,
    tag,
  };
  state.vault.unshift(item);
  renderVaultAndSelects();
  return item;
}

function renderVaultAndSelects() {
  document.getElementById("vault-count").textContent = String(state.vault.length);
  const listEl = document.getElementById("vault-list");
  listEl.innerHTML = "";

  state.vault.forEach((item) => {
    const checked = state.selectedForMerge.has(item.id);
    const row = document.createElement("div");
    row.className =
      "flex flex-wrap items-center justify-between gap-3 p-3.5 rounded-xl bg-slate-950/80 border border-slate-800";
    row.innerHTML = `
      <div class="flex items-center gap-3">
        <input type="checkbox" data-merge-id="${item.id}" ${checked ? "checked" : ""} class="w-4 h-4 accent-purple-500 rounded cursor-pointer" />
        <div>
          <div class="font-semibold text-sm text-white">${item.title}</div>
          <div class="text-xs text-slate-400">
            <span class="px-2 py-0.5 rounded-full bg-teal-500/15 text-teal-300 font-semibold mr-1.5">${item.tag}</span>
            ${item.pageCount} page(s) • ${formatBytes(item.bytes.byteLength)}
          </div>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <button data-dl-id="${item.id}" class="px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-xs font-semibold text-teal-300">Download</button>
        <button data-del-id="${item.id}" class="px-2.5 py-1.5 rounded-lg bg-slate-800 hover:bg-rose-950 text-xs font-semibold text-rose-400">Delete</button>
      </div>
    `;
    listEl.appendChild(row);
  });

  // Wire checkboxes & buttons
  listEl.querySelectorAll("[data-merge-id]").forEach((cb) => {
    cb.addEventListener("change", (e) => {
      const id = e.target.getAttribute("data-merge-id");
      if (e.target.checked) state.selectedForMerge.add(id);
      else state.selectedForMerge.delete(id);
      updateMergeButton();
    });
  });

  listEl.querySelectorAll("[data-dl-id]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const item = state.vault.find((v) => v.id === btn.getAttribute("data-dl-id"));
      if (item) downloadPdfBytes(item.bytes, item.title);
    });
  });

  listEl.querySelectorAll("[data-del-id]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const id = btn.getAttribute("data-del-id");
      state.vault = state.vault.filter((v) => v.id !== id);
      state.selectedForMerge.delete(id);
      renderVaultAndSelects();
    });
  });

  updateMergeButton();

  // Populate select dropdowns across Compressor, Signer, and OCR tabs
  ["compress-pdf-select", "sign-pdf-select", "ocr-pdf-select"].forEach((selId) => {
    const sel = document.getElementById(selId);
    const prev = sel.value;
    sel.innerHTML = "";
    state.vault.forEach((item) => {
      const opt = document.createElement("option");
      opt.value = item.id;
      opt.textContent = `${item.title} (${item.pageCount}p • ${formatBytes(item.bytes.byteLength)})`;
      sel.appendChild(opt);
    });
    if (prev && state.vault.some((v) => v.id === prev)) sel.value = prev;
  });
}

function updateMergeButton() {
  const btn = document.getElementById("btn-merge-selected");
  const count = state.selectedForMerge.size;
  btn.textContent = `Merge Selected PDFs (${count})`;
  btn.disabled = count < 2;
}

// Create a rich 2-page starter Sample PDF in browser memory on first load
async function createStarterSamplePdf() {
  const pdfDoc = await PDFLib.PDFDocument.create();
  const fontBold = await pdfDoc.embedFont(PDFLib.StandardFonts.HelveticaBold);
  const fontReg = await pdfDoc.embedFont(PDFLib.StandardFonts.Helvetica);

  // Create a synthetic high-resolution canvas image so PDF Size Reducer has real bitmap pixels to compress
  const bannerCanvas = document.createElement("canvas");
  bannerCanvas.width = 900;
  bannerCanvas.height = 340;
  const bCtx = bannerCanvas.getContext("2d");
  const grad = bCtx.createLinearGradient(0, 0, 900, 340);
  grad.addColorStop(0, "#0f766e");
  grad.addColorStop(0.5, "#1e3a8a");
  grad.addColorStop(1, "#4338ca");
  bCtx.fillStyle = grad;
  bCtx.fillRect(0, 0, 900, 340);
  bCtx.fillStyle = "#ffffff";
  bCtx.font = "bold 30px sans-serif";
  bCtx.fillText("High-Res Embedded Figure (Test PDF Size Reducer!)", 45, 175);
  const pngDataUrl = bannerCanvas.toDataURL("image/png");
  const embeddedImg = await pdfDoc.embedPng(pngDataUrl);

  for (let p = 1; p <= 2; p++) {
    const page = pdfDoc.addPage([612, 792]);
    page.drawRectangle({
      x: 36,
      y: 690,
      width: 540,
      height: 64,
      color: PDFLib.rgb(0.05, 0.42, 0.38),
    });
    page.drawText(`PurePDF Sample Agreement & OCR Benchmark (Page ${p} of 2)`, {
      x: 52,
      y: 715,
      size: 16,
      font: fontBold,
      color: PDFLib.rgb(1, 1, 1),
    });

    const lines = [
      "100% Free, Zero-Watermark, Zero-Ad, On-Device PDF Studio (Web + iOS + Android).",
      "",
      "Every feature runs 100% locally inside your device memory:",
      "1. Smart PDF Size Reducer: Shrinks PDFs to <300 KB or <500 KB for strict web portals.",
      "2. Watermark-Free Scanner: Magic Crisp B&W shadow removal and clean multi-page export.",
      "3. Finger / Stylus Signer: Draw ink signatures, add date stamps, and flatten onto any page.",
      "4. Offline OCR: Extract selectable, copyable text without uploading files to any server.",
      "",
      "Authorized Signature: ___________________________     Date: _______________",
    ];
    let yCursor = 645;
    lines.forEach((line) => {
      page.drawText(line, {
        x: 48,
        y: yCursor,
        size: 11.5,
        font: fontReg,
        color: PDFLib.rgb(0.18, 0.2, 0.24),
      });
      yCursor -= 22;
    });

    page.drawImage(embeddedImg, {
      x: 48,
      y: 210,
      width: 516,
      height: 195,
    });
  }

  const pdfBytes = await pdfDoc.save();
  await addPdfToVault(pdfBytes, "Welcome_PurePDF_Sample", "Sample");
}

// Tab switching
document.querySelectorAll(".tab-btn").forEach((btn) => {
  btn.addEventListener("click", () => {
    const target = btn.getAttribute("data-tab");
    document.querySelectorAll(".tab-btn").forEach((b) => {
      b.className =
        "tab-btn text-slate-300 hover:text-white font-semibold py-2.5 px-3 rounded-xl text-xs transition";
    });
    btn.className =
      "tab-btn bg-teal-600 text-white font-semibold py-2.5 px-3 rounded-xl text-xs transition";

    document.querySelectorAll(".tab-panel").forEach((panel) => panel.classList.add("hidden"));
    document.getElementById(`tab-${target}`).classList.remove("hidden");
  });
});

// Global PDF file import
document.getElementById("global-pdf-input").addEventListener("change", async (e) => {
  const files = Array.from(e.target.files || []);
  for (const file of files) {
    const buf = await file.arrayBuffer();
    await addPdfToVault(new Uint8Array(buf), file.name, "Imported");
  }
  if (files.length > 0) {
    showBanner(`Imported ${files.length} PDF(s) into local on-device vault.`);
  }
  e.target.value = "";
});

// Multi-PDF Merge
document.getElementById("btn-merge-selected").addEventListener("click", async () => {
  const selectedItems = state.vault.filter((v) => state.selectedForMerge.has(v.id));
  if (selectedItems.length < 2) return;

  const mergedPdf = await PDFLib.PDFDocument.create();
  for (const item of selectedItems) {
    const srcDoc = await PDFLib.PDFDocument.load(item.bytes);
    const copiedPages = await mergedPdf.copyPages(srcDoc, srcDoc.getPageIndices());
    copiedPages.forEach((p) => mergedPdf.addPage(p));
  }
  const mergedBytes = await mergedPdf.save();
  state.selectedForMerge.clear();
  const created = await addPdfToVault(mergedBytes, "Merged_Document", "Merged");
  showBanner(`Merged ${selectedItems.length} PDFs into "${created.title}" (${formatBytes(mergedBytes.byteLength)})`);
});

// ================= SCANNER ENGINE =================
function applyScanFilterToCanvas(img, filterMode) {
  const canvas = document.createElement("canvas");
  canvas.width = img.naturalWidth || img.width;
  canvas.height = img.naturalHeight || img.height;
  const ctx = canvas.getContext("2d");
  ctx.drawImage(img, 0, 0);

  if (filterMode === "color") return canvas;

  const imgData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const d = imgData.data;
  const contrast = filterMode === "bw" ? 1.65 : 1.2;
  const bias = filterMode === "bw" ? 18 : 5;

  for (let i = 0; i < d.length; i += 4) {
    const lum = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
    const adj = Math.min(255, Math.max(0, (lum - 128) * contrast + 128 + bias));
    d[i] = d[i + 1] = d[i + 2] = adj;
  }
  ctx.putImageData(imgData, 0, 0);
  return canvas;
}

function renderScannerPreviews() {
  const container = document.getElementById("scan-pages-preview");
  const filterMode = document.getElementById("scan-filter-select").value;
  container.innerHTML = "";

  state.scannedImages.forEach((img, idx) => {
    const filteredCanvas = applyScanFilterToCanvas(img, filterMode);
    const card = document.createElement("div");
    card.className = "bg-slate-950 border border-slate-800 rounded-xl p-2 text-center space-y-1.5";
    const previewImg = document.createElement("img");
    previewImg.src = filteredCanvas.toDataURL("image/jpeg", 0.85);
    previewImg.className = "w-full h-44 object-contain rounded-lg bg-white";
    const label = document.createElement("div");
    label.className = "text-xs font-semibold text-slate-300";
    label.textContent = `Page ${idx + 1}`;
    card.appendChild(previewImg);
    card.appendChild(label);
    container.appendChild(card);
  });

  document.getElementById("btn-save-scanned-pdf").disabled = state.scannedImages.length === 0;
}

document.getElementById("scan-image-input").addEventListener("change", (e) => {
  const files = Array.from(e.target.files || []);
  files.forEach((f) => {
    const reader = new FileReader();
    reader.onload = () => {
      const img = new Image();
      img.onload = () => {
        state.scannedImages.push(img);
        renderScannerPreviews();
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(f);
  });
  e.target.value = "";
});

document.getElementById("scan-filter-select").addEventListener("change", renderScannerPreviews);

document.getElementById("btn-demo-receipt").addEventListener("click", () => {
  const c = document.createElement("canvas");
  c.width = 600;
  c.height = 800;
  const ctx = c.getContext("2d");
  ctx.fillStyle = "#ececec";
  ctx.fillRect(0, 0, 600, 800);
  ctx.fillStyle = "#111827";
  ctx.font = "bold 24px monospace";
  ctx.fillText("PUREPDF SCANNER RECEIPT", 60, 100);
  ctx.font = "20px monospace";
  ctx.fillText("Zero Watermarks:       $0.00", 60, 175);
  ctx.fillText("Smart PDF Compressor:  $0.00", 60, 220);
  ctx.fillText("Offline Neural OCR:    $0.00", 60, 265);
  ctx.fillText("TOTAL CHARGED:         $0.00", 60, 340);

  const img = new Image();
  img.onload = () => {
    state.scannedImages.push(img);
    renderScannerPreviews();
  };
  img.src = c.toDataURL("image/png");
});

document.getElementById("btn-save-scanned-pdf").addEventListener("click", async () => {
  if (state.scannedImages.length === 0) return;
  const filterMode = document.getElementById("scan-filter-select").value;
  const title = document.getElementById("scan-doc-title").value || "Scanned_Document";
  const pdfDoc = await PDFLib.PDFDocument.create();

  for (const img of state.scannedImages) {
    const filteredCanvas = applyScanFilterToCanvas(img, filterMode);
    const jpegUrl = filteredCanvas.toDataURL("image/jpeg", 0.86);
    const embedded = await pdfDoc.embedJpg(jpegUrl);
    const page = pdfDoc.addPage([612, 792]);
    const scale = Math.min(564 / embedded.width, 744 / embedded.height);
    const w = embedded.width * scale;
    const h = embedded.height * scale;
    page.drawImage(embedded, {
      x: (612 - w) / 2,
      y: (792 - h) / 2,
      width: w,
      height: h,
    });
  }

  const pdfBytes = await pdfDoc.save();
  state.scannedImages = [];
  renderScannerPreviews();
  const saved = await addPdfToVault(pdfBytes, title, "Scanned");
  downloadPdfBytes(pdfBytes, saved.title);
  showBanner(`Saved watermark-free scan "${saved.title}" (${formatBytes(pdfBytes.byteLength)})`);
});

// ================= SMART PDF SIZE REDUCER =================
const dpiSlider = document.getElementById("compress-dpi-slider");
const qualSlider = document.getElementById("compress-qual-slider");

document.getElementById("compress-preset-select").addEventListener("change", (e) => {
  const [dpi, qual] = e.target.value.split(",").map(Number);
  dpiSlider.value = String(dpi);
  qualSlider.value = String(Math.round(qual * 100));
  document.getElementById("compress-dpi-label").textContent = `${dpi} DPI`;
  document.getElementById("compress-qual-label").textContent = `${Math.round(qual * 100)}%`;
});

dpiSlider.addEventListener("input", () => {
  document.getElementById("compress-dpi-label").textContent = `${dpiSlider.value} DPI`;
});

qualSlider.addEventListener("input", () => {
  document.getElementById("compress-qual-label").textContent = `${qualSlider.value}%`;
});

document.getElementById("btn-run-compress").addEventListener("click", async () => {
  const id = document.getElementById("compress-pdf-select").value;
  const item = state.vault.find((v) => v.id === id);
  if (!item) return;

  const targetDpi = Number(dpiSlider.value);
  const jpegQuality = Number(qualSlider.value) / 100;
  const useGrayscale = document.getElementById("compress-grayscale-toggle").checked;
  const scale = targetDpi / 72;

  const btn = document.getElementById("btn-run-compress");
  btn.textContent = "Compressing On-Device...";
  btn.disabled = true;

  try {
    const loadingTask = window.pdfjsLib.getDocument({ data: item.bytes.slice() });
    const srcPdf = await loadingTask.promise;
    const outPdf = await PDFLib.PDFDocument.create();

    for (let pageNum = 1; pageNum <= srcPdf.numPages; pageNum++) {
      const page = await srcPdf.getPage(pageNum);
      const baseVp = page.getViewport({ scale: 1.0 });
      const scaledVp = page.getViewport({ scale });

      const canvas = document.createElement("canvas");
      canvas.width = Math.max(1, Math.floor(scaledVp.width));
      canvas.height = Math.max(1, Math.floor(scaledVp.height));
      const ctx = canvas.getContext("2d");
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(0, 0, canvas.width, canvas.height);

      await page.render({ canvasContext: ctx, viewport: scaledVp }).promise;

      if (useGrayscale) {
        const imgData = ctx.getImageData(0, 0, canvas.width, canvas.height);
        const d = imgData.data;
        for (let i = 0; i < d.length; i += 4) {
          const lum = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
          d[i] = d[i + 1] = d[i + 2] = lum;
        }
        ctx.putImageData(imgData, 0, 0);
      }

      const jpegDataUrl = canvas.toDataURL("image/jpeg", jpegQuality);
      const jpgImage = await outPdf.embedJpg(jpegDataUrl);
      const outPage = outPdf.addPage([baseVp.width, baseVp.height]);
      outPage.drawImage(jpgImage, {
        x: 0,
        y: 0,
        width: baseVp.width,
        height: baseVp.height,
      });
    }

    const compressedBytes = await outPdf.save();
    const origBytes = item.bytes.byteLength;
    const newBytes = compressedBytes.byteLength;
    const pct = (((origBytes - newBytes) / origBytes) * 100).toFixed(1);

    state.lastCompressed = {
      bytes: compressedBytes,
      title: `${item.title}_Compressed`,
    };
    await addPdfToVault(compressedBytes, `${item.title}_Compressed`, "Compressed");

    document.getElementById("compress-stats-text").textContent =
      `${formatBytes(origBytes)} → ${formatBytes(newBytes)} (${pct}% reduction)`;
    document.getElementById("compress-result-card").classList.remove("hidden");
  } finally {
    btn.textContent = "Reduce PDF File Size Now";
    btn.disabled = false;
  }
});

document.getElementById("btn-download-compressed").addEventListener("click", () => {
  if (state.lastCompressed) {
    downloadPdfBytes(state.lastCompressed.bytes, state.lastCompressed.title);
  }
});

// ================= FINGER / MOUSE SIGNATURE PAD =================
const sigCanvas = document.getElementById("signature-canvas");
const sigCtx = sigCanvas.getContext("2d");
let isDrawingSig = false;
let hasDrawnSig = false;

function getCanvasPoint(e) {
  const rect = sigCanvas.getBoundingClientRect();
  const clientX = e.touches ? e.touches[0].clientX : e.clientX;
  const clientY = e.touches ? e.touches[0].clientY : e.clientY;
  return {
    x: ((clientX - rect.left) / rect.width) * sigCanvas.width,
    y: ((clientY - rect.top) / rect.height) * sigCanvas.height,
  };
}

function startSigDraw(e) {
  e.preventDefault();
  isDrawingSig = true;
  hasDrawnSig = true;
  const pt = getCanvasPoint(e);
  sigCtx.strokeStyle = document.getElementById("sign-ink-color").value;
  sigCtx.lineWidth = 3.5;
  sigCtx.lineCap = "round";
  sigCtx.lineJoin = "round";
  sigCtx.beginPath();
  sigCtx.moveTo(pt.x, pt.y);
}

function moveSigDraw(e) {
  if (!isDrawingSig) return;
  e.preventDefault();
  const pt = getCanvasPoint(e);
  sigCtx.lineTo(pt.x, pt.y);
  sigCtx.stroke();
}

function endSigDraw() {
  isDrawingSig = false;
}

sigCanvas.addEventListener("mousedown", startSigDraw);
sigCanvas.addEventListener("mousemove", moveSigDraw);
window.addEventListener("mouseup", endSigDraw);
sigCanvas.addEventListener("touchstart", startSigDraw, { passive: false });
sigCanvas.addEventListener("touchmove", moveSigDraw, { passive: false });
window.addEventListener("touchend", endSigDraw);

document.getElementById("btn-clear-sig").addEventListener("click", () => {
  sigCtx.clearRect(0, 0, sigCanvas.width, sigCanvas.height);
  hasDrawnSig = false;
});

document.getElementById("btn-apply-signature").addEventListener("click", async () => {
  const id = document.getElementById("sign-pdf-select").value;
  const item = state.vault.find((v) => v.id === id);
  if (!item) return;

  const pdfDoc = await PDFLib.PDFDocument.load(item.bytes);
  const firstPage = pdfDoc.getPages()[0];
  const { width, height } = firstPage.getSize();

  const normX = Number(document.getElementById("sign-pos-x").value) / 100;
  const normY = Number(document.getElementById("sign-pos-y").value) / 100;
  const customText = document.getElementById("sign-custom-text").value.trim();
  const includeDate = document.getElementById("sign-date-toggle").checked;

  if (hasDrawnSig) {
    const pngUrl = sigCanvas.toDataURL("image/png");
    const sigImg = await pdfDoc.embedPng(pngUrl);
    const sigW = width * 0.34;
    const sigH = sigW * (sigCanvas.height / sigCanvas.width);
    firstPage.drawImage(sigImg, {
      x: width * normX - sigW / 2,
      y: height * normY,
      width: sigW,
      height: sigH,
    });
  }

  const stampParts = [];
  if (customText) stampParts.push(customText);
  if (includeDate) stampParts.push(`Signed: ${new Date().toLocaleDateString()}`);

  if (stampParts.length > 0) {
    const font = await pdfDoc.embedFont(PDFLib.StandardFonts.HelveticaBold);
    firstPage.drawText(stampParts.join("  •  "), {
      x: Math.max(24, width * normX - 80),
      y: Math.max(18, height * normY - 14),
      size: 11,
      font,
      color: PDFLib.rgb(0.08, 0.2, 0.55),
    });
  }

  const signedBytes = await pdfDoc.save();
  const saved = await addPdfToVault(signedBytes, `${item.title}_Signed`, "Signed");
  downloadPdfBytes(signedBytes, saved.title);
  showBanner(`Saved & downloaded signed PDF "${saved.title}".`);
});

// ================= OFFLINE OCR STUDIO =================
document.getElementById("btn-run-ocr").addEventListener("click", async () => {
  const id = document.getElementById("ocr-pdf-select").value;
  const item = state.vault.find((v) => v.id === id);
  if (!item) return;

  const btn = document.getElementById("btn-run-ocr");
  const container = document.getElementById("ocr-output-container");
  btn.textContent = "Extracting Text On-Device...";
  btn.disabled = true;
  container.innerHTML = "";

  try {
    const loadingTask = window.pdfjsLib.getDocument({ data: item.bytes.slice() });
    const pdf = await loadingTask.promise;
    const allPagesText = [];

    for (let i = 1; i <= pdf.numPages; i++) {
      const page = await pdf.getPage(i);
      const textContent = await page.getTextContent();
      let pageText = textContent.items.map((it) => it.str).join(" ").trim();

      if (pageText.length < 15 && window.Tesseract) {
        const vp = page.getViewport({ scale: 1.8 });
        const c = document.createElement("canvas");
        c.width = vp.width;
        c.height = vp.height;
        await page.render({ canvasContext: c.getContext("2d"), viewport: vp }).promise;
        const res = await window.Tesseract.recognize(c, "eng");
        pageText = res.data.text.trim();
      }

      allPagesText.push(`--- Page ${i} ---\n${pageText || "No text detected."}`);
      const card = document.createElement("div");
      card.className = "p-4 rounded-xl bg-slate-950 border border-slate-800 space-y-1.5";
      card.innerHTML = `
        <div class="text-xs font-bold text-teal-400">Page ${i}</div>
        <pre class="text-xs text-slate-200 whitespace-pre-wrap font-mono">${pageText || "No text detected."}</pre>
      `;
      container.appendChild(card);
    }

    const copyBtn = document.getElementById("btn-copy-ocr");
    copyBtn.classList.remove("hidden");
    copyBtn.onclick = () => {
      navigator.clipboard.writeText(allPagesText.join("\n\n"));
      showBanner("Copied all extracted OCR text to clipboard!");
    };
  } finally {
    btn.textContent = "Extract Text Now";
    btn.disabled = false;
  }
});

// Initialize Starter PDF Vault
createStarterSamplePdf();
