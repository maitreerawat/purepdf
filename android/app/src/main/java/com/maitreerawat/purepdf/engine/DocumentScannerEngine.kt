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

enum class AndroidScanLayoutMode(val label: String) {
    STANDARD_ONE_PER_PAGE("Standard (1 per Page)"),
    ID_CARD_TWO_UP("2-Sided ID Card (Front + Back on 1 Page)")
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

    fun buildWatermarkFreePdf(
        pages: List<Bitmap>,
        filter: AndroidScanFilter,
        layoutMode: AndroidScanLayoutMode = AndroidScanLayoutMode.STANDARD_ONE_PER_PAGE
    ): ByteArray {
        if (layoutMode == AndroidScanLayoutMode.ID_CARD_TWO_UP) {
            return buildIdCardTwoUpPdf(pages, filter)
        }

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
            drawAspectFit(canvas, processed, RectF(margin, margin, pageW - margin, pageH - margin))
            pdf.finishPage(page)
        }

        val out = ByteArrayOutputStream()
        pdf.writeTo(out)
        pdf.close()
        return out.toByteArray()
    }

    private fun buildIdCardTwoUpPdf(pages: List<Bitmap>, filter: AndroidScanFilter): ByteArray {
        val pdf = PdfDocument()
        val pageW = 612
        val pageH = 792
        var idx = 0
        var pageNum = 1

        while (idx < pages.size) {
            val pageInfo = PdfDocument.PageInfo.Builder(pageW, pageH, pageNum++).create()
            val page = pdf.startPage(pageInfo)
            val canvas = page.canvas
            canvas.drawColor(Color.WHITE)

            val topSlot = RectF(86f, 78f, 526f, 358f)
            val bottomSlot = RectF(86f, 424f, 526f, 704f)

            drawCardSlot(canvas, applyFilter(pages[idx], filter), topSlot, "FRONT SIDE")
            if (idx + 1 < pages.size) {
                drawCardSlot(canvas, applyFilter(pages[idx + 1], filter), bottomSlot, "BACK SIDE")
            }

            pdf.finishPage(page)
            idx += 2
        }

        val out = ByteArrayOutputStream()
        pdf.writeTo(out)
        pdf.close()
        return out.toByteArray()
    }

    private fun drawCardSlot(canvas: Canvas, bitmap: Bitmap, slot: RectF, label: String) {
        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.GRAY
            textSize = 10f
            isFakeBoldText = true
        }
        canvas.drawText(label, slot.left, slot.top - 8f, labelPaint)

        val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.LTGRAY
            style = Paint.Style.STROKE
            strokeWidth = 1.2f
        }
        canvas.drawRoundRect(slot, 12f, 12f, borderPaint)

        val inner = RectF(slot.left + 12f, slot.top + 12f, slot.right - 12f, slot.bottom - 12f)
        drawAspectFit(canvas, bitmap, inner)
    }

    private fun drawAspectFit(canvas: Canvas, bitmap: Bitmap, avail: RectF) {
        val availW = avail.width()
        val availH = avail.height()
        val aspect = bitmap.width.toFloat() / bitmap.height.coerceAtLeast(1).toFloat()

        val dest = if (availW / availH > aspect) {
            val w = availH * aspect
            RectF(avail.left + (availW - w) / 2f, avail.top, avail.left + (availW + w) / 2f, avail.bottom)
        } else {
            val h = availW / aspect
            RectF(avail.left, avail.top + (availH - h) / 2f, avail.right, avail.top + (availH + h) / 2f)
        }
        canvas.drawBitmap(bitmap, null, dest, Paint(Paint.FILTER_BITMAP_FLAG))
    }
}
