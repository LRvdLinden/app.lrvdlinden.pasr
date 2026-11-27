package app.lrvdlinden.pasrzakelijk.ui.cards

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Share
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import app.lrvdlinden.pasrzakelijk.R
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.core.Prefs
import app.lrvdlinden.pasrzakelijk.data.BusinessCard
import app.lrvdlinden.pasrzakelijk.ui.BigButton
import app.lrvdlinden.pasrzakelijk.ui.FullSheet
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.shareText
import java.io.File

/**
 * "Knop voor je website": de knop "Voeg toe aan Pasr" voor een stempelkaart (https://pasr.nl/add/k/<id>).
 * Kies zwart, wit of nachtblauw en groot of compact; deel de HTML-code, de link, de QR-code of de knop als PNG.
 * De knop is altijd Nederlands (badges uit tools/make_badges.py, ook op pasr.nl/badge/nl/). Zelfde als iOS.
 */
@Composable
fun WebsiteBadgeSheet(card: BusinessCard, onDismiss: () -> Unit) =
    WebsiteBadgeSheet("https://pasr.nl/add/k/${card.id.lowercase()}", card.name,
        L("Klanten zetten je stempelkaart met één tik in Pasr. Zonder Pasr opent pasr.nl met de downloadknoppen."), onDismiss)

/** Zelfde knop voor een event (/add/e/<id>) of klantenkaart (/add/m/<id>). */
@Composable
fun WebsiteBadgeSheet(url: String, name: String, intro: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var theme by remember { mutableStateOf(Prefs.string("badge.theme", "zwart")) }
    var size by remember { mutableStateOf(Prefs.string("badge.size", "groot")) }
    var copied by remember { mutableStateOf(false) }
    val file = theme + if (size == "compact") "-compact" else ""
    val height = if (size == "compact") 38 else 52
    val snippet = "<a href=\"$url\">\n  <img src=\"https://pasr.nl/badge/nl/$file.svg\"\n       alt=\"Voeg toe aan Pasr\" height=\"$height\">\n</a>"
    val badge = badgeRes(file)
    val qr = remember(url) { QrCode.bitmap(url) }

    FullSheet(onDismiss, L("Knop voor je website"), cancelText = null, confirmText = L("Klaar"), onConfirm = onDismiss) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(intro, color = Pz.muted)
            Choice(L("Kleur"), listOf("zwart" to L("Zwart"), "wit" to L("Wit"), "nachtblauw" to L("Nachtblauw")), theme) {
                theme = it; copied = false; Prefs.putString("badge.theme", it)
            }
            Choice(L("Formaat"), listOf("groot" to L("Groot"), "compact" to L("Compact")), size) {
                size = it; copied = false; Prefs.putString("badge.size", it)
            }
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).border(1.dp, Pz.line, RoundedCornerShape(16.dp))) {
                for (bg in listOf(Color.White, Color(0xFF17162A))) {
                    Box(Modifier.weight(1f).heightIn(min = 96.dp).background(bg), contentAlignment = Alignment.Center) {
                        Image(painterResource(badge), L("Voorbeeld van de knop Voeg toe aan Pasr"), Modifier.height(height.dp))
                    }
                }
            }
            Text(L("Zet deze code op je website"), fontWeight = FontWeight.Bold)
            Text(snippet, color = Color(0xFFE9E7FF), fontFamily = FontFamily.Monospace, fontSize = 12.sp,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Color(0xFF17162A)).padding(14.dp))
            BigButton(if (copied) L("Gekopieerd") else L("Kopieer HTML-code"), {
                (context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager)
                    ?.setPrimaryClip(ClipData.newPlainText("Voeg toe aan Pasr", snippet))
                copied = true
            }, icon = Icons.Filled.ContentCopy)
            BigButton(L("Deel HTML-code"), { context.shareText(snippet, name) }, icon = Icons.Filled.Share, color = Pz.card2, foreground = Pz.text)
            Text(L("Link"), fontWeight = FontWeight.Bold)
            Text(url, color = Pz.muted, fontFamily = FontFamily.Monospace, fontSize = 13.sp)
            BigButton(L("Link delen"), { context.shareText(url, name) }, icon = Icons.Filled.Share, color = Pz.mint, foreground = Color.Black)
            Text(L("QR-code voor toonbank en kassabon"), fontWeight = FontWeight.Bold)
            if (qr != null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Image(qr.asImageBitmap(), L("QR-code met de link"), filterQuality = FilterQuality.None,
                        modifier = Modifier.size(132.dp).clip(RoundedCornerShape(14.dp)).background(Color.White).padding(8.dp))
                    Text(L("Scannen met de camera opent dezelfde link: met Pasr meteen Toevoegen aan Pasr?, anders pasr.nl."), color = Pz.muted, fontSize = 13.sp)
                }
                BigButton(L("Deel QR-code"), { sharePng(context, qr, "pasr-qr") }, icon = Icons.Filled.Share, color = Pz.card2, foreground = Pz.text)
            }
            BigButton(L("Knop als afbeelding (PNG)"), {
                val bmp = android.graphics.BitmapFactory.decodeResource(context.resources, badge)
                if (bmp != null) sharePng(context, bmp, "voeg-toe-aan-pasr-$file")
            }, icon = Icons.Filled.Share, color = Pz.card2, foreground = Pz.text)
        }
    }
}

@Composable
private fun Choice(label: String, options: List<Pair<String, String>>, selected: String, onSelect: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, color = Pz.muted, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Row(Modifier.clip(RoundedCornerShape(12.dp)).background(Pz.card2).padding(3.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            for ((value, title) in options) {
                val on = value == selected
                Box(
                    Modifier.clip(RoundedCornerShape(9.dp)).background(if (on) Pz.card else Color.Transparent)
                        .clickable { onSelect(value) }.padding(horizontal = 14.dp, vertical = 8.dp),
                ) { Text(title, fontWeight = if (on) FontWeight.Bold else FontWeight.Medium, color = Pz.text) }
            }
        }
    }
}

private fun badgeRes(file: String): Int = when (file) {
    "wit" -> R.drawable.pasr_badge_wit
    "wit-compact" -> R.drawable.pasr_badge_wit_compact
    "nachtblauw" -> R.drawable.pasr_badge_nachtblauw
    "nachtblauw-compact" -> R.drawable.pasr_badge_nachtblauw_compact
    "zwart-compact" -> R.drawable.pasr_badge_zwart_compact
    else -> R.drawable.pasr_badge_zwart
}

private fun sharePng(context: Context, bitmap: Bitmap, name: String) {
    runCatching {
        val dir = File(context.cacheDir, "share").apply { mkdirs() }
        val file = File(dir, "$name.png")
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
