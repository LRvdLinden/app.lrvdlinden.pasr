package app.lrvdlinden.pasrzakelijk.ui.cards

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.compose.ui.graphics.toArgb
import androidx.core.content.FileProvider
import app.lrvdlinden.pasrzakelijk.R
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.core.LogoImage
import app.lrvdlinden.pasrzakelijk.data.Business
import app.lrvdlinden.pasrzakelijk.data.BusinessCard
import app.lrvdlinden.pasrzakelijk.ui.hexColor
import app.lrvdlinden.pasrzakelijk.ui.onCard
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/** A4-flyer voor op de toonbank (zelfde opzet als pasr.nl/zakelijk/flyer en de iOS-app), als PDF. */
object Flyer {
    private const val W = 595
    private const val H = 842

    fun makePDF(context: Context, business: Business, card: BusinessCard): File? = runCatching {
        val safe = card.name.replace(Regex("[^A-Za-z0-9 _-]"), "").ifBlank { "Pasr" }
        val dir = File(context.cacheDir, "share").apply { mkdirs() }
        val file = File(dir, "Flyer $safe.pdf")
        val doc = PdfDocument()
        val page = doc.startPage(PdfDocument.PageInfo.Builder(W, H, 1).create())
        draw(context, page.canvas, business, card)
        doc.finishPage(page)
        FileOutputStream(file).use { doc.writeTo(it) }
        doc.close()
        file
    }.getOrNull()

    private fun paint(size: Float, bold: Boolean = false, color: Int = 0xFF17162A.toInt(), align: Paint.Align = Paint.Align.CENTER) =
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size; this.color = color; textAlign = align
            typeface = Typeface.create(Typeface.SANS_SERIF, if (bold) Typeface.BOLD else Typeface.NORMAL)
        }

    /** Tekst gecentreerd met regelafbreking; geeft de nieuwe y terug. */
    private fun centered(canvas: Canvas, text: String, y: Float, p: TextPaint, width: Int = W - 88): Float {
        val tp = TextPaint(p).apply { textAlign = Paint.Align.LEFT }
        val layout = StaticLayout.Builder.obtain(text, 0, text.length, tp, width).setAlignment(Layout.Alignment.ALIGN_CENTER).build()
        canvas.save(); canvas.translate(((W - width) / 2).toFloat(), y); layout.draw(canvas); canvas.restore()
        return y + layout.height
    }

    fun draw(context: Context, c: Canvas, business: Business, card: BusinessCard) {
        c.drawColor(android.graphics.Color.WHITE)
        var y = 44f
        y = centered(c, L("DIGITALE STEMPELKAART"), y, paint(13f, true, 0xFF6A5CFF.toInt()).apply { letterSpacing = 0.15f }) + 14
        y = centered(c, L("Spaar bij %@", business.name), y, paint(34f, true)) + 10
        y = centered(c, L("%lld stempels = %@", card.stampsTotal, card.reward), y, paint(19f, true)) + 18

        // de stempelkaart
        val cw = 330f
        val ch = 190f
        val left = (W - cw) / 2
        val rect = RectF(left, y, left + cw, y + ch)
        val base = hexColor(card.color).toArgb()
        val fg = (card.textColor?.let { hexColor(it) } ?: onCard(card.color)).toArgb()
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(rect.left, rect.top, rect.right, rect.bottom, base, (base and 0x00FFFFFF) or (0xD1 shl 24), Shader.TileMode.CLAMP)
        }
        c.drawRoundRect(rect, 20f, 20f, fill)
        val logo = LogoImage.bitmap(card.logo)
        val logoRect = RectF(left + 16, y + 16, left + 54, y + 54)
        if (logo != null) {
            c.drawRoundRect(logoRect, 9f, 9f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE })
            c.drawBitmap(logo, null, logoRect, Paint(Paint.FILTER_BITMAP_FLAG))
        } else {
            c.drawRoundRect(logoRect, 9f, 9f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = (fg and 0x00FFFFFF) or (0x2E shl 24) })
            val initial = business.name.trim().firstOrNull()?.uppercase() ?: "P"
            c.drawText(initial, logoRect.centerX(), logoRect.centerY() + 7, paint(19f, true, fg))
        }
        c.drawText(card.name, left + 64, y + 33, paint(16f, true, fg, Paint.Align.LEFT))
        c.drawText(business.name, left + 64, y + 50, paint(11f, false, fg, Paint.Align.LEFT).apply { alpha = 205 })
        val filled = (card.stampsTotal + 1) / 2
        c.drawText("$filled/${card.stampsTotal}", rect.right - 16, y + 38, paint(14f, true, fg, Paint.Align.RIGHT))
        val perRow = if (card.stampsTotal <= 10) 5 else if (card.stampsTotal <= 18) 6 else 8
        val rows = (card.stampsTotal + perRow - 1) / perRow
        val gap = 8f
        val dot = minOf(30f, (cw - 32 - gap * (perRow - 1)) / perRow, (ch - 92 - gap * (rows - 1)) / rows)
        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 1.5f; color = (fg and 0x00FFFFFF) or (0x8C shl 24) }
        val dashed = Paint(ring).apply { pathEffect = DashPathEffect(floatArrayOf(3f, 3f), 0f) }
        val solid = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = fg }
        for (i in 0 until card.stampsTotal) {
            val cx = left + 16 + (i % perRow) * (dot + gap) + dot / 2
            val cy = y + 70 + (i / perRow) * (dot + gap) + dot / 2
            if (i < filled) { c.drawCircle(cx, cy, dot / 2 - 1, ring); c.drawCircle(cx, cy, dot / 2 - 3, solid) } else c.drawCircle(cx, cy, dot / 2 - 1, dashed)
        }
        c.drawText(card.reward, left + 16, rect.bottom - 14, paint(11f, true, fg, Paint.Align.LEFT))
        y = rect.bottom + 22

        QrCode.bitmap(card.joinURL, 420)?.let { qr -> c.drawBitmap(qr, null, RectF((W - 210) / 2f, y, (W + 210) / 2f, y + 210), null) }
        y += 222
        y = centered(c, L("Scan met je camera"), y, paint(18f, true)) + 14
        val steps = listOf(
            L("1. Scan de QR-code met de camera van je telefoon."),
            L("2. Bewaar de kaart in de gratis app Pasr, of gebruik hem in je browser."),
            L("3. Laat bij elke aankoop je kaart scannen voor een stempel."),
        )
        for (s in steps) { c.drawText(s, 90f, y + 12, paint(13f, false, align = Paint.Align.LEFT)); y += 20 }

        // onderaan: icoon + pasr.nl
        val icon = BitmapFactory.decodeResource(context.resources, R.drawable.app_icon_display)
        val by = H - 60f
        val label = "pasr.nl"
        val lp = paint(13f, true, align = Paint.Align.LEFT)
        val total = 22 + 8 + lp.measureText(label)
        val bx = (W - total) / 2
        if (icon != null) c.drawBitmap(icon, null, RectF(bx, by, bx + 22, by + 22), Paint(Paint.FILTER_BITMAP_FLAG))
        c.drawText(label, bx + 30, by + 16, lp)
    }

    fun share(context: Context, file: File) {
        val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        runCatching { context.startActivity(Intent.createChooser(send, file.nameWithoutExtension).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    /** Afdrukken via de printdienst van Android. */
    fun print(context: Context, file: File) {
        val manager = context.getSystemService(Context.PRINT_SERVICE) as? PrintManager ?: return
        val adapter = object : PrintDocumentAdapter() {
            override fun onLayout(old: PrintAttributes?, new: PrintAttributes?, cancel: CancellationSignal?, callback: LayoutResultCallback, extras: Bundle?) {
                if (cancel?.isCanceled == true) { callback.onLayoutCancelled(); return }
                callback.onLayoutFinished(PrintDocumentInfo.Builder(file.name).setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT).setPageCount(1).build(), true)
            }

            override fun onWrite(pages: Array<out PageRange>?, destination: ParcelFileDescriptor, cancel: CancellationSignal?, callback: WriteResultCallback) {
                runCatching {
                    FileInputStream(file).use { input -> FileOutputStream(destination.fileDescriptor).use { input.copyTo(it) } }
                    callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                }.onFailure { callback.onWriteFailed(it.message) }
            }
        }
        runCatching {
            manager.print(file.nameWithoutExtension, adapter, PrintAttributes.Builder().setMediaSize(PrintAttributes.MediaSize.ISO_A4).build())
        }
    }
}
