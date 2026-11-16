package com.maitreerawat.purepdf.engine

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import java.io.ByteArrayOutputStream
import java.io.File

enum class AndroidCompressionPreset(
    val label: String,
    val subtitle: String,
    val defaultDpi: Int,
    val defaultQuality: Int
) {
    STRICT_PORTAL("Strict Portal (<300 KB)", "78 DPI • Maximum compression for government/visa portals", 78, 32),
    STANDARD_UPLOAD("Standard Upload (<500 KB)", "110 DPI • Crisp text at ~75% smaller size", 110, 48),
    BALANCED_EMAIL("Balanced Email (<1.5 MB)", "145 DPI • Ideal balance of sharpness and compact size", 145, 65),
    HIGH_QUALITY("High Quality (200 DPI)", "200 DPI • Preserves fine detail while trimming bloat", 200, 82)
}

data class AndroidCompressionResult(
    val pdfBytes: ByteArray,
    val originalBytes: Long,
    val compressedBytes: Long,
    val pageCount: Int
) {
    val reductionPercent: Double
        get() = if (originalBytes > 0) ((originalBytes - compressedBytes).toDouble() / originalBytes) * 100.0 else 0.0
}

object PdfCompressorEngine {
    fun compressPdf(
        sourceFile: File,
        targetDpi: Int,
        jpegQuality: Int,
        grayscale: Boolean
    ): AndroidCompressionResult {
        val originalLength = sourceFile.length()
        val scale = (targetDpi.coerceIn(50, 260) / 72f)
        val quality = jpegQuality.coerceIn(15, 95)

        val outPdf = PdfDocument()
        var totalPages = 0

        ParcelFileDescriptor.open(sourceFile, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
            PdfRenderer(pfd).use { renderer ->
                totalPages = renderer.pageCount
                for (i in 0 until renderer.pageCount) {
                    renderer.openPage(i).use { page ->
                        val pageW = page.width
                        val pageH = page.height
                        val rasterW = (pageW * scale).toInt().coerceAtLeast(1)
                        val rasterH = (pageH * scale).toInt().coerceAtLeast(1)

                        var bitmap = Bitmap.createBitmap(rasterW, rasterH, Bitmap.Config.ARGB_8888)
                        val canvas = Canvas(bitmap)
                        canvas.drawColor(Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)

                        if (grayscale) {
                            val grayBmp = Bitmap.createBitmap(rasterW, rasterH, Bitmap.Config.ARGB_8888)
                            val gCanvas = Canvas(grayBmp)
                            val cm = ColorMatrix().apply { setSaturation(0f) }
                            val paint = Paint().apply { colorFilter = ColorMatrixColorFilter(cm) }
                            gCanvas.drawBitmap(bitmap, 0f, 0f, paint)
                            bitmap.recycle()
                            bitmap = grayBmp
                        }

                        val jpegStream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.JPEG, quality, jpegStream)
                        bitmap.recycle()

                        val jpegBytes = jpegStream.toByteArray()
                        val compressedBmp = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)

                        val newPageInfo = PdfDocument.PageInfo.Builder(pageW, pageH, i + 1).create()
                        val newPage = outPdf.startPage(newPageInfo)
                        newPage.canvas.drawBitmap(
                            compressedBmp,
                            null,
                            Rect(0, 0, pageW, pageH),
                            Paint(Paint.FILTER_BITMAP_FLAG)
                        )
                        outPdf.finishPage(newPage)
                        compressedBmp.recycle()
                    }
                }
            }
        }

        val outStream = ByteArrayOutputStream()
        outPdf.writeTo(outStream)
        outPdf.close()
        val finalBytes = outStream.toByteArray()

        return AndroidCompressionResult(
            pdfBytes = finalBytes,
            originalBytes = originalLength,
            compressedBytes = finalBytes.size.toLong(),
            pageCount = totalPages
        )
    }
}
