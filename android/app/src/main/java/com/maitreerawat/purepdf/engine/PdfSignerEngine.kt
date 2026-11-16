package com.maitreerawat.purepdf.engine

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object PdfSignerEngine {
    fun stampSignatureOnPdf(
        sourceFile: File,
        targetPageIndex: Int,
        strokes: List<List<Pair<Float, Float>>>,
        inkColor: Int,
        normX: Float,
        normY: Float,
        widthRatio: Float,
        customStampText: String,
        includeDate: Boolean
    ): ByteArray {
        val outPdf = PdfDocument()

        ParcelFileDescriptor.open(sourceFile, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
            PdfRenderer(pfd).use { renderer ->
                for (i in 0 until renderer.pageCount) {
                    renderer.openPage(i).use { page ->
                        val w = page.width
                        val h = page.height
                        val bmp = Bitmap.createBitmap(w * 2, h * 2, Bitmap.Config.ARGB_8888)
                        Canvas(bmp).drawColor(Color.WHITE)
                        page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)

                        val pageInfo = PdfDocument.PageInfo.Builder(w, h, i + 1).create()
                        val newPage = outPdf.startPage(pageInfo)
                        val canvas = newPage.canvas
                        canvas.drawBitmap(bmp, null, RectF(0f, 0f, w.toFloat(), h.toFloat()), Paint(Paint.FILTER_BITMAP_FLAG))
                        bmp.recycle()

                        if (i == targetPageIndex) {
                            val cx = normX * w
                            val cy = normY * h
                            val sigW = w * widthRatio
                            val sigH = sigW * 0.45f

                            if (strokes.isNotEmpty()) {
                                val sigBmp = renderSignatureBitmap(strokes, 400, 180, inkColor)
                                val dest = RectF(cx - sigW / 2f, cy - sigH / 2f, cx + sigW / 2f, cy + sigH / 2f)
                                canvas.drawBitmap(sigBmp, null, dest, Paint(Paint.FILTER_BITMAP_FLAG))
                                sigBmp.recycle()
                            }

                            val stampParts = mutableListOf<String>()
                            if (customStampText.isNotBlank()) stampParts.add(customStampText.trim())
                            if (includeDate) {
                                val df = SimpleDateFormat("MMM d, yyyy", Locale.US)
                                stampParts.add("Signed: ${df.format(Date())}")
                            }
                            if (stampParts.isNotEmpty()) {
                                val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                                    color = inkColor
                                    textSize = 11.5f
                                    isFakeBoldText = true
                                }
                                val line = stampParts.joinToString("  •  ")
                                val tw = textPaint.measureText(line)
                                canvas.drawText(line, (cx - tw / 2f).coerceIn(20f, w - tw - 20f), cy + sigH / 2f + 16f, textPaint)
                            }
                        }
                        outPdf.finishPage(newPage)
                    }
                }
            }
        }

        val out = ByteArrayOutputStream()
        outPdf.writeTo(out)
        outPdf.close()
        return out.toByteArray()
    }

    private fun renderSignatureBitmap(
        strokes: List<List<Pair<Float, Float>>>,
        width: Int,
        height: Int,
        inkColor: Int
    ): Bitmap {
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = inkColor
            style = Paint.Style.STROKE
            strokeWidth = 5f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        for (stroke in strokes) {
            if (stroke.size < 2) continue
            val path = Path()
            path.moveTo(stroke[0].first, stroke[0].second)
            for (pt in stroke.drop(1)) {
                path.lineTo(pt.first, pt.second)
            }
            canvas.drawPath(path, paint)
        }
        return bmp
    }
}
