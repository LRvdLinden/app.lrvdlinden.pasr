package app.lrvdlinden.pasrzakelijk.core

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import android.util.LruCache
import java.io.ByteArrayOutputStream

/** Logo van de server (base64, PNG/JPEG) als afbeelding, en terug (zelfde regels als de iOS-app en het dashboard). */
object LogoImage {
    private val cache = LruCache<Int, Bitmap>(24)

    fun bitmap(base64: String?): Bitmap? {
        if (base64.isNullOrBlank()) return null
        val key = base64.hashCode()
        cache.get(key)?.let { return it }
        val raw = base64.substringAfterLast(",")
        val bytes = runCatching { Base64.decode(raw, Base64.DEFAULT) }.getOrNull() ?: return null
        val bmp = runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull() ?: return null
        cache.put(key, bmp)
        return bmp
    }

    /** Verkleint tot hoogstens 256 px en maakt er base64 van (PNG, of JPEG als PNG te groot is). */
    fun encode(image: Bitmap): String? {
        val maxSide = 256f
        val scale = minOf(maxSide / maxOf(image.width, 1), maxSide / maxOf(image.height, 1), 1f)
        val w = maxOf(1, Math.round(image.width * scale))
        val h = maxOf(1, Math.round(image.height * scale))
        val small = if (w == image.width && h == image.height) image else Bitmap.createScaledBitmap(image, w, h, true)
        val png = ByteArrayOutputStream().also { small.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        if (png.size <= 150_000) return Base64.encodeToString(png, Base64.NO_WRAP)
        for (q in listOf(85, 70, 50)) {
            // JPEG kent geen transparantie: op wit zetten
            val flat = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            android.graphics.Canvas(flat).apply { drawColor(android.graphics.Color.WHITE); drawBitmap(small, 0f, 0f, null) }
            val jpg = ByteArrayOutputStream().also { flat.compress(Bitmap.CompressFormat.JPEG, q, it) }.toByteArray()
            if (jpg.size <= 150_000) return Base64.encodeToString(jpg, Base64.NO_WRAP)
        }
        return null
    }
}
