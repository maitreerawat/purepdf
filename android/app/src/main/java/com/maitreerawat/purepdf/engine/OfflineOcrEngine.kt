package com.maitreerawat.purepdf.engine

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.tasks.await
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
}
