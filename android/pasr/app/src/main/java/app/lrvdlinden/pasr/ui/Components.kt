package app.lrvdlinden.pasr.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.pm.PackageInfoCompat
import app.lrvdlinden.pasr.R
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.CardKind
import app.lrvdlinden.pasr.data.Catalog
import java.text.NumberFormat
import java.time.Year
import java.util.Locale

fun openUrl(context: Context, url: String) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

/** Link in de app openen met Custom Tabs (Chrome of een andere browser die het kent), anders gewoon in de browser. */
fun openInApp(context: Context, url: String) {
    val ok = runCatching {
        androidx.browser.customtabs.CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, Uri.parse(url))
    }.isSuccess
    if (!ok) openUrl(context, url)
}

fun euro(v: Double, currency: String? = "EUR"): String = runCatching {
    NumberFormat.getCurrencyInstance(Locale("nl", "NL")).apply { this.currency = java.util.Currency.getInstance(currency ?: "EUR") }.format(v)
}.getOrDefault("€ %.2f".format(v))

fun dateText(ms: Long): String =
    java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy", Locale("nl", "NL"))
        .format(java.time.Instant.ofEpochMilli(ms).atZone(java.time.ZoneId.systemDefault()))

/** Voorkant van een kaart: echte merkkleur, schoon logo, geen randen (stijl SuperCards). */
@Composable
fun CardFace(card: Card, modifier: Modifier = Modifier, compact: Boolean = false) {
    val logo = remember(card.id, card.logo, card.templateID, card.website) { Catalog.logo(card) }
    val style = remember(card.id, card.templateID, card.logo) { Catalog.styleFor(card) }
    val cover = remember(card.id, card.cover, card.templateID) { Catalog.coverBitmap(card) }
    val fg = onCard(card.colorHex)
    val shape = RoundedCornerShape(if (compact) 14.dp else 20.dp)
    BoxWithConstraints(
        modifier.aspectRatio(Brand.CARD_ASPECT).shadow(if (compact) 3.dp else 8.dp, shape).clip(shape)
            .background(Brush.linearGradient(listOf(shade(card.colorHex, 0.08f), shade(card.colorHex, -0.12f)))),
    ) {
        val w = maxWidth
        if (cover != null) {
            Image(cover.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        } else if (logo != null) {
            val plate = style?.plate
            Box(Modifier.fillMaxSize().padding(horizontal = w * 0.14f, vertical = w * 0.1f), contentAlignment = Alignment.Center) {
                Box(
                    if (plate != null) Modifier.clip(RoundedCornerShape(10.dp)).background(hexColor(plate)).padding(8.dp) else Modifier,
                    contentAlignment = Alignment.Center,
                ) {
                    Image(
                        logo.asImageBitmap(), contentDescription = card.storeName,
                        modifier = Modifier.fillMaxWidth(if (style?.opaque == true) 0.45f else 1f),
                        contentScale = ContentScale.Fit,
                        colorFilter = style?.tint?.let { ColorFilter.tint(hexColor(it)) },
                    )
                }
            }
        } else {
            Text(
                card.storeName.ifBlank { card.kind.title }, color = fg, fontWeight = FontWeight.Bold,
                fontSize = if (compact) 17.sp else 26.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center,
                modifier = Modifier.align(Alignment.Center).padding(horizontal = 12.dp),
            )
        }
        // onderrand: soort, saldo of stempels
        val badge: String? = when (card.kind) {
            CardKind.VOUCHER -> card.balance?.let { euro(it, card.currencyCode) }
            CardKind.STAMPS -> "${card.details.stampsCountValue}/${card.details.stampsTotalValue}"
            CardKind.LOYALTY -> null
            else -> card.kind.title
        }
        if (badge != null) {
            Text(
                badge, color = fg, fontWeight = FontWeight.SemiBold, fontSize = if (compact) 11.sp else 14.sp,
                modifier = Modifier.align(Alignment.BottomEnd).padding(if (compact) 8.dp else 14.dp)
                    .clip(RoundedCornerShape(50)).background(fg.copy(alpha = 0.16f)).padding(horizontal = 8.dp, vertical = 2.dp),
            )
        }
        if (card.isFavorite && !compact) {
            Icon(androidx.compose.material.icons.Icons.Filled.Star, null, tint = fg.copy(alpha = 0.85f),
                modifier = Modifier.align(Alignment.TopEnd).padding(12.dp).size(18.dp))
        }
        if (card.isExpired) {
            Text("Verlopen", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.TopStart).padding(8.dp).clip(RoundedCornerShape(50))
                    .background(Color(0xCCC8372F)).padding(horizontal = 8.dp, vertical = 2.dp))
        }
    }
}

/** Stempelvakjes (alleen-lezen: alleen de zaak zet stempels). */
@Composable
fun StampGrid(total: Int, count: Int, color: Color, modifier: Modifier = Modifier) {
    val perRow = if (total <= 10) 5 else 6
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        (0 until total).chunked(perRow).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { i ->
                    val filled = i < count
                    Box(
                        Modifier.size(34.dp).clip(CircleShape)
                            .background(if (filled) color else Color.Transparent)
                            .border(2.dp, color.copy(alpha = if (filled) 1f else 0.45f), CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (filled) Icon(androidx.compose.material.icons.Icons.Filled.Check, null, tint = onCard(color.toHex()), modifier = Modifier.size(18.dp))
                    }
                }
            }
        }
    }
}

@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.padding(start = 4.dp, top = 22.dp, bottom = 8.dp),
    )
}

@Composable
fun Group(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(MaterialTheme.colorScheme.surfaceContainer)) { content() }
}

@Composable
fun RowItem(
    icon: ImageVector?, title: String, subtitle: String? = null, tint: Color = MaterialTheme.colorScheme.primary,
    trailing: (@Composable () -> Unit)? = null, onClick: (() -> Unit)? = null,
) {
    Row(
        Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = tint, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(14.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        trailing?.invoke()
    }
}

@Composable
fun Gap(h: Dp) = Spacer(Modifier.height(h))

/** "Meer apps van de ontwikkelaar", zelfde ontwerp als MoreAppsCard.swift (Homey Store) en Noodpakket. */
@Composable
fun MoreAppsCard() {
    val context = LocalContext.current
    val dark = LocalDark.current
    val accent = if (dark) Brand.lrAccentDark else Brand.lrAccentLight
    val line = if (dark) Color(0xFF262D3D) else Color(0xFFDDE2EC)
    val surface = if (dark) Color(0xFF161B27) else Color.White
    val muted = if (dark) Color(0xFF98A0B3) else Color(0xFF5D6578)
    Column {
        SectionHeader("Ontdekken")
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(surface)
                .border(1.dp, line, RoundedCornerShape(22.dp))
                .clickable(role = Role.Button) { openUrl(context, "https://lrvdlinden.app") }
                .semantics { contentDescription = "Meer apps van de ontwikkelaar. Apps voor iPhone, iPad, Android, Apple TV en Homey" }
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            LRLogo(Modifier.size(60.dp).border(1.dp, line, RoundedCornerShape(13.dp)))
            Column(Modifier.weight(1f)) {
                Text("Meer apps van de ontwikkelaar", color = accent, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.titleMedium)
                Text("Apps voor iPhone, iPad, Android, Apple TV en Homey", color = muted, style = MaterialTheme.typography.bodyMedium)
            }
            Text(
                "Bekijk", color = if (dark) Color(0xFF0D1018) else Color.White, fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.clip(CircleShape).background(accent).padding(horizontal = 14.dp, vertical = 6.dp),
            )
        }
    }
}

/** Het "LR"-merk van lrvdlinden.app op een raster van 512. */
@Composable
fun LRLogo(modifier: Modifier = Modifier) {
    Canvas(modifier.clip(RoundedCornerShape(13.dp))) {
        val s = size.width / 512f
        drawRect(Brand.lrTile)
        val stroke = Stroke(46 * s, cap = StrokeCap.Round, join = StrokeJoin.Round)
        val l = Path().apply { moveTo(132 * s, 146 * s); lineTo(132 * s, 370 * s); lineTo(232 * s, 370 * s) }
        val r = Path().apply {
            moveTo(292 * s, 370 * s); lineTo(292 * s, 146 * s); lineTo(340 * s, 146 * s)
            arcTo(androidx.compose.ui.geometry.Rect(Offset(278 * s, 146 * s), Size(124 * s, 124 * s)), -90f, 180f, false)
            lineTo(292 * s, 270 * s)
            moveTo(338 * s, 270 * s); lineTo(390 * s, 370 * s)
        }
        drawPath(l, Color.White, style = stroke)
        drawPath(r, Color.White, style = stroke)
        drawCircle(Brand.lrDot, 34 * s, Offset(404 * s, 126 * s))
        drawCircle(Brand.lrTile, 34 * s, Offset(404 * s, 126 * s), style = Stroke(14 * s))
    }
}

@Composable
fun AppIcon(size: Dp) {
    Box(Modifier.size(size).clip(RoundedCornerShape(size * 0.22f)).background(Color(0xFF1A1633))) {
        Image(painterResource(R.mipmap.ic_launcher_background), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        Image(painterResource(R.mipmap.ic_launcher_foreground), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
    }
}

/** App-icoon, "Versie 1.0.0 (101)" en "© <jaar> Pasr" onderaan Instellingen. */
@Composable
fun AppInfoFooter() {
    val context = LocalContext.current
    val info = remember(context) { context.packageManager.getPackageInfo(context.packageName, 0) }
    val code = PackageInfoCompat.getLongVersionCode(info)
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    Column(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        AppIcon(64.dp)
        Spacer(Modifier.height(14.dp))
        Text("Versie ${info.versionName ?: "–"} ($code)", color = muted, style = MaterialTheme.typography.bodyMedium)
        Text("© ${Year.now().value} Pasr", color = muted, style = MaterialTheme.typography.bodyMedium)
    }
}
