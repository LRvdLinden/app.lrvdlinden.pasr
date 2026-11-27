package app.lrvdlinden.pasrzakelijk.ui.tickets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.data.MemberCard
import app.lrvdlinden.pasrzakelijk.data.TicketEvent
import app.lrvdlinden.pasrzakelijk.data.TkFormat
import app.lrvdlinden.pasrzakelijk.data.TkText
import app.lrvdlinden.pasrzakelijk.ui.Group
import app.lrvdlinden.pasrzakelijk.ui.GroupDivider
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.SectionHeader

/** Overzicht: tegels voor komende events (aanmeldingen) en aflopende kortingsperiodes van klantenkaarten. */
@Composable
fun TkOverview(events: List<TicketEvent>, cards: List<MemberCard>) {
    val now = System.currentTimeMillis()
    val upcoming = events.filter { !it.isCancelled && it.endsAt.time > now }.take(3)
    if (upcoming.isNotEmpty()) {
        SectionHeader(L("Komende events"))
        Group {
            upcoming.forEachIndexed { i, e ->
                if (i > 0) GroupDivider()
                Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(Modifier.width(44.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(TkFormat.calendar(e.startsAt).get(java.util.Calendar.DAY_OF_MONTH).toString(), color = Pz.text, fontWeight = FontWeight.Black, fontSize = 20.sp)
                        Text(TkText.dayMonth(e.startsAt).substringAfter(' ').uppercase(), color = Pz.muted, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(e.name, color = Pz.text, fontWeight = FontWeight.SemiBold, maxLines = 1)
                        Text(L("%@ · %lld/%lld aangemeld", TkText.clock(e.startsAt), e.registered, e.capacity), color = Pz.muted, fontSize = 12.sp)
                        LinearProgressIndicator(progress = { if (e.capacity > 0) minOf(1f, e.registered.toFloat() / e.capacity) else 0f },
                            modifier = Modifier.fillMaxWidth(), color = Pz.iris, trackColor = Pz.card2)
                    }
                    TkStatusPill(e.status)
                }
            }
        }
    }
    if (cards.isNotEmpty()) {
        SectionHeader(L("Klantenkaarten"))
        Group {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
                Text(L("Klantenkaart-leden"), color = Pz.text, modifier = Modifier.weight(1f))
                Text(cards.sumOf { it.members }.toString(), color = Pz.muted)
            }
            cards.forEach { card ->
                val d = card.discountNow
                val until = d?.until
                if (d != null && until != null && until.time - now < 7 * 86_400_000L) {
                    GroupDivider()
                    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
                        Text(L("Kortingsperiode %@%% bij %@", TkFormat.percent(d.percent), card.name), color = Pz.text, fontWeight = FontWeight.SemiBold)
                        Text(L("Loopt af op %@", TkText.dayMonth(until)), color = Pz.coral, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
                if (card.status == "draft") {
                    GroupDivider()
                    Text(L("%@ staat nog in concept", card.name), color = Pz.muted, modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
                }
            }
        }
    }
}
