package app.lrvdlinden.pasr.ui

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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.ConfirmationNumber
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.Catalog
import app.lrvdlinden.pasr.data.TicketInfo
import app.lrvdlinden.pasr.data.ticketInfo
import kotlin.math.PI
import kotlin.math.sin

/**
 * Een ticket zoals een eventTicket in Apple Wallet (zelfde als TicketFaceView.swift): bovenaan de huisstijl van het
 * evenement (logo, naam, titel, soort ticket, datum, toegang, locatie), een golvende rand in de merkkleur,
 * uitsparingen aan de zijkanten en daaronder het deel met de QR-code van de bezoeker.
 *
 * - `full = false`: op kaartformaat, voor de lijst en het raster (als ticket herkenbaar, geen klantenkaart).
 * - `full = true`: hoog, voor het detail, met de code en de knoppen Route en Informatie.
 *
 * `info` en `logo` zijn er voor voorbeelden (Paparazzi); in de app komen ze uit de catalogus.
 */
@Composable
fun TicketFace(
    card: Card,
    modifier: Modifier = Modifier,
    full: Boolean = false,
    compact: Boolean = false,
    revealed: Boolean = true,
    demo: Boolean = false,
    showsActions: Boolean = true,
    onReveal: (() -> Unit)? = null,
    info: TicketInfo = remember(card) { card.ticketInfo() },
    logo: android.graphics.Bitmap? = remember(card.id, card.logo, card.templateID, card.website) { Catalog.logo(card) },
) {
    val brand = hexColor(card.colorHex)
    val ink = info.textHex?.let { hexColor(it) } ?: onCard(card.colorHex)
    val label = info.labelHex?.let { hexColor(it) } ?: ink.copy(alpha = 0.72f)
    val description = listOfNotNull(info.title, "ticket", info.type, info.note, info.dateText, info.timeText?.let { "toegang $it" }, info.place)
        .joinToString(", ")
    if (!full) {
        TicketFront(card, info, logo, brand, ink, label, compact, modifier.semantics { contentDescription = description })
    } else {
        TicketFull(card, info, logo, brand, ink, label, revealed, demo, showsActions, onReveal, modifier.semantics { contentDescription = description })
    }
}

/** Afgeronde rechthoek met twee halve uitsparingen aan de zijkanten op hoogte `notchY` (in px; < 0 = vanaf onder). */
class TicketShape(private val corner: Dp, private val notchY: (Size) -> Float, private val notch: Dp = 11.dp) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val r = with(density) { corner.toPx() }
        val n = with(density) { notch.toPx() }
        val card = Path().apply { addRoundRect(RoundRect(0f, 0f, size.width, size.height, r, r)) }
        val y = notchY(size)
        if (y <= r + n || y >= size.height - r - n) return Outline.Generic(card)
        val holes = Path().apply {
            addOval(androidx.compose.ui.geometry.Rect(Offset(0f, y), n))
            addOval(androidx.compose.ui.geometry.Rect(Offset(size.width, y), n))
        }
        return Outline.Generic(Path().apply { op(card, holes, PathOperation.Difference) })
    }
}

@Composable
private fun TicketFront(card: Card, info: TicketInfo, logo: android.graphics.Bitmap?, brand: Color, ink: Color, label: Color,
                        compact: Boolean, modifier: Modifier) {
    val corner = if (compact) 14.dp else 20.dp
    val stubFraction = 0.30f
    val shape = remember(corner, compact) { TicketShape(corner, { it.height * (1 - stubFraction) }, if (compact) 7.dp else 11.dp) }
    BoxWithConstraints(modifier.aspectRatio(Brand.CARD_ASPECT).shadow(if (compact) 3.dp else 8.dp, shape).clip(shape).background(brand)) {
        val w = maxWidth
        val h = maxHeight
        val pad = if (compact) 9.dp else 14.dp
        Column(Modifier.fillMaxSize().padding(start = pad, end = pad, top = pad)) {
            TicketHeader(card, info, logo, ink, label, small = compact)
            Spacer(Modifier.weight(1f))
            Text(info.title, color = ink, fontWeight = FontWeight.Black,
                fontSize = if (compact) 14.sp else (w.value * 0.07f).coerceIn(16f, 26f).sp,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            TypePill(info, ink, small = true, modifier = Modifier.padding(top = if (compact) 3.dp else 5.dp))
            Spacer(Modifier.weight(1f))
            // strookje onder de perforatie: datum, toegang, locatie
            Row(Modifier.fillMaxWidth().height(h * stubFraction), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(if (compact) 8.dp else 12.dp)) {
                info.dateText?.let { TicketField("DATUM", it, ink, label, small = true, tiny = compact) }
                info.timeText?.let { TicketField("TOEGANG", it, ink, label, small = true, tiny = compact) }
                if (!compact) info.place?.let {
                    TicketField("LOCATIE", it, ink, label, small = true, modifier = Modifier.weight(1f, fill = false))
                }
            }
        }
        // perforatie tussen kop en strookje
        Canvas(Modifier.fillMaxWidth().padding(horizontal = 16.dp).height(1.dp).offset(y = h * (1 - stubFraction))) {
            drawLine(ink.copy(alpha = 0.35f), Offset(0f, 0f), Offset(size.width, 0f), strokeWidth = 1.2f * density,
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(4 * density, 4 * density)))
        }
    }
}

@Composable
private fun TicketFull(card: Card, info: TicketInfo, logo: android.graphics.Bitmap?, brand: Color, ink: Color, label: Color,
                       revealed: Boolean, demo: Boolean, showsActions: Boolean, onReveal: (() -> Unit)?, modifier: Modifier) {
    val dark = LocalDark.current
    val paper = if (dark) Color(0xFF1C1C1E) else Color.White
    val paperInk = if (dark) Color.White else Color(0xFF111216)
    val context = LocalContext.current
    val density = LocalDensity.current
    var headPx by remember { mutableFloatStateOf(0f) }
    val waveH = 18.dp
    val notchAt = headPx + with(density) { (waveH * 0.45f).toPx() }
    val shape = remember(notchAt) { TicketShape(20.dp, { notchAt }) }
    Column(modifier.fillMaxWidth().shadow(10.dp, shape).clip(shape)) {
        Column(
            Modifier.fillMaxWidth().background(brand).onSizeChanged { headPx = it.height.toFloat() }
                .padding(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 10.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            TicketHeader(card, info, logo, ink, label, small = false)
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(info.title, color = ink, fontWeight = FontWeight.Black, fontSize = 30.sp, lineHeight = 34.sp, maxLines = 2,
                    overflow = TextOverflow.Ellipsis)
                TypePill(info, ink, small = false)
            }
            if (info.dateText != null || info.timeText != null) Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                info.dateText?.let { TicketField("DATUM", it, ink, label) }
                info.timeText?.let { TicketField("TOEGANG", it, ink, label) }
            }
            if (info.place != null || info.seat != null) Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                info.place?.let { TicketField("LOCATIE", it, ink, label, modifier = Modifier.weight(1f, fill = false)) }
                info.seat?.let { TicketField("PLAATS", it, ink, label) }
            }
        }
        // golvende onderrand in de merkkleur
        Canvas(Modifier.fillMaxWidth().height(waveH).background(paper)) {
            val mid = size.height * 0.45f
            val amp = size.height * 0.4f
            val waves = 7f
            val steps = 80
            val p = Path().apply {
                moveTo(0f, 0f)
                lineTo(size.width, 0f)
                lineTo(size.width, mid)
                for (i in steps downTo 0) {
                    val x = size.width * i / steps
                    lineTo(x, mid + amp * sin(i.toFloat() / steps * waves * 2f * PI.toFloat()))
                }
                close()
            }
            drawPath(p, brand)
        }
        Column(
            Modifier.fillMaxWidth().background(paper).padding(start = 20.dp, end = 20.dp, bottom = 18.dp, top = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(Modifier.widthIn(max = 230.dp).fillMaxWidth()) {
                when {
                    !revealed -> Notice("Afgeschermd", paperInk, Icons.Filled.Lock, onReveal)
                    card.number.isEmpty() -> Notice("Geen code", paperInk, Icons.Outlined.ConfirmationNumber, null)
                    else -> Column(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Color.White)
                            .border(1.dp, Color.Black.copy(alpha = 0.08f), RoundedCornerShape(14.dp)).padding(12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        BarcodeImage(card.number, card.format, Modifier.fillMaxWidth())
                        Text(card.number, color = Color(0xB3111216), fontFamily = FontFamily.Monospace, fontSize = 12.sp,
                            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 6.dp))
                    }
                }
            }
            if (demo) {
                Text("DEMO – geen toegangsbewijs", color = Color(0xFFC8372F), fontWeight = FontWeight.Bold, fontSize = 11.sp,
                    letterSpacing = 0.6.sp)
            }
            Text("Pasr", color = paperInk.copy(alpha = 0.45f), fontWeight = FontWeight.Black, fontSize = 13.sp)
            if (showsActions && (info.routeTarget != null || info.info != null)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    info.routeTarget?.let { target ->
                        TicketButton("Route", Icons.Filled.Map, brand, onCard(card.colorHex), Modifier.weight(1f)) {
                            val geo = Uri.parse("geo:0,0?q=" + Uri.encode(target))
                            val ok = runCatching {
                                context.startActivity(Intent(Intent.ACTION_VIEW, geo).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            }.isSuccess
                            if (!ok) openUrl(context, "https://www.google.com/maps/dir/?api=1&destination=" + Uri.encode(target))
                        }
                    }
                    info.info?.let { url ->
                        TicketButton("Informatie", Icons.Filled.Info, brand, onCard(card.colorHex), Modifier.weight(1f)) {
                            openInApp(context, url)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TicketHeader(card: Card, info: TicketInfo, logo: android.graphics.Bitmap?, ink: Color, label: Color, small: Boolean) {
    val size = if (small) 22.dp else 34.dp
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (logo != null) {
            Image(logo.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Fit,
                modifier = Modifier.height(size).widthIn(max = size * 3.2f))
        } else {
            // geen logo: de initialen in de merkkleur
            val initials = info.brand.split(" ").filter { it.isNotBlank() }.take(2).joinToString("") { it.take(1) }.uppercase().ifBlank { "T" }
            Box(Modifier.size(size).clip(RoundedCornerShape(size * 0.28f)).background(ink.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
                Text(initials, color = ink, fontWeight = FontWeight.Black, fontSize = (size.value * 0.42f).sp)
            }
        }
        Text(info.brand.uppercase(), color = ink, fontWeight = FontWeight.Black, fontSize = if (small) 11.sp else 14.sp,
            letterSpacing = 1.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        if (card.isFavorite) Icon(Icons.Filled.Star, null, tint = ink.copy(alpha = 0.85f), modifier = Modifier.size(if (small) 12.dp else 15.dp))
        if (card.isLocked) Icon(Icons.Filled.Lock, null, tint = ink.copy(alpha = 0.85f), modifier = Modifier.size(if (small) 12.dp else 15.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Icon(Icons.Outlined.ConfirmationNumber, null, tint = label, modifier = Modifier.size(if (small) 10.dp else 13.dp))
            Text("TICKET", color = label, fontWeight = FontWeight.SemiBold, fontSize = if (small) 8.sp else 10.sp, letterSpacing = 0.6.sp)
        }
    }
}

@Composable
private fun TypePill(info: TicketInfo, ink: Color, small: Boolean, modifier: Modifier = Modifier) {
    val type = info.type ?: return
    Row(
        modifier.clip(RoundedCornerShape(50)).background(ink.copy(alpha = 0.18f))
            .border(1.dp, ink.copy(alpha = 0.3f), RoundedCornerShape(50))
            .padding(horizontal = if (small) 8.dp else 12.dp, vertical = if (small) 2.dp else 4.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(type, color = ink, fontWeight = FontWeight.Bold, fontSize = if (small) 11.sp else 14.sp, maxLines = 1)
        info.note?.let { Text(it, color = ink.copy(alpha = 0.8f), fontWeight = FontWeight.Medium, fontSize = if (small) 10.sp else 12.sp, maxLines = 1) }
    }
}

@Composable
private fun TicketField(title: String, value: String, ink: Color, label: Color, small: Boolean = false, tiny: Boolean = false,
                        modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(title, color = label, fontWeight = FontWeight.SemiBold, fontSize = if (tiny) 7.sp else if (small) 8.sp else 10.sp, letterSpacing = 0.7.sp)
        Text(value, color = ink, fontWeight = FontWeight.SemiBold, fontSize = if (tiny) 9.sp else if (small) 11.sp else 16.sp,
            maxLines = if (small) 1 else 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun Notice(text: String, color: Color, icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: (() -> Unit)?) {
    Column(
        Modifier.fillMaxWidth().heightIn(min = 90.dp).clip(RoundedCornerShape(12.dp)).background(color.copy(alpha = 0.06f))
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        Icon(icon, null, tint = color.copy(alpha = 0.7f), modifier = Modifier.size(28.dp))
        Text(text, color = color.copy(alpha = 0.7f), fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
        if (onClick != null) Text("Tik om de code te tonen", color = color.copy(alpha = 0.55f), fontSize = 11.sp)
    }
}

@Composable
private fun TicketButton(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, background: Color, content: Color,
                         modifier: Modifier = Modifier, onClick: () -> Unit) {
    Row(
        modifier.clip(RoundedCornerShape(50)).background(background).clickable(onClick = onClick).padding(vertical = 11.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = content, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(6.dp))
        Text(title, color = content, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
    }
}
