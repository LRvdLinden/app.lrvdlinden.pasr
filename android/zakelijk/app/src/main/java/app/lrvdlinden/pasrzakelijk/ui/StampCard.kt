package app.lrvdlinden.pasrzakelijk.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Image
import androidx.compose.foundation.Canvas
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
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.graphics.drawscope.withTransform
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
            if (!on) drawCircle(
                color.copy(alpha = 0.55f), radius = size.minDimension / 2 - stroke / 2, center = Offset(size.width / 2, size.height / 2),
                style = Stroke(stroke, pathEffect = if (on) null else PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx()))),
            )
        },
        contentAlignment = Alignment.Center,
    ) {
        if (on) {
            PasrStampMark(color, Modifier.fillMaxSize().scale(scale))
        } else if (last) {
            Icon(Icons.Outlined.CardGiftcard, null, tint = color.copy(alpha = 0.7f), modifier = Modifier.size(14.dp))
        }
    }
}


/** Eén op één overgetrokken van de aangeleverde Pasr-zegel. De uitgespaarde
 *  letters en het vinkje laten de gekozen merkkleur van de kaart door. */
private const val PASR_STAMP_PATH = "M54,4 L43,7 L34,11 L24,18 L14,29 L10,35 L4,49 L2,58 L2,75 L4,85 L8,95 L14,105 L23,115 L31,121 L49,129 L74,130 L85,127 L97,121 L106,114 L116,102 L123,87 L125,79 L125,74 L126,73 L125,53 L118,35 L111,25 L100,15 L90,9 L79,5Z M57,8 L63,11 L70,8 L75,12 L84,12 L90,18 L93,19 L97,18 L100,21 L101,26 L107,29 L110,32 L111,39 L118,45 L117,54 L122,63 L122,66 L119,70 L120,80 L116,85 L116,92 L110,97 L110,103 L108,105 L102,107 L100,110 L100,113 L98,115 L91,115 L84,122 L75,121 L68,125 L57,124 L53,121 L44,122 L39,116 L30,115 L28,113 L27,108 L18,103 L18,97 L11,91 L12,84 L7,78 L9,73 L9,68 L6,64 L6,61 L11,55 L10,46 L15,42 L17,38 L17,32 L25,28 L28,20 L37,19 L42,12 L51,13Z M56,17 L46,20 L38,24 L31,29 L23,38 L16,52 L14,62 L14,71 L18,87 L24,97 L31,105 L46,114 L53,116 L66,117 L81,114 L91,109 L103,98 L108,90 L107,89 L108,86 L111,83 L113,76 L113,67 L114,66 L113,65 L113,56 L107,41 L101,33 L93,26 L80,19 L72,17Z M93,101 L94,103 L91,105 L90,103Z M106,82 L107,85 L103,93 L96,100 L95,98 L101,91 L104,83Z M88,76 L65,107 L62,106 L49,96 L49,93 L53,89 L56,90 L62,95 L64,95 L81,72 L83,72Z M42,56 L47,62 L46,73 L41,78 L38,79 L33,78 L33,86 L31,88 L27,88 L25,86 L25,75 L24,74 L23,60 L27,58 L31,59 L34,56 L38,55Z M34,63 L32,65 L32,70 L33,72 L37,72 L39,70 L39,65 L38,63Z M65,51 L68,55 L69,69 L64,72 L61,71 L57,74 L50,73 L48,70 L48,65 L52,61 L56,59 L60,59 L60,57 L56,57 L51,60 L48,56 L52,52 L57,50Z M60,63 L56,65 L57,68 L60,67 L61,65Z M86,45 L87,48 L85,51 L78,51 L77,52 L87,54 L89,56 L89,62 L82,68 L72,68 L70,65 L74,61 L80,62 L82,60 L73,59 L70,56 L71,49 L77,45 L81,44Z M103,39 L104,40 L104,45 L98,51 L99,62 L96,64 L92,64 L90,54 L90,43 L95,41 L97,43 L101,39Z M87,30 L86,32 L83,32 L79,29 L72,27 L55,27 L43,32 L30,45 L28,44 L28,42 L31,38 L41,29 L49,25 L57,23 L71,23 L83,27Z"

@Composable
private fun PasrStampMark(color: Color, modifier: Modifier = Modifier) {
    val stamp = remember {
        PathParser().parsePathString(PASR_STAMP_PATH).toPath().apply {
            fillType = PathFillType.EvenOdd
        }
    }
    Canvas(modifier) {
        withTransform({ scale(size.width / 131f, size.height / 135f, pivot = Offset.Zero) }) {
            drawPath(path = stamp, color = color)
        }
    }
}
