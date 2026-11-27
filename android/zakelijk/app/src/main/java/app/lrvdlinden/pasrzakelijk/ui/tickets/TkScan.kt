package app.lrvdlinden.pasrzakelijk.ui.tickets

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Percent
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.data.Business
import app.lrvdlinden.pasrzakelijk.data.MemberScan
import app.lrvdlinden.pasrzakelijk.data.SavingInfo
import app.lrvdlinden.pasrzakelijk.data.TicketScan
import app.lrvdlinden.pasrzakelijk.data.TkApi
import app.lrvdlinden.pasrzakelijk.data.TkFormat
import app.lrvdlinden.pasrzakelijk.data.TkText
import app.lrvdlinden.pasrzakelijk.ui.BigButton
import app.lrvdlinden.pasrzakelijk.ui.FullSheet
import app.lrvdlinden.pasrzakelijk.ui.rememberHaptics
import kotlinx.coroutines.launch

private val Green = Color(0xFF12A77E)
private val Red = Color(0xFFD93A2B)

@Composable
private fun BigIcon(icon: ImageVector) {
    Box(Modifier.size(62.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.22f)), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(32.dp))
    }
}

/** Uitkomst van een ticketscan aan de deur: groot groen (geldig) of rood met de reden. */
@Composable
fun TicketScanSheet(scan: TicketScan, onDismiss: () -> Unit) {
    val haptics = rememberHaptics()
    LaunchedEffect(scan) { if (scan.isValid) haptics.success() else haptics.error() }
    val reason = when (scan.result) {
        "valid" -> L("Toegang")
        "used" -> scan.checkedInAt?.let { L("Al gebruikt om %@", TkText.clock(it)) } ?: L("Al gebruikt")
        "other_event" -> if (scan.eventName.isBlank()) L("Ticket voor een ander event") else L("Ticket voor een ander event: %@", scan.eventName)
        "cancelled" -> L("Geannuleerd")
        else -> L("Ongeldig ticket")
    }
    FullSheet(onDismiss, L("Scannen"), cancelText = null, confirmText = L("Klaar"), onConfirm = onDismiss) {
        Column(Modifier.fillMaxSize().padding(16.dp).clip(RoundedCornerShape(24.dp)).background(if (scan.isValid) Green else Red).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            BigIcon(if (scan.isValid) Icons.Filled.Check else Icons.Filled.Close)
            Text(if (scan.isValid) L("Geldig") else L("Niet geldig"), color = Color.White, fontSize = 40.sp, fontWeight = FontWeight.Black)
            Text(reason, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            val who = listOf(scan.name, scan.ticketType).filter { it.isNotBlank() }.joinToString(" · ")
            if (who.isNotBlank()) Text(who, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
            if (scan.eventName.isNotBlank()) Text(scan.eventName, color = Color.White.copy(alpha = 0.9f), fontSize = 15.sp)
            scan.checkedIn?.let { inside ->
                Text(L("%lld / %lld binnen", inside, scan.registered ?: scan.capacity ?: 0), color = Color.White, fontWeight = FontWeight.Bold,
                    modifier = Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.2f)).padding(horizontal = 12.dp, vertical = 6.dp))
            }
            Box(Modifier.weight(1f))
            BigButton(if (scan.isValid) L("Volgende scannen") else L("Opnieuw scannen"), onDismiss, color = Color.White.copy(alpha = 0.25f))
        }
    }
}

/** Uitkomst van een klantenkaartscan aan de kassa: de korting die nu geldt, de spaarstand en de knoppen. */
@Composable
fun MemberScanSheet(business: Business, initial: MemberScan, unit: String?, onDismiss: () -> Unit) {
    var scan by remember { mutableStateOf(initial) }
    var points by remember { mutableStateOf(1) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var done by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val usesPoints = (scan.saving?.unit ?: unit) == "points"
    val discount = scan.discountNow
    val bg = when {
        !scan.isValid -> Red
        discount != null -> Color(0xFF6A5CFF)
        else -> Color(0xFF2A2C38)
    }

    fun merge(s: SavingInfo?) {
        if (s != null) scan = scan.copy(saving = if (s.unit == null) s.copy(unit = scan.saving?.unit) else s)
    }

    FullSheet(onDismiss, L("Scannen"), cancelText = null, confirmText = L("Klaar"), onConfirm = onDismiss) {
        Column(Modifier.fillMaxSize().padding(16.dp).clip(RoundedCornerShape(24.dp)).background(bg).verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (!scan.isValid) {
                BigIcon(Icons.Filled.Close)
                Text(L("Niet geldig"), color = Color.White, fontSize = 36.sp, fontWeight = FontWeight.Black)
                Text(if (scan.result == "other_business") L("Deze kaart hoort bij een andere zaak.") else L("Deze klantenkaart is niet bekend."),
                    color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            } else {
                BigIcon(if (discount != null) Icons.Filled.Percent else Icons.Filled.Badge)
                if (discount != null) {
                    Text(L("%@%% korting", TkFormat.percent(discount.percent)), color = Color.White, fontSize = 40.sp, fontWeight = FontWeight.Black)
                    val detail = listOfNotNull(discount.label.takeIf { it.isNotBlank() }, discount.until?.let { L("geldt tot %@", TkText.soon(it)) }).joinToString(" · ")
                    if (detail.isNotBlank()) Text(detail, color = Color.White.copy(alpha = 0.9f), fontSize = 15.sp)
                } else {
                    Text(L("Geen korting vandaag"), color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Black)
                    scan.nextDiscount?.let { n ->
                        val text = listOfNotNull(n.startsAt?.let { TkText.soon(it) }, n.label.takeIf { it.isNotBlank() }, TkFormat.percent(n.percent) + "%").joinToString(" · ")
                        Text(L("Volgende: %@", text), color = Color.White.copy(alpha = 0.9f), fontSize = 15.sp)
                    }
                }
                val member = listOfNotNull(scan.memberName?.takeIf { it.isNotBlank() }, scan.cardName.ifBlank { L("Lid") }, scan.number).joinToString(" · ")
                Text(member, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                scan.saving?.let { saving ->
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Color.White.copy(alpha = 0.15f)).padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(L("Spaarstand"), color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                        LinearProgressIndicator(progress = { minOf(1f, saving.count.toFloat() / saving.target) }, modifier = Modifier.weight(1f),
                            color = Color.White, trackColor = Color.White.copy(alpha = 0.25f))
                        Text("${saving.count}/${saving.target}", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    }
                    if (saving.reward.isNotBlank()) Text(L("Beloning: %@", saving.reward), color = Color.White.copy(alpha = 0.9f), fontSize = 14.sp)
                    if (usesPoints) {
                        Box(Modifier.clip(RoundedCornerShape(12.dp)).background(app.lrvdlinden.pasrzakelijk.ui.Pz.card)) {
                            StepperLine(L("Punten"), points, 1..1000) { points = it }
                        }
                    }
                    BigButton(if (usesPoints) L("Punten registreren") else L("Bezoek registreren"), {
                        busy = true; error = null
                        scope.launch {
                            try {
                                merge(TkApi.visit(business.id, scan.code, if (usesPoints) points else null))
                                done = if (usesPoints) L("%lld punten geregistreerd", points) else L("Bezoek geregistreerd")
                                haptics.success()
                            } catch (e: Exception) { error = e.message; haptics.error() } finally { busy = false }
                        }
                    }, icon = Icons.Filled.Check, color = Color.White, foreground = Color(0xFF6A5CFF), busy = busy)
                    if (saving.canRedeem) {
                        BigButton(L("Beloning inwisselen"), {
                            busy = true; error = null
                            scope.launch {
                                try {
                                    merge(TkApi.redeem(business.id, scan.code))
                                    done = L("Beloning ingewisseld")
                                    haptics.success()
                                } catch (e: Exception) { error = e.message; haptics.error() } finally { busy = false }
                            }
                        }, icon = Icons.Filled.CardGiftcard, color = Color.White.copy(alpha = 0.25f), enabled = !busy)
                    }
                }
            }
            error?.let { Text(it, color = Color.White, fontWeight = FontWeight.Bold) }
            done?.let { Text(it, color = Color.White, fontWeight = FontWeight.Bold) }
        }
    }
}
