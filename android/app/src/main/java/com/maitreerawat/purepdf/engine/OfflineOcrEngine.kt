package com.maitreerawat.purepdf.engine

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.tasks.await
import java.io.ByteArrayOutputStream
import java.io.File

data class OcrPageItem(
    val pageNumber: Int,
    val recognizedText: String
)

object OfflineOcrEngine {
    suspend fun extractTextFromPdf(file: File): List<OcrPageItem> {
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val outputs = mutableListOf<OcrPageItem>()

        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
            PdfRenderer(pfd).use { renderer ->
                for (i in 0 until renderer.pageCount) {
                    val bmp = renderer.openPage(i).use { page ->
                        val b = Bitmap.createBitmap(page.width * 2, page.height * 2, Bitmap.Config.ARGB_8888)
                        Canvas(b).drawColor(Color.WHITE)
                        page.render(b, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        b
                    }
                    val inputImage = InputImage.fromBitmap(bmp, 0)
                    val visionText = recognizer.process(inputImage).await()
                    bmp.recycle()

                    outputs.add(
                        OcrPageItem(
                            pageNumber = i + 1,
                            recognizedText = visionText.text.ifBlank { "No text detected on this page." }
                        )
                    )
                }
            }
        }
        return outputs
    }

    /// Generates a Searchable PDF by embedding the recognized OCR text layer invisibly underneath each visual page.
    fun buildSearchablePdf(sourceFile: File, ocrPages: List<OcrPageItem>): ByteArray {
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

                        // 1. Invisible searchable text layer
                        if (i < ocrPages.size) {
                            val invisiblePaint = Paint().apply {
                                color = Color.TRANSPARENT
                                textSize = 10f
                            }
                            var ty = 48f
                            for (line in ocrPages[i].recognizedText.lines()) {
                                canvas.drawText(line, 36f, ty, invisiblePaint)
                                ty += 14f
                            }
                        }

                        // 2. Visual page on top
                        canvas.drawBitmap(bmp, null, RectF(0f, 0f, w.toFloat(), h.toFloat()), Paint(Paint.FILTER_BITMAP_FLAG))
                        bmp.recycle()
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
}
