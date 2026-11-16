package com.maitreerawat.purepdf.model

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.text.format.Formatter
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

data class PdfVaultItem(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val file: File,
    val byteSize: Long,
    val pageCount: Int,
    val badgeTag: String
) {
    fun formattedSize(context: Context): String = Formatter.formatFileSize(context, byteSize)
}

object PdfVaultManager {
    fun getVaultDir(context: Context): File {
        val dir = File(context.filesDir, "PurePDF_Vault")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    fun loadVaultItems(context: Context): List<PdfVaultItem> {
        val dir = getVaultDir(context)
        val files = dir.listFiles { f -> f.extension.equals("pdf", ignoreCase = true) }?.toList().orEmpty()
        if (files.isEmpty()) {
            createStarterSamplePdf(context)
        }
        val refreshed = dir.listFiles { f -> f.extension.equals("pdf", ignoreCase = true) }
            ?.sortedByDescending { it.lastModified() }
            .orEmpty()

        return refreshed.map { file ->
            val pages = countPages(file)
            val tag = when {
                file.name.contains("_Compressed", true) -> "Compressed"
                file.name.contains("_Signed", true) -> "Signed"
                file.name.contains("_Scanned", true) -> "Scanned"
                file.name.contains("_Merged", true) -> "Merged"
                file.name.contains("Sample", true) -> "Sample"
                else -> "Document"
            }
            PdfVaultItem(
                title = file.nameWithoutExtension,
                file = file,
                byteSize = file.length(),
                pageCount = pages,
                badgeTag = tag
            )
        }
    }

    fun savePdfBytes(context: Context, bytes: ByteArray, baseTitle: String, tag: String): File {
        val clean = baseTitle.replace(".pdf", "", ignoreCase = true).replace("[^a-zA-Z0-9_-]".toRegex(), "_")
        val file = File(getVaultDir(context), "${clean}_${tag}_${System.currentTimeMillis() / 1000}.pdf")
        FileOutputStream(file).use { it.write(bytes) }
        return file
    }

    fun countPages(file: File): Int {
        return try {
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
                PdfRenderer(pfd).use { it.pageCount }
            }
        } catch (e: Exception) {
            1
        }
    }

    private fun createStarterSamplePdf(context: Context) {
        val doc = PdfDocument()
        for (pageNum in 1..2) {
            val pageInfo = PdfDocument.PageInfo.Builder(612, 792, pageNum).create()
            val page = doc.startPage(pageInfo)
            val canvas: Canvas = page.canvas

            val headerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.rgb(15, 95, 86)
            }
            canvas.drawRect(36f, 36f, 576f, 104f, headerPaint)

            val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textSize = 18f
                isFakeBoldText = true
            }
            canvas.drawText("PurePDF Android — Sample Document (Page $pageNum of 2)", 52f, 76f, titlePaint)

            val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.DKGRAY
                textSize = 13f
            }
            val lines = listOf(
                "100% Free, Zero-Watermark, Zero-Ad, Offline PDF Studio for Android.",
                "• Smart PDF Size Reducer: Compress PDFs to <300 KB or <500 KB for strict web portals.",
                "• Watermark-Free Scanner: Magic Crisp B&W shadow removal & clean multi-page export.",
                "• Finger PDF Signer: Draw ink signatures, add date stamps, and flatten onto any page.",
                "• 100% Offline ML Kit OCR: Extract copyable text with zero cloud servers.",
                "",
                "Authorized Signature: ___________________________   Date: _______________"
            )
            var y = 148f
            for (line in lines) {
                canvas.drawText(line, 48f, y, bodyPaint)
                y += 26f
            }

            // High-color gradient block so PDF Size Reducer demonstrates real byte compression
            val gradPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = LinearGradient(
                    48f, 420f, 564f, 680f,
                    Color.rgb(20, 120, 110),
                    Color.rgb(35, 60, 130),
                    Shader.TileMode.CLAMP
                )
            }
            canvas.drawRect(48f, 420f, 564f, 680f, gradPaint)
            canvas.drawText("Embedded High-Res Banner #$pageNum (Test PDF Size Reducer!)", 72f, 555f, titlePaint)

            doc.finishPage(page)
        }
        val outFile = File(getVaultDir(context), "Welcome_PurePDF_Sample.pdf")
        FileOutputStream(outFile).use { doc.writeTo(it) }
        doc.close()
    }
}
