package app.lrvdlinden.pasrzakelijk.ui.tickets

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.core.LogoImage
import app.lrvdlinden.pasrzakelijk.data.MemberCard
import app.lrvdlinden.pasrzakelijk.data.TkFormat
import app.lrvdlinden.pasrzakelijk.data.TkText
import app.lrvdlinden.pasrzakelijk.ui.BigButton
import app.lrvdlinden.pasrzakelijk.ui.FullSheet
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.cards.QrCode
import app.lrvdlinden.pasrzakelijk.ui.cards.WebsiteBadgeSheet
import app.lrvdlinden.pasrzakelijk.ui.hexColor
import app.lrvdlinden.pasrzakelijk.ui.onCard
import app.lrvdlinden.pasrzakelijk.ui.shareText
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
import java.util.Calendar
import java.util.Date

/** Barcode als afbeelding: QR, Code 128 of EAN-13 (zxing). */
object Barcode {
    fun bitmap(text: String, type: String): Bitmap? = when (type) {
        "qr" -> QrCode.bitmap(text, 480)
        "ean13" -> linear(text, BarcodeFormat.EAN_13) ?: linear(text, BarcodeFormat.CODE_128)
        else -> linear(text, BarcodeFormat.CODE_128)
    }

    private fun linear(text: String, format: BarcodeFormat): Bitmap? = runCatching {
        val m = MultiFormatWriter().encode(text, format, 600, 160)
        val pixels = IntArray(m.width * m.height) { i -> if (m.get(i % m.width, i / m.width)) android.graphics.Color.BLACK else android.graphics.Color.WHITE }
        Bitmap.createBitmap(pixels, m.width, m.height, Bitmap.Config.ARGB_8888)
    }.getOrNull()
}

/** Statuspil: Online, Concept, Geannuleerd, Gearchiveerd. */
@Composable
fun TkStatusPill(status: String) {
    val (label, color) = when (status) {
        "published" -> L("Online") to Pz.mint
        "cancelled" -> L("Geannuleerd") to Pz.coral
        "archived" -> L("Gearchiveerd") to Pz.muted
        else -> L("Concept") to Pz.muted
    }
    Pill(label, color)
}

@Composable
fun Pill(label: String, color: Color) {
    Text(label, color = color, fontSize = 12.sp, fontWeight = FontWeight.Bold,
        modifier = Modifier.clip(CircleShape).background(color.copy(alpha = 0.14f)).padding(horizontal = 8.dp, vertical = 3.dp))
}

/** Regel met titel en schakelaar. */
@Composable
fun ToggleLine(title: String, checked: Boolean, subtitle: String? = null, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(enabled = enabled) { onChange(!checked) }.padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, color = Pz.text, fontSize = 17.sp)
            if (subtitle != null) Text(subtitle, color = Pz.muted, fontSize = 13.sp)
        }
        Switch(checked, onChange, enabled = enabled, colors = SwitchDefaults.colors(checkedTrackColor = Pz.mint))
    }
}

/** Regel met een getal en - / + (zoals Stepper op iOS). */
@Composable
fun StepperLine(title: String, value: Int, range: IntRange, step: Int = 1, suffix: String = "", onChange: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Pz.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
        IconButton(onClick = { onChange(maxOf(range.first, value - step)) }, enabled = value > range.first) {
            Icon(Icons.Filled.Remove, L("Minder"), tint = Pz.accent)
        }
        Text("$value$suffix", color = Pz.text, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
        IconButton(onClick = { onChange(minOf(range.last, value + step)) }, enabled = value < range.last) {
            Icon(Icons.Filled.Add, L("Meer"), tint = Pz.accent)
        }
    }
}

/** Regel met datum en/of tijd; tikken opent de kiezer van Android. */
@Composable
fun DateTimeLine(title: String, value: Date, withDate: Boolean = true, withTime: Boolean = true, onChange: (Date) -> Unit) {
    val context = LocalContext.current
    val text = when {
        withDate && withTime -> TkText.dayMonth(value) + " " + TkText.clock(value)
        withDate -> TkText.dayMonth(value) + " " + Calendar.getInstance(TkFormat.zone).apply { time = value }.get(Calendar.YEAR)
        else -> TkText.clock(value)
    }
    Row(Modifier.fillMaxWidth().clickable { pickDateTime(context, value, withDate, withTime, onChange) }.padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Pz.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
        Text(text, color = Pz.accent, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
    }
}

fun pickDateTime(context: Context, value: Date, withDate: Boolean, withTime: Boolean, onChange: (Date) -> Unit) {
    val c = Calendar.getInstance(TkFormat.zone).apply { time = value }
    fun time() {
        TimePickerDialog(context, { _, h, m ->
            c.set(Calendar.HOUR_OF_DAY, h); c.set(Calendar.MINUTE, m); c.set(Calendar.SECOND, 0); c.set(Calendar.MILLISECOND, 0)
            onChange(c.time)
        }, c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE), true).show()
    }
    if (withDate) {
        DatePickerDialog(context, { _, y, mo, d ->
            c.set(Calendar.YEAR, y); c.set(Calendar.MONTH, mo); c.set(Calendar.DAY_OF_MONTH, d)
            if (withTime) time() else onChange(c.time)
        }, c.get(Calendar.YEAR), c.get(Calendar.MONTH), c.get(Calendar.DAY_OF_MONTH)).show()
    } else time()
}

/** Kleuren: "kleur van je zaak" (null) en de vaste kleuren. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TkColorRow(selected: String?, allowDefault: Boolean = true, onSelect: (String?) -> Unit) {
    FlowRow(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (allowDefault) {
            Box(Modifier.size(36.dp).clip(CircleShape).background(Pz.gradient)
                .border(if (selected == null) 3.dp else 0.dp, Pz.text, CircleShape).clickable { onSelect(null) },
                contentAlignment = Alignment.Center) {
                Text("B", color = Color.White, fontWeight = FontWeight.Bold)
            }
        }
        for (hex in Pz.swatches) {
            Box(Modifier.size(36.dp).clip(CircleShape).background(hexColor(hex))
                .border(if (selected?.uppercase() == hex) 3.dp else 0.dp, Pz.text, CircleShape).clickable { onSelect(hex) })
        }
    }
}

/** Delen van een event of klantenkaart: QR, link en de knop "Voeg toe aan Pasr" voor de website. */
@Composable
fun TkShareSheet(title: String, url: String, intro: String, badgeIntro: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var badge by remember { mutableStateOf(false) }
    val qr = remember(url) { QrCode.bitmap(url) }
    FullSheet(onDismiss, title, cancelText = null, confirmText = L("Klaar"), onConfirm = onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(intro, color = Pz.muted)
            if (qr != null) {
                Image(qr.asImageBitmap(), L("QR-code met de link"), filterQuality = FilterQuality.None,
                    modifier = Modifier.widthIn(max = 240.dp).fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Color.White).padding(16.dp))
            }
            Text(url, color = Pz.muted, fontFamily = FontFamily.Monospace, fontSize = 13.sp)
            BigButton(L("Link delen"), { context.shareText(url, title) }, icon = Icons.Filled.Share)
            BigButton(L("Kopieer link"), {
                (context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager)?.setPrimaryClip(ClipData.newPlainText(title, url))
            }, icon = Icons.Filled.ContentCopy, color = Pz.card2, foreground = Pz.text)
            BigButton(L("Knop voor je website"), { badge = true }, color = Pz.mint, foreground = Color.Black)
        }
    }
    if (badge) WebsiteBadgeSheet(url, title, badgeIntro) { badge = false }
}

/** Klantenkaart zoals de klant hem ziet: naam, korting, spaarstand en barcode. */
@Composable
fun MemberCardPreview(card: MemberCard, business: String, number: String? = null, memberName: String? = null) {
    val bg = hexColor(card.color)
    val fg = onCard(card.color)
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(bg).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            val logo = remember(card.logo) { LogoImage.bitmap(card.logo) }
            if (logo != null) {
                Image(logo.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.size(34.dp).clip(RoundedCornerShape(9.dp)))
            } else {
                Box(Modifier.size(34.dp).clip(RoundedCornerShape(9.dp)).background(fg.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
                    Text(business.take(1).uppercase(), color = fg, fontWeight = FontWeight.Black)
                }
            }
            Column(Modifier.weight(1f)) {
                Text(card.name.ifBlank { L("Naam van de kaart") }, color = fg, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(business, color = fg.copy(alpha = 0.8f), fontSize = 12.sp, maxLines = 1)
            }
            Text(L("KLANTENKAART"), color = fg.copy(alpha = 0.85f), fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
        }
        val line = when {
            card.discountNow != null -> L("Nu %@%% korting", TkFormat.percent(card.discountNow.percent))
            card.goals.fixedEnabled -> L("%@%% korting voor leden", TkFormat.percent(card.goals.fixedPercent))
            card.goals.periods.isNotEmpty() -> L("%@%% korting", TkFormat.percent(card.goals.periods[0].percent)) + " · " + card.goals.periods[0].summary()
            else -> null
        }
        if (line != null) {
            Text(line, color = bg, fontWeight = FontWeight.Bold, fontSize = 14.sp,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Color.White).padding(horizontal = 10.dp, vertical = 6.dp))
        }
        if (card.goals.savingEnabled) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(L("Spaarstand"), color = fg, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                LinearProgressIndicator(progress = { 0.6f }, modifier = Modifier.weight(1f), color = fg, trackColor = fg.copy(alpha = 0.25f))
                Text("${card.goals.savingTarget * 6 / 10}/${card.goals.savingTarget}", color = fg, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
        }
        val text = number ?: card.sampleNumber
        val code = remember(text, card.barcodeType) { Barcode.bitmap(text, card.barcodeType) }
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Color.White).padding(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            if (code != null) {
                Image(code.asImageBitmap(), null, filterQuality = FilterQuality.None, contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxWidth().heightIn(max = if (card.barcodeType == "qr") 130.dp else 70.dp))
            }
            Text(text, color = Color.Black, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
        }
        if (memberName != null) Text(L("Lid: %@", memberName), color = fg, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    }
}
