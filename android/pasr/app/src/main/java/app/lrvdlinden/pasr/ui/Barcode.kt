package app.lrvdlinden.pasr.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import app.lrvdlinden.pasr.data.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatWriter
import com.google.zxing.common.BitMatrix

/** Tekent barcodes en QR-codes met ZXing (scherp, zwart op wit). */
object BarcodeRender {
    private fun zx(f: BarcodeFormat) = when (f) {
        BarcodeFormat.EAN13 -> com.google.zxing.BarcodeFormat.EAN_13
        BarcodeFormat.EAN8 -> com.google.zxing.BarcodeFormat.EAN_8
        BarcodeFormat.UPCA -> com.google.zxing.BarcodeFormat.UPC_A
        BarcodeFormat.CODE128 -> com.google.zxing.BarcodeFormat.CODE_128
        BarcodeFormat.CODE39 -> com.google.zxing.BarcodeFormat.CODE_39
        BarcodeFormat.ITF -> com.google.zxing.BarcodeFormat.ITF
        BarcodeFormat.QR -> com.google.zxing.BarcodeFormat.QR_CODE
        BarcodeFormat.PDF417 -> com.google.zxing.BarcodeFormat.PDF_417
        BarcodeFormat.AZTEC -> com.google.zxing.BarcodeFormat.AZTEC
    }

    fun bitmap(value: String, format: BarcodeFormat): Bitmap? {
        if (value.isEmpty()) return null
        val hints = mapOf(EncodeHintType.MARGIN to if (format.linear) 4 else 1, EncodeHintType.CHARACTER_SET to "UTF-8")
        val w = if (format.linear) 800 else 600
        val h = when { format.linear -> 260; format == BarcodeFormat.PDF417 -> 240; else -> 600 }
        var m: BitMatrix? = runCatching { MultiFormatWriter().encode(value, zx(format), w, h, hints) }.getOrNull()
        if (m == null && format.linear) {
            // past de waarde niet bij de soort (bijv. een verkeerd controlecijfer): dan Code 128
            m = runCatching { MultiFormatWriter().encode(value, com.google.zxing.BarcodeFormat.CODE_128, w, h, hints) }.getOrNull()
        }
        if (m == null) return null
        val pixels = IntArray(m.width * m.height)
        for (y in 0 until m.height) {
            val off = y * m.width
            for (x in 0 until m.width) pixels[off + x] = if (m[x, y]) 0xFF000000.toInt() else 0xFFFFFFFF.toInt()
        }
        return Bitmap.createBitmap(pixels, m.width, m.height, Bitmap.Config.ARGB_8888)
    }
}

@Composable
fun BarcodeImage(value: String, format: BarcodeFormat, modifier: Modifier = Modifier) {
    val bmp = remember(value, format) { BarcodeRender.bitmap(value, format) }
    if (bmp == null) {
        Box(modifier.fillMaxWidth().aspectRatio(3f), contentAlignment = Alignment.Center) {
            Text("Deze code kan niet als ${format.title} worden getekend.", color = Color.Gray)
        }
        return
    }
    Image(
        bmp.asImageBitmap(), contentDescription = "Barcode $value",
        modifier = modifier.fillMaxWidth().aspectRatio(bmp.width.toFloat() / bmp.height),
        contentScale = ContentScale.FillBounds, filterQuality = FilterQuality.None,
    )
}
