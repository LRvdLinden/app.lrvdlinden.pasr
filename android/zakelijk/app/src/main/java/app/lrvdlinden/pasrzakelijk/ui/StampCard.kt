package app.lrvdlinden.pasrzakelijk.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.CardGiftcard
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.core.LogoImage

/** Stempelkaart zoals de klant hem ziet: kleur, logo, naam, vakjes. */
@Composable
fun StampCardView(
    name: String,
    business: String?,
    color: String,
    logo: String?,
    total: Int,
    filled: Int,
    reward: String,
    modifier: Modifier = Modifier,
    textColor: String? = null,
) {
    val fg = textColor?.let { hexColor(it) } ?: onCard(color)
    val base = hexColor(color)
    val initial = ((business?.takeIf { it.isNotBlank() }) ?: name).trim().firstOrNull()?.uppercase() ?: "P"
    val bitmap = remember(logo) { LogoImage.bitmap(logo)?.asImageBitmap() }
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Brush.linearGradient(listOf(base, base.copy(alpha = 0.82f))))
            .border(1.dp, Color.White.copy(alpha = 0.12f), shape)
            .padding(16.dp)
            .clearAndSetSemantics { contentDescription = L("%@: %lld van %lld stempels", name, minOf(filled, total), total) },
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (bitmap != null) {
                Image(
                    bitmap, null, contentScale = ContentScale.Fit,
                    modifier = Modifier.size(38.dp).clip(RoundedCornerShape(9.dp)).background(Color.White),
                )
            } else {
                // geen logo: de initiaal van de zaak
                Box(Modifier.size(38.dp).clip(RoundedCornerShape(9.dp)).background(fg.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
                    Text(initial, color = fg, fontSize = 18.sp, fontWeight = FontWeight.Black)
                }
            }
            Column(Modifier.weight(1f)) {
                Text(name.ifEmpty { "–" }, color = fg, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (!business.isNullOrEmpty()) {
                    Text(business, color = fg.copy(alpha = 0.8f), fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Text("${minOf(filled, total)}/$total", color = fg, fontWeight = FontWeight.Bold, fontSize = 15.sp)
        }
        StampGrid(total = total, filled = filled, color = fg)
        if (reward.isNotEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.CardGiftcard, null, tint = fg.copy(alpha = 0.9f), modifier = Modifier.size(14.dp))
                Text(reward, color = fg.copy(alpha = 0.9f), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** Vakjes van de stempelkaart (5 per rij tot 10, daarna 6 of 8). */
@Composable
fun StampGrid(total: Int, filled: Int, color: Color = Color.White) {
    val perRow = if (total <= 10) 5 else if (total <= 18) 6 else 8
    val rows = (total + perRow - 1) / perRow
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (r in 0 until rows) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (c in 0 until perRow) {
                    val i = r * perRow + c
                    Box(Modifier.weight(1f).widthIn(max = 40.dp).aspectRatio(1f), contentAlignment = Alignment.Center) {
                        if (i < total) StampDot(i < filled, i == total - 1, color)
                    }
                }
            }
        }
    }
}

@Composable
private fun StampDot(on: Boolean, last: Boolean, color: Color) {
    val scale by animateFloatAsState(if (on) 1f else 0.0f, spring(dampingRatio = 0.6f), label = "stamp")
    Box(
        Modifier.fillMaxSize().drawBehind {
            val stroke = 1.5.dp.toPx()
            drawCircle(
                color.copy(alpha = 0.55f), radius = size.minDimension / 2 - stroke / 2, center = Offset(size.width / 2, size.height / 2),
                style = Stroke(stroke, pathEffect = if (on) null else PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx()))),
            )
        },
        contentAlignment = Alignment.Center,
    ) {
        if (on) {
            Box(Modifier.fillMaxSize().padding(3.dp).scale(scale).clip(CircleShape).background(color.copy(alpha = 0.95f)), contentAlignment = Alignment.Center) {
                Icon(
                    if (last) Icons.Filled.CardGiftcard else Icons.Filled.Check, null,
                    tint = if (color == Color.White) Color.Black.copy(alpha = 0.75f) else Color.White,
                    modifier = Modifier.size(14.dp),
                )
            }
        } else if (last) {
            Icon(Icons.Outlined.CardGiftcard, null, tint = color.copy(alpha = 0.7f), modifier = Modifier.size(14.dp))
        }
    }
}

