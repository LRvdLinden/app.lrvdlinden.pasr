package app.lrvdlinden.pasr.ui

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Pasr-stempelkaartstijl: echte ondernemerlogo + bedrijfskleur, eigen Pasr-merk, status voorop. */
@Composable
fun PasrOfferCard(offer: JSONObject, saved: Boolean) {
    val business = offer.optString("business", "Ondernemer")
    val kind = if (offer.optString("kind") == "code") "Actiecode" else "Kortingscoupon"
    val used = offer.optBoolean("redeemed")
    val paused = offer.optBoolean("disabled")
    val expiry = remember(offer.optString("ends_at")) {
        runCatching { Instant.parse(offer.optString("ends_at")) }.getOrNull()
    }
    val expired = expiry?.isBefore(Instant.now()) == true
    val inactive = used || paused || expired
    val status = when {
        used -> "PASR · GEBRUIKT"
        paused -> "GEPAUZEERD"
        expired -> "VERLOPEN"
        saved -> "Opgeslagen"
        else -> "Beschikbaar"
    }
    val tint = remember(offer.optString("color")) {
        runCatching { Color(android.graphics.Color.parseColor(offer.optString("color", "#6A5CFF"))) }
            .getOrDefault(Color(0xFF6A5CFF))
    }
    val logo = remember(offer.optString("logo")) {
        runCatching {
            val bytes = Base64.decode(offer.optString("logo"), Base64.DEFAULT)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
        }.getOrNull()
    }
    val value = offer.optDouble("discount_value")
    val discount = if (offer.optString("discount_type") == "percent")
        value.toInt().toString() + "% KORTING"
    else "€ " + "%.2f".format(Locale.forLanguageTag("nl-NL"), value) + " KORTING"
    Box(Modifier.fillMaxWidth().background(
        Brush.linearGradient(if (inactive) listOf(Color.DarkGray, Color.Gray)
                             else listOf(tint.copy(alpha=.84f), tint)),
        RoundedCornerShape(22.dp)
    )) {
        Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (logo != null) {
                    Image(logo, "Bedrijfslogo", Modifier.size(44.dp).background(Color.White, RoundedCornerShape(10.dp)))
                } else {
                    Box(Modifier.size(44.dp).background(Color.White, RoundedCornerShape(10.dp)),
                        contentAlignment = Alignment.Center) {
                        Text(business.take(1), color = Color(0xFF29233E), fontWeight = FontWeight.Bold)
                    }
                }
                Column(Modifier.weight(1f).padding(start = 10.dp)) {
                    Text(business, color = Color.White, fontWeight = FontWeight.Bold)
                    Text(kind, color = Color.White.copy(alpha=.8f),
                        style = MaterialTheme.typography.labelSmall)
                }
                Text("pasr.", color = Color.White, fontWeight = FontWeight.Black,
                    style = MaterialTheme.typography.titleLarge)
            }
            Text(discount, color = Color.White, style = MaterialTheme.typography.headlineLarge,
                fontWeight = FontWeight.Black)
            Text(offer.optString("title"), color = Color.White, fontWeight = FontWeight.Bold)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(status, color = Color.White, fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.labelMedium, modifier = Modifier.weight(1f))
                if (expiry != null) Text("t/m " +
                    DateTimeFormatter.ofPattern("dd-MM-yyyy").withZone(ZoneId.systemDefault()).format(expiry),
                    color = Color.White, style = MaterialTheme.typography.labelSmall)
            }
        }
        if (used) {
            Text("PASR · GEBRUIKT", Modifier.align(Alignment.Center)
                .border(3.dp, Color.White, RoundedCornerShape(40.dp)).padding(11.dp),
                color = Color.White, fontWeight = FontWeight.Black)
        }
    }
}
