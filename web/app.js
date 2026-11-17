/**
 * PurePDF Universal Web & PWA Studio
 * 100% Client-Side PDF Scanner (with 2-Sided ID Card Mode), Smart Target KB Auto-Solver,
 * Interactive Drag-to-Sign on Live PDF Page, Visual Page Organizer, and Searchable Offline OCR.
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
  organizerPages: [], // [{ origIdx, rotation: 0|90|180|270, selected: bool, thumbUrl }]
  sigNormX: 0.42, // center X [0..1]
  sigNormY: 0.75, // center Y from top [0..1]
  sigWidthRatio: 0.36,
  sigRotationDeg: 0,
  lastOcrPages: [], // [{ pageNumber, text }]
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

  ["organizer-pdf-select", "compress-pdf-select", "sign-pdf-select", "ocr-pdf-select"].forEach(
    (selId) => {
      const sel = document.getElementById(selId);
      if (!sel) return;
      const prev = sel.value;
      sel.innerHTML = "";
      state.vault.forEach((item) => {
        const opt = document.createElement("option");
        opt.value = item.id;
        opt.textContent = `${item.title} (${item.pageCount}p • ${formatBytes(item.bytes.byteLength)})`;
        sel.appendChild(opt);
      });
      if (prev && state.vault.some((v) => v.id === prev)) sel.value = prev;
    }
  );

  loadOrganizerThumbnails();
  renderLiveSignPagePreview();
}

function updateMergeButton() {
  const btn = document.getElementById("btn-merge-selected");
  const count = state.selectedForMerge.size;
  btn.textContent = `Merge Selected PDFs (${count})`;
  btn.disabled = count < 2;
}

// ================= VISUAL PAGE ORGANIZER (REORDER, ROTATE 90°, SPLIT) =================
async function loadOrganizerThumbnails() {
  const sel = document.getElementById("organizer-pdf-select");
  if (!sel || !sel.value) return;
  const item = state.vault.find((v) => v.id === sel.value);
  if (!item || !window.pdfjsLib) return;

  const pdf = await window.pdfjsLib.getDocument({ data: item.bytes.slice() }).promise;
  const pages = [];
  for (let i = 1; i <= pdf.numPages; i++) {
    const page = await pdf.getPage(i);
    const vp = page.getViewport({ scale: 0.45 });
    const c = document.createElement("canvas");
    c.width = vp.width;
    c.height = vp.height;
    await page.render({ canvasContext: c.getContext("2d"), viewport: vp }).promise;
    pages.push({
      origIdx: i - 1,
      rotation: 0,
      selected: false,
      thumbUrl: c.toDataURL("image/jpeg", 0.8),
    });
  }
  state.organizerPages = pages;
  renderOrganizerGrid();
}

function renderOrganizerGrid() {
  const grid = document.getElementById("organizer-thumbnails-grid");
  if (!grid) return;
  grid.innerHTML = "";

  state.organizerPages.forEach((p, idx) => {
    const card = document.createElement("div");
    card.className = `p-2.5 rounded-xl bg-slate-950 border ${
      p.selected ? "border-purple-500" : "border-slate-800"
    } flex flex-col items-center gap-2`;
    card.innerHTML = `
      <div class="relative w-full flex items-center justify-center bg-white rounded-lg p-2 h-40 overflow-hidden">
        <img src="${p.thumbUrl}" style="transform: rotate(${p.rotation}deg);" class="max-h-full max-w-full object-contain transition" />
        <input type="checkbox" data-org-check="${idx}" ${p.selected ? "checked" : ""} class="absolute top-2 right-2 w-4 h-4 accent-purple-500" />
      </div>
      <div class="flex items-center gap-2 text-xs">
        <button data-org-left="${idx}" ${idx === 0 ? "disabled" : ""} class="px-2 py-1 rounded bg-slate-800 disabled:opacity-30">◀</button>
        <span class="font-bold text-slate-300">P.${idx + 1}</span>
        <button data-org-rot="${idx}" class="px-2 py-1 rounded bg-teal-900/60 text-teal-300 font-bold">↻</button>
        <button data-org-right="${idx}" ${idx === state.organizerPages.length - 1 ? "disabled" : ""} class="px-2 py-1 rounded bg-slate-800 disabled:opacity-30">▶</button>
      </div>
    `;
    grid.appendChild(card);
  });

  grid.querySelectorAll("[data-org-check]").forEach((cb) => {
    cb.addEventListener("change", (e) => {
      const i = Number(e.target.getAttribute("data-org-check"));
      state.organizerPages[i].selected = e.target.checked;
      renderOrganizerGrid();
    });
  });

  grid.querySelectorAll("[data-org-left]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const i = Number(btn.getAttribute("data-org-left"));
      if (i > 0) {
        const tmp = state.organizerPages[i - 1];
        state.organizerPages[i - 1] = state.organizerPages[i];
        state.organizerPages[i] = tmp;
        renderOrganizerGrid();
      }
    });
  });

  grid.querySelectorAll("[data-org-right]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const i = Number(btn.getAttribute("data-org-right"));
      if (i < state.organizerPages.length - 1) {
        const tmp = state.organizerPages[i + 1];
        state.organizerPages[i + 1] = state.organizerPages[i];
        state.organizerPages[i] = tmp;
        renderOrganizerGrid();
      }
    });
  });

  grid.querySelectorAll("[data-org-rot]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const i = Number(btn.getAttribute("data-org-rot"));
      state.organizerPages[i].rotation = (state.organizerPages[i].rotation + 90) % 360;
      renderOrganizerGrid();
    });
  });
}

document.getElementById("organizer-pdf-select").addEventListener("change", loadOrganizerThumbnails);

async function rebuildOrganizedPdf(onlySelected = false) {
  const id = document.getElementById("organizer-pdf-select").value;
  const item = state.vault.find((v) => v.id === id);
  if (!item) return;

  const subset = onlySelected
    ? state.organizerPages.filter((p) => p.selected)
    : state.organizerPages;
  if (subset.length === 0) {
    showBanner("Check at least 1 page thumbnail first to extract a split PDF.");
    return;
  }

  const srcDoc = await PDFLib.PDFDocument.load(item.bytes);
  const outDoc = await PDFLib.PDFDocument.create();

  for (const p of subset) {
    const [copied] = await outDoc.copyPages(srcDoc, [p.origIdx]);
    if (p.rotation !== 0) {
      const curAngle = copied.getRotation().angle;
      copied.setRotation(PDFLib.degrees((curAngle + p.rotation) % 360));
    }
    outDoc.addPage(copied);
  }

  const outBytes = await outDoc.save();
  const suffix = onlySelected ? `Split_${subset.length}p` : "Organized";
  const created = await addPdfToVault(outBytes, `${item.title}_${suffix}`, suffix);
  downloadPdfBytes(outBytes, created.title);
  showBanner(`Saved & downloaded "${created.title}" (${formatBytes(outBytes.byteLength)})`);
}

document.getElementById("btn-save-organized").addEventListener("click", () => rebuildOrganizedPdf(false));
document.getElementById("btn-extract-selected-pages").addEventListener("click", () => rebuildOrganizedPdf(true));

// Create a rich 2-page starter Sample PDF in browser memory on first load
async function createStarterSamplePdf() {
  const pdfDoc = await PDFLib.PDFDocument.create();
  const fontBold = await pdfDoc.embedFont(PDFLib.StandardFonts.HelveticaBold);
  const fontReg = await pdfDoc.embedFont(PDFLib.StandardFonts.Helvetica);

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
  bCtx.fillText("High-Res Embedded Figure (Test Smart KB Auto-Solver!)", 45, 175);
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
      "1. Smart Target KB Auto-Solver: Binary-searches optimal DPI/quality under <300 KB / <450 KB.",
      "2. Watermark-Free Scanner & 2-Sided ID Card Mode: Stacks Front + Back on 1 page.",
      "3. Live Page Drag-to-Sign: Drag & rotate your ink signature directly on the PDF page.",
      "4. Offline OCR & Searchable PDF: Embeds an invisible searchable text layer offline.",
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
    if (target === "signer") renderLiveSignPagePreview();
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

// ================= SCANNER ENGINE & 2-SIDED ID CARD MODE =================
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
  const layoutMode = document.getElementById("scan-layout-select").value;
  container.innerHTML = "";

  state.scannedImages.forEach((img, idx) => {
    const filteredCanvas = applyScanFilterToCanvas(img, filterMode);
    const card = document.createElement("div");
    card.className = "bg-slate-950 border border-slate-800 rounded-xl p-2 text-center space-y-1.5";
    const previewImg = document.createElement("img");
    previewImg.src = filteredCanvas.toDataURL("image/jpeg", 0.85);
    previewImg.className = "w-full h-40 object-contain rounded-lg bg-white";
    const label = document.createElement("div");
    label.className = "text-xs font-semibold text-slate-300";
    label.textContent =
      layoutMode === "id2up"
        ? idx % 2 === 0
          ? `ID Front (#${idx + 1})`
          : `ID Back (#${idx + 1})`
        : `Page ${idx + 1}`;
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
document.getElementById("scan-layout-select").addEventListener("change", renderScannerPreviews);

document.getElementById("btn-demo-receipt").addEventListener("click", () => {
  document.getElementById("scan-layout-select").value = "standard";
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

document.getElementById("btn-demo-id-card").addEventListener("click", () => {
  document.getElementById("scan-layout-select").value = "id2up";
  document.getElementById("scan-doc-title").value = "ID_Card_Front_And_Back";

  const makeCard = (title, line1, line2, bg) => {
    const c = document.createElement("canvas");
    c.width = 640;
    c.height = 400;
    const ctx = c.getContext("2d");
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, 640, 400);
    ctx.fillStyle = "#111827";
    ctx.font = "bold 24px sans-serif";
    ctx.fillText(title, 40, 80);
    ctx.font = "20px monospace";
    ctx.fillText(line1, 40, 165);
    ctx.fillText(line2, 40, 225);
    return c.toDataURL("image/png");
  };

  const frontUrl = makeCard("IDENTIFICATION CARD — FRONT", "Name: MAITREE RAWAT", "ID #: PURE-2026-0001", "#e0f2fe");
  const backUrl = makeCard("IDENTIFICATION CARD — BACK", "<<<<PUREPDF<<ONDEVICE<<2026<<<<", "Zero Cloud • Zero Watermarks", "#f1f5f9");

  [frontUrl, backUrl].forEach((url) => {
    const img = new Image();
    img.onload = () => {
      state.scannedImages.push(img);
      renderScannerPreviews();
    };
    img.src = url;
  });
});

document.getElementById("btn-save-scanned-pdf").addEventListener("click", async () => {
  if (state.scannedImages.length === 0) return;
  const filterMode = document.getElementById("scan-filter-select").value;
  const layoutMode = document.getElementById("scan-layout-select").value;
  const title = document.getElementById("scan-doc-title").value || "Scanned_Document";
  const pdfDoc = await PDFLib.PDFDocument.create();
  const fontBold = await pdfDoc.embedFont(PDFLib.StandardFonts.HelveticaBold);

  if (layoutMode === "id2up") {
    for (let i = 0; i < state.scannedImages.length; i += 2) {
      const page = pdfDoc.addPage([612, 792]);
      const drawCard = async (img, yBottom, labelText) => {
        const filtered = applyScanFilterToCanvas(img, filterMode);
        const embedded = await pdfDoc.embedJpg(filtered.toDataURL("image/jpeg", 0.88));
        page.drawText(labelText, {
          x: 86,
          y: yBottom + 286,
          size: 9.5,
          font: fontBold,
          color: PDFLib.rgb(0.45, 0.48, 0.52),
        });
        page.drawRectangle({
          x: 86,
          y: yBottom,
          width: 440,
          height: 280,
          borderColor: PDFLib.rgb(0.8, 0.82, 0.85),
          borderWidth: 1,
        });
        const scale = Math.min(416 / embedded.width, 256 / embedded.height);
        const w = embedded.width * scale;
        const h = embedded.height * scale;
        page.drawImage(embedded, {
          x: 86 + (440 - w) / 2,
          y: yBottom + (280 - h) / 2,
          width: w,
          height: h,
        });
      };

      await drawCard(state.scannedImages[i], 430, "FRONT SIDE");
      if (i + 1 < state.scannedImages.length) {
        await drawCard(state.scannedImages[i + 1], 90, "BACK SIDE");
      }
    }
  } else {
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
  }

  const pdfBytes = await pdfDoc.save();
  state.scannedImages = [];
  renderScannerPreviews();
  const badge = layoutMode === "id2up" ? "ID Card 2-Up" : "Scanned";
  const saved = await addPdfToVault(pdfBytes, title, badge);
  downloadPdfBytes(pdfBytes, saved.title);
  showBanner(`Saved watermark-free PDF "${saved.title}" (${formatBytes(pdfBytes.byteLength)})`);
});

// ================= SMART PDF SIZE REDUCER & TARGET KB AUTO-SOLVER =================
const dpiSlider = document.getElementById("compress-dpi-slider");
const qualSlider = document.getElementById("compress-qual-slider");
const presetSelect = document.getElementById("compress-preset-select");
const targetKbInput = document.getElementById("target-kb-input");

presetSelect.addEventListener("change", (e) => {
  const val = e.target.value;
  if (val === "auto") {
    document.getElementById("auto-kb-controls").classList.remove("hidden");
    document.getElementById("manual-compress-controls").classList.add("hidden");
  } else {
    document.getElementById("auto-kb-controls").classList.add("hidden");
    document.getElementById("manual-compress-controls").classList.remove("hidden");
    const [dpi, qual] = val.split(",").map(Number);
    dpiSlider.value = String(dpi);
    qualSlider.value = String(Math.round(qual * 100));
    document.getElementById("compress-dpi-label").textContent = `${dpi} DPI`;
    document.getElementById("compress-qual-label").textContent = `${Math.round(qual * 100)}%`;
  }
});

document.querySelectorAll(".kb-pill").forEach((pill) => {
  pill.addEventListener("click", () => {
    targetKbInput.value = pill.getAttribute("data-kb");
    document.querySelectorAll(".kb-pill").forEach((p) => {
      p.className = "kb-pill px-2.5 py-1 rounded-full bg-slate-800 hover:bg-orange-600 text-xs font-bold";
    });
    pill.className = "kb-pill px-2.5 py-1 rounded-full bg-orange-600 text-white text-xs font-bold";
  });
});

dpiSlider.addEventListener("input", () => {
  document.getElementById("compress-dpi-label").textContent = `${dpiSlider.value} DPI`;
});

qualSlider.addEventListener("input", () => {
  document.getElementById("compress-qual-label").textContent = `${qualSlider.value}%`;
});

async function compressPdfAtSetting(srcBytes, targetDpi, jpegQuality, useGrayscale) {
  const scale = targetDpi / 72;
  const loadingTask = window.pdfjsLib.getDocument({ data: srcBytes.slice() });
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

  return await outPdf.save();
}

document.getElementById("btn-run-compress").addEventListener("click", async () => {
  const id = document.getElementById("compress-pdf-select").value;
  const item = state.vault.find((v) => v.id === id);
  if (!item) return;

  const useGrayscale = document.getElementById("compress-grayscale-toggle").checked;
  const isAutoMode = presetSelect.value === "auto";
  const btn = document.getElementById("btn-run-compress");
  btn.textContent = isAutoMode ? "Binary-Searching Optimal DPI & Quality..." : "Compressing On-Device...";
  btn.disabled = true;

  try {
    let finalBytes = null;
    let chosenDpi = Number(dpiSlider.value);
    let chosenQualPct = Number(qualSlider.value);

    if (isAutoMode) {
      const targetBytes = Math.max(30, Number(targetKbInput.value || 450)) * 1024;
      const ladder = [
        [210, 0.84],
        [180, 0.74],
        [155, 0.64],
        [135, 0.56],
        [118, 0.48],
        [102, 0.4],
        [88, 0.34],
        [74, 0.28],
        [62, 0.22],
        [50, 0.15],
      ];

      let low = 0;
      let high = ladder.length - 1;
      let bestFit = null;
      let smallestFallback = null;

      while (low <= high) {
        const mid = Math.floor((low + high) / 2);
        const [d, q] = ladder[mid];
        const candidate = await compressPdfAtSetting(item.bytes, d, q, useGrayscale);

        if (!smallestFallback || candidate.byteLength < smallestFallback.bytes.byteLength) {
          smallestFallback = { bytes: candidate, dpi: d, qualPct: Math.round(q * 100) };
        }

        if (candidate.byteLength <= targetBytes) {
          bestFit = { bytes: candidate, dpi: d, qualPct: Math.round(q * 100) };
          high = mid - 1;
        } else {
          low = mid + 1;
        }
      }

      const winner = bestFit || smallestFallback;
      finalBytes = winner.bytes;
      chosenDpi = winner.dpi;
      chosenQualPct = winner.qualPct;
    } else {
      finalBytes = await compressPdfAtSetting(item.bytes, chosenDpi, chosenQualPct / 100, useGrayscale);
    }

    const origBytes = item.bytes.byteLength;
    const newBytes = finalBytes.byteLength;
    const pct = (((origBytes - newBytes) / origBytes) * 100).toFixed(1);

    state.lastCompressed = {
      bytes: finalBytes,
      title: `${item.title}_Compressed`,
    };
    await addPdfToVault(finalBytes, `${item.title}_Compressed`, "Compressed");

    document.getElementById("compress-meta-badge").textContent =
      `Optimal Settings Selected: ${chosenDpi} DPI • ${chosenQualPct}% JPEG Quality`;
    document.getElementById("compress-stats-text").textContent =
      `${formatBytes(origBytes)} → ${formatBytes(newBytes)} (${pct}% reduction)`;
    document.getElementById("compress-result-card").classList.remove("hidden");
  } finally {
    btn.textContent = "Auto-Solve & Reduce PDF Size Now";
    btn.disabled = false;
  }
});

document.getElementById("btn-download-compressed").addEventListener("click", () => {
  if (state.lastCompressed) {
    downloadPdfBytes(state.lastCompressed.bytes, state.lastCompressed.title);
  }
});

// ================= INTERACTIVE LIVE PAGE DRAG-TO-SIGN STUDIO =================
const sigCanvas = document.getElementById("signature-canvas");
const sigCtx = sigCanvas.getContext("2d");
const dragBox = document.getElementById("draggable-sig-box");
const dragSigImg = document.getElementById("draggable-sig-img");
const dragPlaceholder = document.getElementById("draggable-sig-placeholder");
const dragStampLabel = document.getElementById("draggable-stamp-label");
const liveStage = document.getElementById("live-page-stage");

let isDrawingSig = false;
let hasDrawnSig = false;

async function renderLiveSignPagePreview() {
  const sel = document.getElementById("sign-pdf-select");
  if (!sel || !sel.value || !window.pdfjsLib) return;
  const item = state.vault.find((v) => v.id === sel.value);
  if (!item) return;

  const pdf = await window.pdfjsLib.getDocument({ data: item.bytes.slice() }).promise;
  const page = await pdf.getPage(1);
  const vp = page.getViewport({ scale: 1.1 });
  const previewCanvas = document.getElementById("pdf-page-preview-canvas");
  previewCanvas.width = vp.width;
  previewCanvas.height = vp.height;
  await page.render({ canvasContext: previewCanvas.getContext("2d"), viewport: vp }).promise;
  updateDraggableOverlayUI();
}

function updateDraggableOverlayUI() {
  const customText = document.getElementById("sign-custom-text").value.trim();
  const includeDate = document.getElementById("sign-date-toggle").checked;
  const parts = [];
  if (customText) parts.push(customText);
  if (includeDate) parts.push(`Signed: ${new Date().toLocaleDateString()}`);
  dragStampLabel.textContent = parts.join(" • ");

  const wPct = state.sigWidthRatio * 100;
  const leftPct = Math.max(2, Math.min(98 - wPct, state.sigNormX * 100 - wPct / 2));
  const topPct = Math.max(4, Math.min(90, state.sigNormY * 100 - 6));

  dragBox.style.width = `${wPct}%`;
  dragBox.style.left = `${leftPct}%`;
  dragBox.style.top = `${topPct}%`;
  dragBox.style.transform = `rotate(${state.sigRotationDeg}deg)`;

  if (hasDrawnSig) {
    dragSigImg.src = sigCanvas.toDataURL("image/png");
    dragSigImg.classList.remove("hidden");
    dragPlaceholder.classList.add("hidden");
  } else {
    dragSigImg.classList.add("hidden");
    dragPlaceholder.classList.remove("hidden");
  }
}

document.getElementById("sign-pdf-select").addEventListener("change", renderLiveSignPagePreview);
document.getElementById("sign-scale-slider").addEventListener("input", (e) => {
  state.sigWidthRatio = Number(e.target.value) / 100;
  updateDraggableOverlayUI();
});
document.getElementById("sign-rot-slider").addEventListener("input", (e) => {
  state.sigRotationDeg = Number(e.target.value);
  document.getElementById("sign-rot-label").textContent = `${state.sigRotationDeg}°`;
  updateDraggableOverlayUI();
});
document.getElementById("sign-custom-text").addEventListener("input", updateDraggableOverlayUI);
document.getElementById("sign-date-toggle").addEventListener("change", updateDraggableOverlayUI);

// Dragging the signature overlay directly on the live PDF page
let isDraggingOverlay = false;
function onStagePointerMove(e) {
  if (!isDraggingOverlay) return;
  e.preventDefault();
  const rect = liveStage.getBoundingClientRect();
  const clientX = e.touches ? e.touches[0].clientX : e.clientX;
  const clientY = e.touches ? e.touches[0].clientY : e.clientY;
  state.sigNormX = Math.max(0.12, Math.min(0.88, (clientX - rect.left) / rect.width));
  state.sigNormY = Math.max(0.08, Math.min(0.92, (clientY - rect.top) / rect.height));
  updateDraggableOverlayUI();
}

dragBox.addEventListener("mousedown", (e) => {
  e.preventDefault();
  isDraggingOverlay = true;
});
window.addEventListener("mousemove", onStagePointerMove);
window.addEventListener("mouseup", () => {
  isDraggingOverlay = false;
});
dragBox.addEventListener(
  "touchstart",
  (e) => {
    e.preventDefault();
    isDraggingOverlay = true;
  },
  { passive: false }
);
window.addEventListener("touchmove", onStagePointerMove, { passive: false });
window.addEventListener("touchend", () => {
  isDraggingOverlay = false;
});

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
  if (isDrawingSig) {
    isDrawingSig = false;
    updateDraggableOverlayUI();
  }
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
  updateDraggableOverlayUI();
});

document.getElementById("btn-apply-signature").addEventListener("click", async () => {
  const id = document.getElementById("sign-pdf-select").value;
  const item = state.vault.find((v) => v.id === id);
  if (!item) return;

  const pdfDoc = await PDFLib.PDFDocument.load(item.bytes);
  const firstPage = pdfDoc.getPages()[0];
  const { width, height } = firstPage.getSize();

  const pdfX = width * state.sigNormX;
  const pdfY = height * (1.0 - state.sigNormY);
  const customText = document.getElementById("sign-custom-text").value.trim();
  const includeDate = document.getElementById("sign-date-toggle").checked;

  if (hasDrawnSig) {
    const pngUrl = sigCanvas.toDataURL("image/png");
    const sigImg = await pdfDoc.embedPng(pngUrl);
    const sigW = width * state.sigWidthRatio;
    const sigH = sigW * (sigCanvas.height / sigCanvas.width);
    firstPage.drawImage(sigImg, {
      x: pdfX - sigW / 2,
      y: pdfY - sigH / 2,
      width: sigW,
      height: sigH,
      rotate: PDFLib.degrees(-state.sigRotationDeg),
    });
  }

  const stampParts = [];
  if (customText) stampParts.push(customText);
  if (includeDate) stampParts.push(`Signed: ${new Date().toLocaleDateString()}`);

  if (stampParts.length > 0) {
    const font = await pdfDoc.embedFont(PDFLib.StandardFonts.HelveticaBold);
    firstPage.drawText(stampParts.join("  •  "), {
      x: Math.max(24, pdfX - 85),
      y: Math.max(18, pdfY - 34),
      size: 10.5,
      font,
      color: PDFLib.rgb(0.08, 0.2, 0.55),
    });
  }

  const signedBytes = await pdfDoc.save();
  const saved = await addPdfToVault(signedBytes, `${item.title}_Signed`, "Signed");
  downloadPdfBytes(signedBytes, saved.title);
  showBanner(`Saved & downloaded signed PDF "${saved.title}".`);
});

// ================= OFFLINE OCR & SEARCHABLE PDF BUILDER =================
function renderOcrCards(filterText = "") {
  const container = document.getElementById("ocr-output-container");
  container.innerHTML = "";
  const q = filterText.trim().toLowerCase();

  state.lastOcrPages
    .filter((p) => !q || p.text.toLowerCase().includes(q))
    .forEach((p) => {
      const card = document.createElement("div");
      card.className = "p-4 rounded-xl bg-slate-950 border border-slate-800 space-y-1.5";
      card.innerHTML = `
        <div class="text-xs font-bold text-teal-400">Page ${p.pageNumber}</div>
        <pre class="text-xs text-slate-200 whitespace-pre-wrap font-mono">${p.text || "No text detected."}</pre>
      `;
      container.appendChild(card);
    });
}

document.getElementById("ocr-search-input").addEventListener("input", (e) => {
  renderOcrCards(e.target.value);
});

document.getElementById("btn-run-ocr").addEventListener("click", async () => {
  const id = document.getElementById("ocr-pdf-select").value;
  const item = state.vault.find((v) => v.id === id);
  if (!item) return;

  const btn = document.getElementById("btn-run-ocr");
  btn.textContent = "Extracting Text On-Device...";
  btn.disabled = true;

  try {
    const loadingTask = window.pdfjsLib.getDocument({ data: item.bytes.slice() });
    const pdf = await loadingTask.promise;
    const extracted = [];

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

      extracted.push({ pageNumber: i, text: pageText || "No text detected." });
    }

    state.lastOcrPages = extracted;
    renderOcrCards();

    const copyBtn = document.getElementById("btn-copy-ocr");
    const searchableBtn = document.getElementById("btn-save-searchable-pdf");
    const searchInput = document.getElementById("ocr-search-input");
    copyBtn.classList.remove("hidden");
    searchableBtn.classList.remove("hidden");
    searchInput.classList.remove("hidden");

    copyBtn.onclick = () => {
      const all = state.lastOcrPages.map((p) => `--- Page ${p.pageNumber} ---\n${p.text}`).join("\n\n");
      navigator.clipboard.writeText(all);
      showBanner("Copied all extracted OCR text to clipboard!");
    };

    searchableBtn.onclick = async () => {
      const pdfDoc = await PDFLib.PDFDocument.load(item.bytes);
      const font = await pdfDoc.embedFont(PDFLib.StandardFonts.Helvetica);
      const pages = pdfDoc.getPages();
      pages.forEach((p, idx) => {
        if (idx < state.lastOcrPages.length) {
          p.drawText(state.lastOcrPages[idx].text.slice(0, 1500), {
            x: 36,
            y: 36,
            size: 8,
            font,
            opacity: 0.01,
          });
        }
      });
      const outBytes = await pdfDoc.save();
      const created = await addPdfToVault(outBytes, `${item.title}_SearchableOCR`, "Searchable OCR");
      downloadPdfBytes(outBytes, created.title);
      showBanner(`Saved Searchable OCR PDF "${created.title}"!`);
    };
  } finally {
    btn.textContent = "Extract Text Now";
    btn.disabled = false;
  }
});

// Initialize Starter PDF Vault
createStarterSamplePdf();
