package com.maitreerawat.purepdf.engine

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import java.io.ByteArrayOutputStream
import java.io.File

object PdfPageToolkitEngine {
    fun mergePdfs(files: List<File>): ByteArray {
        val outPdf = PdfDocument()
        var globalPageNum = 1

        for (file in files) {
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
                PdfRenderer(pfd).use { renderer ->
                    for (i in 0 until renderer.pageCount) {
                        renderer.openPage(i).use { page ->
                            val w = page.width
                            val h = page.height
                            val bmp = Bitmap.createBitmap(w * 2, h * 2, Bitmap.Config.ARGB_8888)
                            Canvas(bmp).drawColor(Color.WHITE)
                            page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)

                            val pageInfo = PdfDocument.PageInfo.Builder(w, h, globalPageNum++).create()
                            val newPage = outPdf.startPage(pageInfo)
                            newPage.canvas.drawBitmap(bmp, null, RectF(0f, 0f, w.toFloat(), h.toFloat()), Paint(Paint.FILTER_BITMAP_FLAG))
                            outPdf.finishPage(newPage)
                            bmp.recycle()
                        }
                    }
                }
            }
        }

        val out = ByteArrayOutputStream()
        outPdf.writeTo(out)
        outPdf.close()
        return out.toByteArray()
    }
}
