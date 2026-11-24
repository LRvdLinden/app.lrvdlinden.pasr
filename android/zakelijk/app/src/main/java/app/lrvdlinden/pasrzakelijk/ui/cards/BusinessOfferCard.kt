package app.lrvdlinden.pasrzakelijk.ui.cards

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasrzakelijk.core.LogoImage
import org.json.JSONObject
import java.util.Locale

/** De bestaande stempelkaartstijl doorgezet naar coupons en promotiecodes, geen lijstje. */
@Composable
fun BusinessOfferCard(business: String, item: JSONObject, isCode: Boolean, logo: String? = null,
                      color: String = "#6A5CFF") {
    val used = if(isCode)item.optInt("used_count") else item.optInt("redeemed")
    val deleted = item.optBoolean("deleted")
    val active = if(isCode)item.optBoolean("active") else item.optBoolean("public")
    val paused = !active || deleted
    val tint = runCatching {
        Color(android.graphics.Color.parseColor(item.optString("color",color)))
    }.getOrDefault(Color(0xFF6A5CFF))
    val value = item.optDouble("discount_value")
    val discount = if(item.optString("discount_type")=="percent")
        value.toInt().toString()+"% KORTING"
    else "€ "+String.format(Locale.forLanguageTag("nl-NL"),"%.2f",value)+" KORTING"
    Column(Modifier.fillMaxWidth().background(
        Brush.linearGradient(if(paused)listOf(Color.DarkGray,Color.Gray)
            else listOf(tint.copy(alpha=.82f),tint)),RoundedCornerShape(22.dp))
        .padding(18.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment=Alignment.CenterVertically) {
            LogoImage(item.optString("logo").ifBlank { logo ?: "" }, modifier=Modifier.size(44.dp))
            Column(Modifier.weight(1f).padding(start=10.dp)) {
                Text(business,color=Color.White,fontWeight=FontWeight.Bold)
                Text(if(isCode)"Actiecode" else "Kortingscoupon",color=Color.White.copy(alpha=.85f),
                    style=MaterialTheme.typography.labelSmall)
            }
            Text("pasr.",color=Color.White,fontWeight=FontWeight.Black,
                style=MaterialTheme.typography.titleLarge)
        }
        Text(discount,color=Color.White,fontWeight=FontWeight.Black,
            style=MaterialTheme.typography.headlineLarge)
        Text(item.optString("title"),color=Color.White,fontWeight=FontWeight.Bold)
        Row {
            Text(if(deleted)"VERWIJDERD" else if(active)"Actief" else "Gepauzeerd",
                color=Color.White,fontWeight=FontWeight.Bold,modifier=Modifier.weight(1f))
            Text(used.toString()+" gebruikt",color=Color.White)
        }
    }
}
