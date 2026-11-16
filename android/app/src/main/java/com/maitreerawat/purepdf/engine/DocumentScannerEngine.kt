package com.maitreerawat.purepdf.engine

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import java.io.ByteArrayOutputStream

enum class AndroidScanFilter(val label: String) {
    MAGIC_CRISP_BW("Magic Crisp B&W"),
    CLEAN_GRAYSCALE("Clean Grayscale"),
    ORIGINAL_COLOR("Original Color")
}

object DocumentScannerEngine {
    fun applyFilter(source: Bitmap, filter: AndroidScanFilter): Bitmap {
        if (filter == AndroidScanFilter.ORIGINAL_COLOR) return source
        val out = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)

        val satMatrix = ColorMatrix().apply { setSaturation(0f) }
        val contrast = if (filter == AndroidScanFilter.MAGIC_CRISP_BW) 1.55f else 1.18f
        val translate = (-0.5f * contrast + 0.5f) * 255f + (if (filter == AndroidScanFilter.MAGIC_CRISP_BW) 16f else 4f)

        val contrastMatrix = ColorMatrix(
            floatArrayOf(
                contrast, 0f, 0f, 0f, translate,
                0f, contrast, 0f, 0f, translate,
                0f, 0f, contrast, 0f, translate,
                0f, 0f, 0f, 1f, 0f
            )
        )
        satMatrix.postConcat(contrastMatrix)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            colorFilter = ColorMatrixColorFilter(satMatrix)
        }
        canvas.drawBitmap(source, 0f, 0f, paint)
        return out
    }

    fun buildWatermarkFreePdf(pages: List<Bitmap>, filter: AndroidScanFilter): ByteArray {
        val pdf = PdfDocument()
        val pageW = 612
        val pageH = 792
        val margin = 24f

        pages.forEachIndexed { idx, rawBmp ->
            val pageInfo = PdfDocument.PageInfo.Builder(pageW, pageH, idx + 1).create()
            val page = pdf.startPage(pageInfo)
            val canvas = page.canvas
            canvas.drawColor(Color.WHITE)

            val processed = applyFilter(rawBmp, filter)
            val availW = pageW - margin * 2
            val availH = pageH - margin * 2
            val aspect = processed.width.toFloat() / processed.height.coerceAtLeast(1).toFloat()

            val destRect = if (availW / availH > aspect) {
                val w = availH * aspect
                RectF(margin + (availW - w) / 2f, margin, margin + (availW + w) / 2f, margin + availH)
            } else {
                val h = availW / aspect
                RectF(margin, margin + (availH - h) / 2f, margin + availW, margin + (availH + h) / 2f)
            }

            canvas.drawBitmap(processed, null, destRect, Paint(Paint.FILTER_BITMAP_FLAG))
            pdf.finishPage(page)
        }

        val out = ByteArrayOutputStream()
        pdf.writeTo(out)
        pdf.close()
        return out.toByteArray()
    }
}
