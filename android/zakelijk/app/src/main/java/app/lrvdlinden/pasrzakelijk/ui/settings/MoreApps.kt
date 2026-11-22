package app.lrvdlinden.pasrzakelijk.ui.settings

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.BuildConfig
import app.lrvdlinden.pasrzakelijk.R
import app.lrvdlinden.pasrzakelijk.core.I18n
import app.lrvdlinden.pasrzakelijk.ui.LocalDark
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.openUrl
import java.util.Calendar

/** Huisstijl van lrvdlinden.app (zelfde als MoreAppsCard.swift en de andere Android-apps van Léon). */
private object LRBrand {
    const val URL = "https://lrvdlinden.app"
    val logoTile = Color(0xFF121726)
    val logoDot = Color(0xFF4C6BFF)
    fun accent(dark: Boolean) = if (dark) Color(0xFF8A9DFF) else Color(0xFF2747E8)
    fun onAccent(dark: Boolean) = if (dark) Color(0xFF0D1018) else Color.White
    fun muted(dark: Boolean) = if (dark) Color(0xFF98A0B3) else Color(0xFF5D6578)
    fun surface(dark: Boolean) = if (dark) Color(0xFF161B27) else Color.White
    fun line(dark: Boolean) = if (dark) Color(0xFF262D3D) else Color(0xFFDDE2EC)
}

private data class MoreAppsText(val section: String, val title: String, val subtitle: String, val action: String)

private val moreAppsTexts = mapOf(
    "nl" to MoreAppsText("Ontdekken", "Meer apps van de ontwikkelaar", "Apps voor iPhone, iPad, Apple TV en Homey", "Bekijk"),
    "en" to MoreAppsText("Discover", "More apps from the developer", "Apps for iPhone, iPad, Apple TV and Homey", "View"),
)

fun moreAppsSection(): String = (moreAppsTexts[I18n.languageCode] ?: moreAppsTexts.getValue("en")).section

/** Het "LR"-merk van lrvdlinden.app, getekend (ontwerpraster 512 × 512). */
@Composable
fun LRLogo(size: Int = 60) {
    Canvas(Modifier.size(size.dp)) {
        val s = this.size.width / 512f
        fun p(x: Float, y: Float) = Offset(x * s, y * s)
        drawRoundRect(LRBrand.logoTile, cornerRadius = CornerRadius(116 * s))
        val letters = Path().apply {
            moveTo(132 * s, 146 * s); lineTo(132 * s, 370 * s); lineTo(232 * s, 370 * s)
            moveTo(292 * s, 370 * s); lineTo(292 * s, 146 * s); lineTo(340 * s, 146 * s)
            arcTo(Rect(p(340f, 208f), 62 * s), -90f, 180f, false)
            lineTo(292 * s, 270 * s)
            moveTo(338 * s, 270 * s); lineTo(390 * s, 370 * s)
        }
        drawPath(letters, Color.White, style = Stroke(46 * s, cap = StrokeCap.Round, join = StrokeJoin.Round))
        drawCircle(LRBrand.logoDot, 34 * s, p(404f, 126f))
        drawCircle(LRBrand.logoTile, 34 * s, p(404f, 126f), style = Stroke(14 * s))
    }
}

/** Kaart "Meer apps van de ontwikkelaar" onderaan Instellingen; opent lrvdlinden.app. */
@Composable
fun MoreAppsCard() {
    val context = LocalContext.current
    val dark = LocalDark.current
    val t = moreAppsTexts[I18n.languageCode] ?: moreAppsTexts.getValue("en")
    val shape = RoundedCornerShape(22.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(LRBrand.surface(dark))
            .border(1.dp, LRBrand.line(dark), shape)
            .clickable { context.openUrl(LRBrand.URL) }
            .semantics(mergeDescendants = true) { contentDescription = "${t.title}. ${t.subtitle}"; role = Role.Button }
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column(Modifier.border(1.dp, LRBrand.line(dark), RoundedCornerShape(14.dp))) { LRLogo(60) }
        Column(Modifier.weight(1f)) {
            Text(t.title, color = LRBrand.accent(dark), fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            Text(t.subtitle, color = LRBrand.muted(dark), fontSize = 15.sp)
        }
        Text(
            t.action, color = LRBrand.onAccent(dark), fontWeight = FontWeight.Bold, fontSize = 15.sp,
            modifier = Modifier.clip(CircleShape).background(LRBrand.accent(dark)).padding(horizontal = 14.dp, vertical = 6.dp),
        )
    }
}

/** Onderaan Instellingen: icoon, "Versie: 1.0.0 (101)" en "© <jaar> Pasr Zakelijk". */
@Composable
fun AppInfoFooter() {
    Column(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Image(painterResource(R.drawable.app_icon_display), null, Modifier.size(64.dp).clip(RoundedCornerShape(14.dp)))
        Spacer(Modifier.size(16.dp))
        val label = if (I18n.dutch) "Versie" else "Version"
        Text("$label: ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", color = Pz.muted, fontSize = 15.sp, textAlign = TextAlign.Center)
        Text("© ${Calendar.getInstance().get(Calendar.YEAR)} Pasr Zakelijk", color = Pz.muted, fontSize = 15.sp, textAlign = TextAlign.Center)
    }
}

