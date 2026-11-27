package app.lrvdlinden.pasrzakelijk.ui.tickets

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.core.LogoImage
import app.lrvdlinden.pasrzakelijk.data.Business
import app.lrvdlinden.pasrzakelijk.data.DiscountPeriod
import app.lrvdlinden.pasrzakelijk.data.MemberCard
import app.lrvdlinden.pasrzakelijk.data.TkApi
import app.lrvdlinden.pasrzakelijk.data.TkFormat
import app.lrvdlinden.pasrzakelijk.data.TkText
import app.lrvdlinden.pasrzakelijk.ui.BigButton
import app.lrvdlinden.pasrzakelijk.ui.ConfirmDialog
import app.lrvdlinden.pasrzakelijk.ui.ErrorLine
import app.lrvdlinden.pasrzakelijk.ui.FullSheet
import app.lrvdlinden.pasrzakelijk.ui.Group
import app.lrvdlinden.pasrzakelijk.ui.GroupDivider
import app.lrvdlinden.pasrzakelijk.ui.PillSegments
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.PzField
import app.lrvdlinden.pasrzakelijk.ui.SectionFooter
import app.lrvdlinden.pasrzakelijk.ui.SectionHeader
import app.lrvdlinden.pasrzakelijk.ui.SettingsRow
import app.lrvdlinden.pasrzakelijk.ui.hexColor
import app.lrvdlinden.pasrzakelijk.ui.onCard
import app.lrvdlinden.pasrzakelijk.ui.rememberHaptics
import kotlinx.coroutines.launch
import java.util.Calendar
import java.util.Date

/** Acties → Klantenkaarten: eigen klantenkaart met barcode (eigenaar). De vensters staan in CardsScreen (buiten de lijst). */
@Composable
fun MemberCardsBlock(business: Business, reload: Int, onCreate: () -> Unit, onEdit: (MemberCard) -> Unit, onShare: (MemberCard) -> Unit) {
    var cards by remember(business.id) { mutableStateOf<List<MemberCard>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(business.id, reload) {
        try { cards = TkApi.memberCards(business.id).filter { it.status != "archived" }; error = null }
        catch (e: Exception) { error = L("Klantenkaarten laden mislukt.") + " " + (e.message ?: "") }
    }
    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
        Text(L("Klantenkaarten"), fontWeight = FontWeight.Bold, color = Pz.text)
        if (cards.isEmpty()) Text(L("Nog geen klantenkaart. Maak er een met je eigen logo, kleur en barcode."), color = Pz.muted)
        if (cards.isNotEmpty()) Group {
            cards.forEachIndexed { i, card ->
                if (i > 0) GroupDivider()
                MemberCardRow(card) { onEdit(card) }
                if (card.isPublished) {
                    TextButton(onClick = { onShare(card) }, modifier = Modifier.padding(horizontal = 8.dp)) {
                        Icon(Icons.Filled.QrCode, null, tint = Pz.accent, modifier = Modifier.size(18.dp))
                        Text("  " + L("Delen: link, QR en knop voor je website"), color = Pz.accent, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
        TextButton(onClick = onCreate) { Text("+ " + L("Klantenkaart aanmaken"), color = Pz.accent) }
        error?.let { ErrorLine(it) }
        SectionFooter(L("Pasr maakt de kaartnummers zelf (QR, Code 128 of EAN-13). Scannen gaat met Pasr Zakelijk."))
    }
}

/** Delen van een klantenkaart (link /add/m/<id>). */
@Composable
fun MemberCardShareSheet(card: MemberCard, onDismiss: () -> Unit) {
    TkShareSheet(card.name, card.addUrl,
        L("Klanten scannen deze code of openen de link en zetten je klantenkaart in Pasr en Wallet."),
        L("Klanten zetten je klantenkaart met één tik in Pasr. Zonder Pasr opent pasr.nl met de downloadknoppen."), onDismiss)
}

@Composable
private fun MemberCardRow(card: MemberCard, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)).background(hexColor(card.color)), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.QrCode, null, tint = onCard(card.color), modifier = Modifier.size(20.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(card.name, color = Pz.text, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(L("%lld leden", card.members), color = Pz.muted, fontSize = 14.sp)
            val now = card.discountNow
            val next = card.nextDiscount?.startsAt
            if (now != null) Text(L("Nu %@%% korting", TkFormat.percent(now.percent)), color = Pz.mint, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            else if (next != null) Text(L("Volgende korting: %@", TkText.soon(next)), color = Pz.muted, fontSize = 12.sp)
        }
        TkStatusPill(card.status)
    }
}

// Klantenkaart maken of bewerken

@Composable
fun MemberCardEditorSheet(business: Business, initial: MemberCard, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var card by remember { mutableStateOf(initial) }
    var logoChanged by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var period by remember { mutableStateOf<DiscountPeriod?>(null) }
    var timeline by remember { mutableStateOf(false) }
    var confirmArchive by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val isNew = initial.id.isEmpty()
    val g = card.goals
    val goalsChosen = g.membership || g.savingEnabled || g.fixedEnabled || g.periods.isNotEmpty()
    val valid = card.name.isNotBlank() && goalsChosen && (!g.savingEnabled || g.savingReward.isNotBlank())

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        uri ?: return@rememberLauncherForActivityResult
        val bmp: Bitmap? = runCatching {
            if (Build.VERSION.SDK_INT >= 28) ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { d, _, _ ->
                d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
            else @Suppress("DEPRECATION") MediaStore.Images.Media.getBitmap(context.contentResolver, uri)
        }.getOrNull()
        val encoded = bmp?.let { LogoImage.encode(it) }
        if (encoded != null) { card = card.copy(logo = encoded); logoChanged = true } else message = L("Dit bestand is geen afbeelding.")
    }

    fun save(status: String) {
        busy = true; message = null
        scope.launch {
            try {
                TkApi.saveMemberCard(card, business.id, status, logoChanged)
                haptics.success()
                onDismiss()
            } catch (e: Exception) { message = e.message; haptics.error() } finally { busy = false }
        }
    }

    FullSheet(onDismiss, if (isNew) L("Nieuwe klantenkaart") else L("Klantenkaart bewerken"), confirmText = L("Opslaan"),
        confirmEnabled = valid && !busy, busy = busy, onConfirm = { save(card.status) }) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).imePadding().padding(16.dp)) {
            MemberCardPreview(card, business.name, memberName = "Anna de Vries")
            SectionHeader(L("Kaart"))
            PzField(card.name, { card = card.copy(name = it) }, L("Naam (bijv. Korenschoof Klantenkaart)"))
            Spacer(Modifier.height(8.dp))
            Group {
                TkColorRow(card.color, allowDefault = false) { c -> if (c != null) card = card.copy(color = c) }
                GroupDivider()
                SettingsRow(if (card.logo == null) L("Logo kiezen") else L("Ander logo kiezen"),
                    onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) })
                if (card.logo != null) {
                    GroupDivider()
                    SettingsRow(L("Logo weghalen"), titleColor = Pz.coral, onClick = { card = card.copy(logo = null); logoChanged = true })
                }
            }
            SectionHeader(L("Barcode"))
            PillSegments(listOf("qr" to L("QR-code"), "code128" to L("Code 128"), "ean13" to L("EAN-13")), card.barcodeType) {
                card = card.copy(barcodeType = it)
            }
            Spacer(Modifier.height(8.dp))
            if (card.barcodeType != "ean13") {
                PzField(card.prefix, { card = card.copy(prefix = it.take(8)) }, L("Voorvoegsel kaartnummer (bijv. KS-)"),
                    capitalization = KeyboardCapitalization.Characters, autoCorrect = false)
            }
            Text(L("Nummering") + ": " + card.sampleNumber, color = Pz.muted, fontSize = 14.sp, modifier = Modifier.padding(start = 6.dp, top = 8.dp))
            SectionFooter(L("Pasr maakt de nummers zelf. Scannen gaat met Pasr Zakelijk; koppelen met je eigen kassa komt later."))
            SectionHeader(L("Doel van de kaart · kies er één of meer"))
            Group {
                ToggleLine(L("Lidmaatschap of herkenning"), g.membership, L("De klant laat zijn kaart zien; jij ziet wie het is.")) {
                    card = card.copy(goals = g.copy(membership = it))
                }
                GroupDivider()
                ToggleLine(L("Sparen voor een beloning"), g.savingEnabled, L("Elke scan telt als bezoek of punten.")) {
                    card = card.copy(goals = g.copy(savingEnabled = it))
                }
                if (g.savingEnabled) {
                    Column(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        PillSegments(listOf("visits" to L("Bezoeken"), "points" to L("Punten")), g.savingUnit) {
                            card = card.copy(goals = g.copy(savingUnit = it))
                        }
                    }
                    StepperLine(if (g.savingUnit == "points") L("Beloning na (punten)") else L("Beloning na (bezoeken)"), g.savingTarget, 2..10_000,
                        if (g.savingTarget >= 50) 10 else 1) { card = card.copy(goals = g.copy(savingTarget = it)) }
                    Box(Modifier.padding(horizontal = 12.dp, vertical = 6.dp)) {
                        PzField(g.savingReward, { card = card.copy(goals = g.copy(savingReward = it)) }, L("Beloning (bijv. gratis gebakje naar keuze)"))
                    }
                }
                GroupDivider()
                ToggleLine(L("Vaste korting"), g.fixedEnabled, L("Altijd hetzelfde percentage voor leden.")) {
                    card = card.copy(goals = g.copy(fixedEnabled = it))
                }
                if (g.fixedEnabled) {
                    StepperLine(L("Korting"), g.fixedPercent.toInt(), 1..100, suffix = "%") { card = card.copy(goals = g.copy(fixedPercent = it.toDouble())) }
                }
            }
            SectionHeader(L("Korting in een periode"))
            PillSegments(listOf(false to L("Lijst"), true to L("Tijdlijn")), timeline) { timeline = it }
            Spacer(Modifier.height(8.dp))
            if (timeline) PeriodTimeline(g.periods)
            else Group {
                if (g.periods.isEmpty()) Text(L("Nog geen kortingsperiodes"), color = Pz.muted, modifier = Modifier.padding(16.dp))
                g.periods.forEachIndexed { i, p ->
                    if (i > 0) GroupDivider()
                    Column(Modifier.fillMaxWidth().clickable { period = p }.padding(horizontal = 16.dp, vertical = 10.dp)) {
                        Text(p.label.ifBlank { L("%@%% korting", TkFormat.percent(p.percent)) }, color = Pz.text, fontWeight = FontWeight.SemiBold)
                        Text(p.summary(), color = Pz.muted, fontSize = 13.sp)
                    }
                }
            }
            TextButton(onClick = { period = DiscountPeriod() }) { Text("+ " + L("Periode toevoegen"), color = Pz.accent) }
            SectionFooter(L("Van–tot, eventueel alleen op bepaalde dagen of uren. Plan meerdere periodes vooruit."))
            message?.let { Spacer(Modifier.height(10.dp)); ErrorLine(it) }
            if (!goalsChosen) SectionFooter(L("Kies minstens één doel voor de kaart."))
            Spacer(Modifier.height(16.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (card.isPublished) {
                    BigButton(L("Offline halen (concept)"), { save("draft") }, enabled = valid && !busy, color = Pz.card2, foreground = Pz.text)
                } else {
                    BigButton(L("Online zetten"), { save("published") }, enabled = valid && !busy && business.isApproved, color = Pz.mint, foreground = Color.Black)
                    BigButton(L("Concept bewaren"), { save("draft") }, enabled = valid && !busy, color = Pz.card2, foreground = Pz.text)
                    if (!business.isApproved) SectionFooter(L("Je zaak is nog niet goedgekeurd. Online zetten kan pas daarna."))
                }
                if (!isNew) BigButton(L("Archiveren"), { confirmArchive = true }, enabled = !busy, color = Pz.coral)
            }
            Spacer(Modifier.height(24.dp))
        }
    }
    period?.let { p ->
        PeriodEditorSheet(p, onSave = { updated ->
            val list = card.goals.periods
            val next = if (list.any { it.key == updated.key }) list.map { if (it.key == updated.key) updated else it } else list + updated
            card = card.copy(goals = card.goals.copy(periods = next))
            period = null
        }, onDelete = {
            card = card.copy(goals = card.goals.copy(periods = card.goals.periods.filter { it.key != p.key }))
            period = null
        }, onDismiss = { period = null })
    }
    if (confirmArchive) {
        ConfirmDialog(L("Klantenkaart archiveren?"), L("Klanten kunnen de kaart dan niet meer toevoegen en scannen werkt niet meer."),
            L("Archiveren"), destructive = true, onConfirm = { save("archived") }, onDismiss = { confirmArchive = false })
    }
}

@Composable
private fun PeriodEditorSheet(initial: DiscountPeriod, onSave: (DiscountPeriod) -> Unit, onDelete: () -> Unit, onDismiss: () -> Unit) {
    var p by remember { mutableStateOf(initial) }
    FullSheet(onDismiss, L("Kortingsperiode"), confirmText = L("Klaar"),
        onConfirm = { onSave(if (p.endsOn.before(p.startsOn)) p.copy(endsOn = p.startsOn) else p) }) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).imePadding().padding(16.dp)) {
            SectionHeader(L("Korting"))
            PzField(p.label, { p = p.copy(label = it) }, L("Label (bijv. happy hour)"))
            Spacer(Modifier.height(8.dp))
            Group { StepperLine(L("Percentage"), p.percent.toInt(), 1..100, suffix = "%") { p = p.copy(percent = it.toDouble()) } }
            SectionHeader(L("Periode"))
            Group {
                DateTimeLine(L("Van"), p.startsOn, withTime = false) { p = p.copy(startsOn = it) }
                GroupDivider()
                DateTimeLine(L("Tot en met"), p.endsOn, withTime = false) { p = p.copy(endsOn = it) }
            }
            SectionHeader(L("Weekdagen"))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (day in 1..7) {
                    val on = day in p.weekdays
                    Box(Modifier.weight(1f).height(36.dp).clip(RoundedCornerShape(9.dp)).background(if (on) Pz.iris else Pz.card2)
                        .clickable { p = p.copy(weekdays = if (on) p.weekdays - day else p.weekdays + day) }, contentAlignment = Alignment.Center) {
                        Text(TkText.weekday(day), color = if (on) Color.White else Pz.text, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
            SectionFooter(L("Niets gekozen = elke dag."))
            SectionHeader(L("Tijden"))
            Group {
                ToggleLine(L("Alleen tussen bepaalde tijden"), p.fromTime != null) { on ->
                    p = p.copy(fromTime = if (on) "17:00" else null, toTime = if (on) "19:00" else null)
                }
                val from = p.fromTime
                val to = p.toTime
                if (from != null && to != null) {
                    GroupDivider()
                    DateTimeLine(L("Van"), TkFormat.parseTime(from) ?: Date(), withDate = false) { p = p.copy(fromTime = TkFormat.time(it)) }
                    GroupDivider()
                    DateTimeLine(L("Tot"), TkFormat.parseTime(to) ?: Date(), withDate = false) { p = p.copy(toTime = TkFormat.time(it)) }
                }
            }
            Spacer(Modifier.height(16.dp))
            BigButton(L("Periode verwijderen"), onDelete, color = Pz.coral)
            Spacer(Modifier.height(24.dp))
        }
    }
}

/** Tijdlijn van één maand met de kortingsperiodes als balken. */
@Composable
private fun PeriodTimeline(periods: List<DiscountPeriod>) {
    var month by remember {
        mutableStateOf(TkFormat.calendar().apply {
            set(Calendar.DAY_OF_MONTH, 1); set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.time)
    }
    val cal = TkFormat.calendar(month)
    val days = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
    val end = Date(month.time + (days - 1) * 86_400_000L + 3_600_000L)
    val visible = periods.filter { !it.endsOn.before(month) && !it.startsOn.after(end) }
    val colors = listOf(Pz.iris, Color(0xFF0F6E6E), Pz.coral, Pz.amber)
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Pz.card).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { month = TkFormat.calendar(month).apply { add(Calendar.MONTH, -1) }.time }) {
                Icon(Icons.Filled.ChevronLeft, L("Vorige maand"), tint = Pz.accent)
            }
            Text(TkText.monthYear(month), color = Pz.text, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            IconButton(onClick = { month = TkFormat.calendar(month).apply { add(Calendar.MONTH, 1) }.time }) {
                Icon(Icons.Filled.ChevronRight, L("Volgende maand"), tint = Pz.accent)
            }
        }
        if (visible.isEmpty()) Text(L("Geen korting in deze maand"), color = Pz.muted, fontSize = 14.sp)
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val unit = maxWidth / days
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                visible.forEachIndexed { i, p ->
                    val first = maxOf(0, ((p.startsOn.time - month.time) / 86_400_000L).toInt())
                    val last = minOf(days - 1, ((p.endsOn.time - month.time) / 86_400_000L).toInt())
                    val label = (if (p.label.isBlank()) "" else p.label + " · ") + TkFormat.percent(p.percent) + "%"
                    Text(label, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.offset(x = unit * first).width(unit * maxOf(1, last - first + 1)).height(24.dp)
                            .clip(RoundedCornerShape(6.dp)).background(colors[i % colors.size].copy(alpha = if (p.weekdays.isEmpty() && p.fromTime == null) 1f else 0.7f))
                            .padding(horizontal = 6.dp, vertical = 4.dp))
                }
            }
        }
    }
}
