package com.maitreerawat.purepdf.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color as AndroidColor
import android.graphics.Paint
import android.text.format.Formatter
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas as ComposeCanvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.maitreerawat.purepdf.engine.*
import com.maitreerawat.purepdf.model.PdfVaultItem
import com.maitreerawat.purepdf.model.PdfVaultManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

enum class AndroidTab(val label: String) {
    STUDIO("Studio"),
    SCAN("Scan"),
    COMPRESS("Reduce Size"),
    SIGN("Sign PDF"),
    OCR("OCR Text")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PurePdfAppScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var activeTab by remember { mutableStateOf(AndroidTab.STUDIO) }
    var vaultItems by remember { mutableStateOf(PdfVaultManager.loadVaultItems(context)) }
    var statusMessage by remember { mutableStateOf<String?>(null) }

    val pdfImporter = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                val bytes = stream.readBytes()
                PdfVaultManager.savePdfBytes(context, bytes, "Imported_Document", "Imported")
                vaultItems = PdfVaultManager.loadVaultItems(context)
                statusMessage = "Imported PDF (${Formatter.formatFileSize(context, bytes.size.toLong())})"
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("PurePDF Android", fontWeight = FontWeight.Bold) },
                actions = {
                    TextButton(onClick = { pdfImporter.launch("application/pdf") }) {
                        Icon(Icons.Default.Add, contentDescription = null)
                        Spacer(Modifier.width(4.dp))
                        Text("Import PDF")
                    }
                }
            )
        },
        bottomBar = {
            NavigationBar {
                AndroidTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = activeTab == tab,
                        onClick = { activeTab = tab },
                        icon = {
                            val icon = when (tab) {
                                AndroidTab.STUDIO -> Icons.Default.AutoAwesome
                                AndroidTab.SCAN -> Icons.Default.DocumentScanner
                                AndroidTab.COMPRESS -> Icons.Default.Compress
                                AndroidTab.SIGN -> Icons.Default.Draw
                                AndroidTab.OCR -> Icons.Default.TextSnippet
                            }
                            Icon(icon, contentDescription = tab.label)
                        },
                        label = { Text(tab.label, fontSize = 11.sp) }
                    )
                }
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp)
        ) {
            statusMessage?.let { msg ->
                Surface(
                    color = Color(0xFFECFDF5),
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(msg, color = Color(0xFF065F46), fontSize = 13.sp, modifier = Modifier.weight(1f))
                        TextButton(onClick = { statusMessage = null }) { Text("OK") }
                    }
                }
            }

            when (activeTab) {
                AndroidTab.STUDIO -> StudioDashboardSection(
                    items = vaultItems,
                    onSelectTab = { activeTab = it },
                    onMergeAll = { selectedFiles ->
                        scope.launch {
                            val bytes = withContext(Dispatchers.IO) { PdfPageToolkitEngine.mergePdfs(selectedFiles) }
                            PdfVaultManager.savePdfBytes(context, bytes, "Merged_Document", "Merged")
                            vaultItems = PdfVaultManager.loadVaultItems(context)
                            statusMessage = "Merged ${selectedFiles.size} PDFs (${Formatter.formatFileSize(context, bytes.size.toLong())})"
                        }
                    },
                    onShareItem = { sharePdfFile(context, it) },
                    onDeleteItem = { item ->
                        item.file.delete()
                        vaultItems = PdfVaultManager.loadVaultItems(context)
                    }
                )
                AndroidTab.SCAN -> ScannerSection(
                    onSaveScannedPdf = { pages, filter, layoutMode, title ->
                        scope.launch {
                            val bytes = withContext(Dispatchers.IO) {
                                DocumentScannerEngine.buildWatermarkFreePdf(pages, filter, layoutMode)
                            }
                            val badge = if (layoutMode == AndroidScanLayoutMode.ID_CARD_TWO_UP) "ID_2Up" else "Scanned"
                            PdfVaultManager.savePdfBytes(context, bytes, title, badge)
                            vaultItems = PdfVaultManager.loadVaultItems(context)
                            statusMessage = "Saved Watermark-Free Scan (${Formatter.formatFileSize(context, bytes.size.toLong())})"
                            activeTab = AndroidTab.STUDIO
                        }
                    }
                )
                AndroidTab.COMPRESS -> CompressorSection(
                    items = vaultItems,
                    onSaveCompressed = { res, title ->
                        PdfVaultManager.savePdfBytes(context, res.pdfBytes, title, "Compressed")
                        vaultItems = PdfVaultManager.loadVaultItems(context)
                        statusMessage = "Saved Compressed PDF (${Formatter.formatFileSize(context, res.compressedBytes)})"
                    }
                )
                AndroidTab.SIGN -> SignerSection(
                    items = vaultItems,
                    onSaveSigned = { bytes, title ->
                        PdfVaultManager.savePdfBytes(context, bytes, title, "Signed")
                        vaultItems = PdfVaultManager.loadVaultItems(context)
                        statusMessage = "Saved Signed PDF (${Formatter.formatFileSize(context, bytes.size.toLong())})"
                        activeTab = AndroidTab.STUDIO
                    }
                )
                AndroidTab.OCR -> OcrSection(
                    items = vaultItems,
                    onSaveSearchablePdf = { bytes, title ->
                        PdfVaultManager.savePdfBytes(context, bytes, title, "SearchableOCR")
                        vaultItems = PdfVaultManager.loadVaultItems(context)
                        statusMessage = "Saved Searchable OCR PDF (${Formatter.formatFileSize(context, bytes.size.toLong())})"
                    }
                )
            }
        }
    }
}

@Composable
private fun StudioDashboardSection(
    items: List<PdfVaultItem>,
    onSelectTab: (AndroidTab) -> Unit,
    onMergeAll: (List<java.io.File>) -> Unit,
    onShareItem: (PdfVaultItem) -> Unit,
    onDeleteItem: (PdfVaultItem) -> Unit
) {
    val context = LocalContext.current
    var selectedForMerge by remember { mutableStateOf(setOf<String>()) }

    LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Surface(
                color = Color(0xFF0F766E),
                shape = RoundedCornerShape(18.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(18.dp)) {
                    Text(
                        "100% Free • Zero Ads • Zero Internet Permission",
                        color = Color.White.copy(alpha = 0.9f),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "Every PDF is processed 100% locally on your Android device.",
                        color = Color.White,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }

        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                Button(onClick = { onSelectTab(AndroidTab.SCAN) }, modifier = Modifier.weight(1f)) {
                    Text("Scan / ID 2-Up")
                }
                Button(onClick = { onSelectTab(AndroidTab.COMPRESS) }, modifier = Modifier.weight(1f)) {
                    Text("Auto-Fit KB")
                }
            }
        }

        if (selectedForMerge.size >= 2) {
            item {
                Button(
                    onClick = {
                        val files = items.filter { selectedForMerge.contains(it.id) }.map { it.file }
                        onMergeAll(files)
                        selectedForMerge = emptySet()
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Merge Selected PDFs (${selectedForMerge.size})")
                }
            }
        }

        item {
            Text("On-Device PDF Vault (${items.size})", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        }

        items(items) { item ->
            val checked = selectedForMerge.contains(item.id)
            Card(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Checkbox(
                        checked = checked,
                        onCheckedChange = {
                            selectedForMerge = if (it) selectedForMerge + item.id else selectedForMerge - item.id
                        }
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(item.title, fontWeight = FontWeight.SemiBold, maxLines = 1)
                        Text(
                            "${item.badgeTag} • ${item.pageCount}p • ${item.formattedSize(context)}",
                            fontSize = 12.sp,
                            color = Color.Gray
                        )
                    }
                    IconButton(onClick = { onShareItem(item) }) {
                        Icon(Icons.Default.Share, contentDescription = "Share")
                    }
                    IconButton(onClick = { onDeleteItem(item) }) {
                        Icon(Icons.Default.Delete, contentDescription = "Delete", tint = Color.Red)
                    }
                }
            }
        }
    }
}

@Composable
private fun ScannerSection(
    onSaveScannedPdf: (List<Bitmap>, AndroidScanFilter, AndroidScanLayoutMode, String) -> Unit
) {
    val context = LocalContext.current
    var pages by remember { mutableStateOf(listOf<Bitmap>()) }
    var filter by remember { mutableStateOf(AndroidScanFilter.MAGIC_CRISP_BW) }
    var layoutMode by remember { mutableStateOf(AndroidScanLayoutMode.STANDARD_ONE_PER_PAGE) }
    var docTitle by remember { mutableStateOf("Scanned_Document") }

    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream)?.let { bmp ->
                    pages = pages + bmp
                }
            }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Watermark-Free Scanner & 2-Sided ID Card Studio", fontWeight = FontWeight.Bold, fontSize = 18.sp)

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AndroidScanLayoutMode.entries.forEach { mode ->
                FilterChip(
                    selected = layoutMode == mode,
                    onClick = { layoutMode = mode },
                    label = { Text(mode.label, fontSize = 11.sp) }
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(onClick = { photoPicker.launch("image/*") }, modifier = Modifier.weight(1f)) {
                Text("Add Photo / Scan")
            }
            OutlinedButton(
                onClick = {
                    layoutMode = AndroidScanLayoutMode.ID_CARD_TWO_UP
                    val front = Bitmap.createBitmap(640, 400, Bitmap.Config.ARGB_8888).apply {
                        val c = Canvas(this)
                        c.drawColor(AndroidColor.rgb(225, 240, 245))
                        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            color = AndroidColor.BLACK
                            textSize = 24f
                            isFakeBoldText = true
                        }
                        c.drawText("IDENTIFICATION CARD — FRONT", 40f, 90f, p)
                        c.drawText("Name: MAITREE RAWAT", 40f, 160f, p)
                        c.drawText("ID #: PURE-2026-0001", 40f, 220f, p)
                    }
                    val back = Bitmap.createBitmap(640, 400, Bitmap.Config.ARGB_8888).apply {
                        val c = Canvas(this)
                        c.drawColor(AndroidColor.rgb(240, 240, 240))
                        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            color = AndroidColor.DKGRAY
                            textSize = 22f
                            isFakeBoldText = true
                        }
                        c.drawText("IDENTIFICATION CARD — BACK", 40f, 100f, p)
                        c.drawText("<<<<PUREPDF<<ONDEVICE<<2026<<<<", 40f, 190f, p)
                    }
                    pages = pages + listOf(front, back)
                    docTitle = "ID_Card_Front_And_Back"
                },
                modifier = Modifier.weight(1f)
            ) {
                Text("Demo Front+Back ID")
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AndroidScanFilter.entries.forEach { f ->
                FilterChip(
                    selected = filter == f,
                    onClick = { filter = f },
                    label = { Text(f.label, fontSize = 12.sp) }
                )
            }
        }

        OutlinedTextField(
            value = docTitle,
            onValueChange = { docTitle = it },
            label = { Text("Output PDF Name") },
            modifier = Modifier.fillMaxWidth()
        )

        Button(
            onClick = { onSaveScannedPdf(pages, filter, layoutMode, docTitle) },
            enabled = pages.isNotEmpty(),
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                if (layoutMode == AndroidScanLayoutMode.ID_CARD_TWO_UP)
                    "Save 2-Sided ID Card PDF (${pages.size} Sides)"
                else
                    "Save Watermark-Free PDF (${pages.size} Pages)"
            )
        }
    }
}

@Composable
private fun CompressorSection(
    items: List<PdfVaultItem>,
    onSaveCompressed: (AndroidCompressionResult, String) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selectedIdx by remember { mutableStateOf(0) }
    var preset by remember { mutableStateOf(AndroidCompressionPreset.AUTO_TARGET_KB) }
    var targetKb by remember { mutableStateOf(450) }
    var dpi by remember { mutableStateOf(110f) }
    var quality by remember { mutableStateOf(48f) }
    var grayscale by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<AndroidCompressionResult?>(null) }
    var isWorking by remember { mutableStateOf(false) }

    val currentItem = items.getOrNull(selectedIdx)
    val quickTargets = listOf(200, 300, 450, 750, 1000)

    LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Text("Smart PDF Size Reducer & Auto-Solver", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            if (currentItem != null) {
                Text(
                    "Selected: ${currentItem.title} (${currentItem.formattedSize(context)})",
                    fontSize = 13.sp,
                    color = Color(0xFF0F766E),
                    fontWeight = FontWeight.SemiBold
                )
            }
        }

        items(AndroidCompressionPreset.entries.toTypedArray()) { p ->
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        preset = p
                        dpi = p.defaultDpi.toFloat()
                        quality = p.defaultQuality.toFloat()
                        result = null
                    }
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(p.label, fontWeight = FontWeight.Bold)
                    Text(p.subtitle, fontSize = 12.sp, color = Color.Gray)
                }
            }
        }

        item {
            if (preset == AndroidCompressionPreset.AUTO_TARGET_KB) {
                Text("Target Ceiling: < $targetKb KB", fontWeight = FontWeight.Bold, color = Color(0xFFEA580C))
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(quickTargets) { kb ->
                        FilterChip(
                            selected = targetKb == kb,
                            onClick = { targetKb = kb; result = null },
                            label = { Text("<$kb KB") }
                        )
                    }
                }
            } else {
                Text("Target Resolution: ${dpi.toInt()} DPI • JPEG Quality: ${quality.toInt()}%", fontSize = 13.sp)
                Slider(value = dpi, onValueChange = { dpi = it }, valueRange = 55f..240f)
                Slider(value = quality, onValueChange = { quality = it }, valueRange = 15f..92f)
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = grayscale, onCheckedChange = { grayscale = it })
                Text("Convert to Crisp Grayscale (Extra Size Reduction)", fontSize = 13.sp)
            }

            Button(
                onClick = {
                    val target = currentItem ?: return@Button
                    isWorking = true
                    scope.launch {
                        val comp = withContext(Dispatchers.IO) {
                            if (preset == AndroidCompressionPreset.AUTO_TARGET_KB) {
                                PdfCompressorEngine.autoSolveTargetKb(target.file, targetKb, grayscale)
                            } else {
                                PdfCompressorEngine.compressPdf(target.file, dpi.toInt(), quality.toInt(), grayscale)
                            }
                        }
                        result = comp
                        isWorking = false
                    }
                },
                enabled = currentItem != null && !isWorking,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    if (isWorking) "Solving Optimal DPI & Quality..."
                    else if (preset == AndroidCompressionPreset.AUTO_TARGET_KB) "Auto-Fit Under $targetKb KB Now"
                    else "Reduce PDF Size Now"
                )
            }
        }

        result?.let { res ->
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(
                            "Optimal Settings Used: ${res.appliedDpi} DPI • ${res.appliedQuality}% JPEG Quality",
                            fontSize = 12.sp,
                            color = Color.Gray
                        )
                        Text(
                            "Before: ${Formatter.formatFileSize(context, res.originalBytes)}  →  After: ${Formatter.formatFileSize(context, res.compressedBytes)} (-${String.format("%.1f", res.reductionPercent)}%)",
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFF065F46)
                        )
                        Button(
                            onClick = {
                                onSaveCompressed(res, currentItem?.title ?: "Document")
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("Save Compressed PDF to Vault")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SignerSection(
    items: List<PdfVaultItem>,
    onSaveSigned: (ByteArray, String) -> Unit
) {
    val scope = rememberCoroutineScope()
    val currentItem = items.firstOrNull()
    var strokes by remember { mutableStateOf(listOf<List<Pair<Float, Float>>>()) }
    var activeStroke by remember { mutableStateOf(listOf<Pair<Float, Float>>()) }
    var customName by remember { mutableStateOf("") }
    var includeDate by remember { mutableStateOf(true) }
    var normX by remember { mutableStateOf(0.42f) }
    var normY by remember { mutableStateOf(0.76f) }
    var rotationDeg by remember { mutableStateOf(0f) }
    var containerSize by remember { mutableStateOf(IntSize(1, 1)) }

    val pagePreview = remember(currentItem) {
        currentItem?.let { PdfSignerEngine.renderPagePreview(it.file, 0) }
    }

    LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Text("Interactive Drag-on-Page PDF Signer", fontWeight = FontWeight.Bold, fontSize = 18.sp)

            if (pagePreview != null) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(260.dp)
                        .background(Color.White, RoundedCornerShape(12.dp))
                        .border(1.dp, Color.LightGray, RoundedCornerShape(12.dp))
                        .onSizeChanged { containerSize = it }
                ) {
                    Image(
                        bitmap = pagePreview.asImageBitmap(),
                        contentDescription = "PDF Page Preview",
                        modifier = Modifier.fillMaxSize()
                    )

                    Box(
                        modifier = Modifier
                            .offset {
                                IntOffset(
                                    x = (normX * containerSize.width - 70).roundToInt(),
                                    y = (normY * containerSize.height - 28).roundToInt()
                                )
                            }
                            .background(Color(0x224338CA), RoundedCornerShape(8.dp))
                            .border(1.5.dp, Color(0xFF4338CA), RoundedCornerShape(8.dp))
                            .padding(horizontal = 12.dp, vertical = 8.dp)
                            .pointerInput(Unit) {
                                detectDragGestures { change, dragAmount ->
                                    change.consume()
                                    normX = (normX + dragAmount.x / containerSize.width.coerceAtLeast(1)).coerceIn(0.1f, 0.9f)
                                    normY = (normY + dragAmount.y / containerSize.height.coerceAtLeast(1)).coerceIn(0.1f, 0.9f)
                                }
                            }
                    ) {
                        Text("Drag Signature Here", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color(0xFF4338CA))
                    }
                }
            }
        }

        item {
            Text("Draw Signature Below:", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(145.dp)
                    .background(Color.White, RoundedCornerShape(14.dp))
                    .border(1.5.dp, Color(0xFF4338CA), RoundedCornerShape(14.dp))
                    .pointerInput(Unit) {
                        detectDragGestures(
                            onDragStart = { offset ->
                                activeStroke = listOf(offset.x to offset.y)
                            },
                            onDrag = { change, _ ->
                                activeStroke = activeStroke + (change.position.x to change.position.y)
                            },
                            onDragEnd = {
                                if (activeStroke.size > 1) {
                                    strokes = strokes + listOf(activeStroke)
                                }
                                activeStroke = emptyList()
                            }
                        )
                    }
            ) {
                ComposeCanvas(modifier = Modifier.fillMaxSize()) {
                    val all = if (activeStroke.isNotEmpty()) strokes + listOf(activeStroke) else strokes
                    for (s in all) {
                        if (s.size < 2) continue
                        val p = Path().apply {
                            moveTo(s[0].first, s[0].second)
                            for (pt in s.drop(1)) lineTo(pt.first, pt.second)
                        }
                        drawPath(p, color = Color(0xFF1E3A8A), style = Stroke(width = 6f))
                    }
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(onClick = { strokes = emptyList(); activeStroke = emptyList() }) {
                    Text("Clear Pad")
                }
                Text("Angle: ${rotationDeg.toInt()}°", fontSize = 12.sp)
                Slider(value = rotationDeg, onValueChange = { rotationDeg = it }, valueRange = -45f..45f, modifier = Modifier.weight(1f))
            }

            OutlinedTextField(
                value = customName,
                onValueChange = { customName = it },
                label = { Text("Optional Name / Title Stamp") },
                modifier = Modifier.fillMaxWidth()
            )

            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = includeDate, onCheckedChange = { includeDate = it })
                Text("Include Today's Date Stamp")
            }

            Button(
                onClick = {
                    val target = currentItem ?: return@Button
                    scope.launch {
                        val bytes = withContext(Dispatchers.IO) {
                            PdfSignerEngine.stampSignatureOnPdf(
                                sourceFile = target.file,
                                targetPageIndex = 0,
                                strokes = strokes,
                                inkColor = AndroidColor.rgb(20, 50, 140),
                                normX = normX,
                                normY = normY,
                                widthRatio = 0.35f,
                                rotationDegrees = rotationDeg,
                                customStampText = customName,
                                includeDate = includeDate
                            )
                        }
                        onSaveSigned(bytes, target.title)
                    }
                },
                enabled = currentItem != null,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Stamp Signature & Save Signed PDF")
            }
        }
    }
}

@Composable
private fun OcrSection(
    items: List<PdfVaultItem>,
    onSaveSearchablePdf: (ByteArray, String) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val currentItem = items.firstOrNull()
    var pages by remember { mutableStateOf(listOf<OcrPageItem>()) }
    var isRunning by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }

    val filteredPages = remember(pages, searchQuery) {
        if (searchQuery.isBlank()) pages
        else pages.filter { it.recognizedText.contains(searchQuery, ignoreCase = true) }
    }

    LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Text("100% Offline On-Device OCR & Searchable PDF", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Button(
                onClick = {
                    val target = currentItem ?: return@Button
                    isRunning = true
                    scope.launch {
                        pages = withContext(Dispatchers.IO) {
                            OfflineOcrEngine.extractTextFromPdf(target.file)
                        }
                        isRunning = false
                    }
                },
                enabled = currentItem != null && !isRunning,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(if (isRunning) "Running On-Device ML Kit OCR..." else "Extract Copyable Text Now")
            }
        }

        if (pages.isNotEmpty()) {
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                    OutlinedButton(
                        onClick = {
                            val fullText = pages.joinToString("\n\n") { "--- Page ${it.pageNumber} ---\n${it.recognizedText}" }
                            val cb = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            cb.setPrimaryClip(ClipData.newPlainText("PurePDF OCR", fullText))
                        },
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("Copy All Text")
                    }

                    Button(
                        onClick = {
                            val target = currentItem ?: return@Button
                            scope.launch {
                                val searchableBytes = withContext(Dispatchers.IO) {
                                    OfflineOcrEngine.buildSearchablePdf(target.file, pages)
                                }
                                onSaveSearchablePdf(searchableBytes, target.title)
                            }
                        },
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("Save Searchable PDF")
                    }
                }

                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    label = { Text("Search inside extracted text...") },
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }

        items(filteredPages) { p ->
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("Page ${p.pageNumber}", fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(4.dp))
                    Text(p.recognizedText, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
                }
            }
        }
    }
}

private fun sharePdfFile(context: Context, item: PdfVaultItem) {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", item.file)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "application/pdf"
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "Share PDF"))
}
