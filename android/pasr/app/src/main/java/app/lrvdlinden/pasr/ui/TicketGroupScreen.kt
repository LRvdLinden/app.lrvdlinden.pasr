package app.lrvdlinden.pasr.ui

import android.app.Activity
import android.view.WindowManager
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ConfirmationNumber
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.CardStackItem
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.Prefs
import app.lrvdlinden.pasr.data.ticketGroupOf
import kotlinx.coroutines.launch

/*
 * Groep tickets (zelfde evenement, zelfde dag): één tegel in de portemonnee en horizontaal vegen in het detail.
 * De groepeersleutel staat in data/TicketGroups.kt.
 */

/**
 * DE plek voor de weergave van een ticket in een groep (tegel in de portemonnee). Nu de gewone kaart; zodra
 * TicketFace er is, is dit één regel.
 */
@Composable
fun TicketGroupFace(card: Card, modifier: Modifier = Modifier) {
    TicketFace(card, modifier, compact = true)
}

/** Detail van een kaart; hoort de kaart bij een groep tickets, dan veeg je tussen de tickets van die groep. */
@Composable
fun CardDetailScreen(id: String) {
    val all by CardStore.cards.collectAsState()
    val group = remember(all, id) { all.ticketGroupOf(id) }
    if (group.size > 1) TicketGroupDetail(group, id) else CardDetailContent(id)
}

/** Tickets van één groep naast elkaar: vegen naar het volgende ticket, puntjes en "1 van 3" onderin. */
@Composable
private fun TicketGroupDetail(group: List<Card>, startId: String) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val start = remember(startId) { group.indexOfFirst { it.id.equals(startId, true) }.coerceAtLeast(0) }
    val pager = rememberPagerState(initialPage = start) { group.size }
    // een ticket verwijderd: binnen de groep blijven
    LaunchedEffect(group.size) { if (pager.currentPage >= group.size) pager.scrollToPage(group.size - 1) }

    // volle helderheid voor de hele groep (niet per pagina, anders springt het bij het vegen)
    DisposableEffect(Unit) {
        val w = (context as? Activity)?.window
        val before = w?.attributes?.screenBrightness
        if (Prefs.brightness) w?.let { it.attributes = it.attributes.apply { screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL } }
        onDispose { w?.let { it.attributes = it.attributes.apply { screenBrightness = before ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE } } }
    }

    Box(Modifier.fillMaxSize()) {
        HorizontalPager(pager, Modifier.fillMaxSize(), key = { group[it].id }) { page ->
            CardDetailContent(group[page].id, inGroup = true)
        }

        val current = pager.currentPage.coerceIn(0, group.size - 1)
        val label = "Ticket ${current + 1} van ${group.size}: ${group[current].storeName}"
        Column(
            Modifier.align(Alignment.BottomCenter).padding(bottom = 24.dp)
                .clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.72f))
                .padding(horizontal = 16.dp, vertical = 8.dp)
                .clearAndSetSemantics {
                    contentDescription = label
                    stateDescription = "${current + 1} van ${group.size}"
                    customActions = listOf(
                        CustomAccessibilityAction("Volgend ticket") {
                            if (current + 1 < group.size) { scope.launch { pager.animateScrollToPage(current + 1) }; true } else false
                        },
                        CustomAccessibilityAction("Vorig ticket") {
                            if (current > 0) { scope.launch { pager.animateScrollToPage(current - 1) }; true } else false
                        },
                    )
                },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                repeat(group.size) { i ->
                    Box(Modifier.size(7.dp).clip(CircleShape)
                        .background(if (i == current) Color.White else Color.White.copy(alpha = 0.35f))
                        .clickable { scope.launch { pager.animateScrollToPage(i) } })
                }
            }
            Text("${current + 1} van ${group.size}", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 4.dp))
        }
    }
}

/** Groep tickets in de portemonnee: het eerste ticket met de naam van het evenement, randjes erachter en "3 tickets". */
@Composable
fun TicketGroupTile(item: CardStackItem, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Column(
        Modifier.clickable(onClick = onClick).semantics(mergeDescendants = true) {
            contentDescription = "${item.title}, ${item.countText}"
            role = Role.Button
        },
    ) {
        Box {
            // randjes van de tickets erachter (zoals een stapeltje passen)
            listOf(2, 1).filter { it < item.cards.size }.forEach { level ->
                Box(
                    Modifier.fillMaxWidth().padding(horizontal = (8 * level).dp).offset(y = (-4 * level).dp)
                        .aspectRatio(Brand.CARD_ASPECT).clip(shape)
                        .background(hexColor(item.cards[level.coerceAtMost(item.cards.size - 1)].colorHex).copy(alpha = 0.8f)),
                )
            }
            TicketGroupFace(item.first.copy(storeName = item.title), Modifier.fillMaxWidth())
            Row(
                Modifier.align(Alignment.TopEnd).padding(6.dp).clip(RoundedCornerShape(50))
                    .background(Color.Black.copy(alpha = 0.6f)).padding(horizontal = 7.dp, vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Outlined.ConfirmationNumber, null, tint = Color.White, modifier = Modifier.size(12.dp))
                Text(" ${item.cards.size}", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            }
        }
        Text("${item.title} · ${item.countText}", style = MaterialTheme.typography.labelLarge, maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 4.dp, top = 6.dp))
    }
}
