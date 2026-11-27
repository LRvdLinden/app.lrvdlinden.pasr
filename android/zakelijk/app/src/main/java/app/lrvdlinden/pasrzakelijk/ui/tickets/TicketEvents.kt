package app.lrvdlinden.pasrzakelijk.ui.tickets

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.core.Geo
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.data.Business
import app.lrvdlinden.pasrzakelijk.data.EventRegistration
import app.lrvdlinden.pasrzakelijk.data.TicketEvent
import app.lrvdlinden.pasrzakelijk.data.TicketType
import app.lrvdlinden.pasrzakelijk.data.TkApi
import app.lrvdlinden.pasrzakelijk.data.TkFormat
import app.lrvdlinden.pasrzakelijk.data.TkText
import app.lrvdlinden.pasrzakelijk.ui.BigButton
import app.lrvdlinden.pasrzakelijk.ui.ErrorLine
import app.lrvdlinden.pasrzakelijk.ui.FullSheet
import app.lrvdlinden.pasrzakelijk.ui.Group
import app.lrvdlinden.pasrzakelijk.ui.GroupDivider
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.PzField
import app.lrvdlinden.pasrzakelijk.ui.SectionFooter
import app.lrvdlinden.pasrzakelijk.ui.SectionHeader
import app.lrvdlinden.pasrzakelijk.ui.hexColor
import app.lrvdlinden.pasrzakelijk.ui.rememberHaptics
import kotlinx.coroutines.launch
import java.util.Date

/** Acties → Tickets: gratis events van de zaak (eigenaar). De vensters staan in CardsScreen (buiten de lijst). */
@Composable
fun TicketEventsBlock(business: Business, reload: Int, onCreate: () -> Unit, onOpen: (TicketEvent) -> Unit) {
    var events by remember(business.id) { mutableStateOf<List<TicketEvent>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(business.id, reload) {
        try { events = TkApi.events(business.id); error = null }
        catch (e: Exception) { error = L("Events laden mislukt.") + " " + (e.message ?: "") }
    }
    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
        Text(L("Tickets"), fontWeight = FontWeight.Bold, color = Pz.text)
        if (events.isEmpty()) Text(L("Nog geen events. Maak een gratis event met tickets en QR-code."), color = Pz.muted)
        if (events.isNotEmpty()) Group {
            events.forEachIndexed { i, event ->
                if (i > 0) GroupDivider()
                EventRow(event) { onOpen(event) }
            }
        }
        TextButton(onClick = onCreate) { Text("+ " + L("Event aanmaken"), color = Pz.accent) }
        error?.let { ErrorLine(it) }
        SectionFooter(L("Alleen gratis tickets. Klanten melden zich aan via de link of QR-code en krijgen hun ticket in Pasr en Wallet."))
    }
}

@Composable
private fun EventRow(event: TicketEvent, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)).background(hexColor(event.color ?: "#24346B")), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.ConfirmationNumber, null, tint = Color.White, modifier = Modifier.size(20.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(event.name, color = Pz.text, fontWeight = FontWeight.Bold, maxLines = 1)
            Text(TkText.eventLine(event.startsAt, event.endsAt), color = Pz.muted, fontSize = 14.sp)
            Text(L("%lld/%lld aangemeld", event.registered, event.capacity), color = Pz.muted, fontSize = 12.sp)
        }
        TkStatusPill(event.status)
    }
}

// Event maken of bewerken

@Composable
fun EventEditorSheet(business: Business, initial: TicketEvent, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var event by remember { mutableStateOf(initial) }
    var busy by remember { mutableStateOf(false) }
    var locating by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val isNew = initial.id.isEmpty()
    val valid = event.name.isNotBlank() && event.endsAt.after(event.startsAt) && event.capacity > 0 && event.ticketTypes.any { it.name.isNotBlank() }

    fun save(status: String) {
        busy = true; message = null
        scope.launch {
            try {
                TkApi.saveEvent(event, business.id, status)
                haptics.success()
                onDismiss()
            } catch (e: Exception) { message = e.message; haptics.error() } finally { busy = false }
        }
    }

    FullSheet(onDismiss, if (isNew) L("Nieuw event") else L("Event bewerken"), confirmText = L("Opslaan"), confirmEnabled = valid && !busy,
        busy = busy, onConfirm = { save(event.status) }) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).imePadding().padding(16.dp)) {
            SectionHeader(L("Event"))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                PzField(event.name, { event = event.copy(name = it) }, L("Naam (bijv. Winterborrel)"))
                PzField(event.description, { event = event.copy(description = it) }, L("Omschrijving"), singleLine = false, minLines = 3)
            }
            SectionHeader(L("Datum en tijd"))
            Group {
                DateTimeLine(L("Begint"), event.startsAt) { d ->
                    val length = maxOf(3600_000L, event.endsAt.time - event.startsAt.time)
                    event = event.copy(startsAt = d, endsAt = if (event.endsAt.after(d)) event.endsAt else Date(d.time + length))
                }
                GroupDivider()
                DateTimeLine(L("Eindigt"), event.endsAt) { event = event.copy(endsAt = it) }
                GroupDivider()
                ToggleLine(L("Deuren open"), event.doorsAt != null) { on ->
                    event = event.copy(doorsAt = if (on) Date(event.startsAt.time - 15 * 60_000L) else null)
                }
                event.doorsAt?.let { doors ->
                    GroupDivider()
                    DateTimeLine(L("Deuren open om"), doors) { event = event.copy(doorsAt = it) }
                }
            }
            SectionHeader(L("Adres"))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                PzField(event.address, { event = event.copy(address = it, lat = null, lng = null) }, L("Adres"), modifier = Modifier.weight(1f))
                if (locating) CircularProgressIndicator(Modifier.size(24.dp), color = Pz.accent)
                else IconButton(onClick = {
                    locating = true
                    scope.launch {
                        val p = Geo.locate(context, event.address)
                        if (p != null) event = event.copy(lat = p.first, lng = p.second)
                        else message = L("Dit adres is niet gevonden. Controleer het en probeer opnieuw.")
                        locating = false
                    }
                }, enabled = event.address.trim().length >= 4) { Icon(Icons.Filled.Search, L("Zoek"), tint = Pz.accent) }
            }
            if (event.lat != null && event.lng != null) {
                Text(L("Locatie gevonden") + " · " + String.format(java.util.Locale.US, "%.5f, %.5f", event.lat, event.lng), color = Pz.mint, fontSize = 13.sp,
                    modifier = Modifier.padding(start = 6.dp, top = 6.dp))
            }
            SectionFooter(L("Met Zoek komt het event op de kaart; klanten krijgen dan een route."))
            SectionHeader(L("Plekken en aanmelden"))
            Group {
                StepperLine(L("Aantal plekken"), event.capacity, 1..100_000, if (event.capacity >= 100) 10 else 1) { event = event.copy(capacity = it) }
                GroupDivider()
                StepperLine(L("Max. per persoon"), event.maxPerPerson, 1..20) { event = event.copy(maxPerPerson = it) }
                GroupDivider()
                ToggleLine(L("Aanmelden tot een datum"), event.signupUntil != null) { on ->
                    event = event.copy(signupUntil = if (on) Date(event.startsAt.time - 4 * 3600_000L) else null)
                }
                event.signupUntil?.let { until ->
                    GroupDivider()
                    DateTimeLine(L("Aanmelden tot"), until) { event = event.copy(signupUntil = it) }
                }
                GroupDivider()
                ToggleLine(L("Wachtlijst"), event.waitlist, L("Bij vol: aanmelden op de wachtlijst, automatisch doorschuiven")) {
                    event = event.copy(waitlist = it)
                }
            }
            SectionHeader(L("Ticketsoorten (allemaal gratis)"))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                event.ticketTypes.forEach { type ->
                    TicketTypeLine(type, canDelete = event.ticketTypes.size > 1,
                        onChange = { t -> event = event.copy(ticketTypes = event.ticketTypes.map { if (it.key == t.key) t else it }) },
                        onDelete = { event = event.copy(ticketTypes = event.ticketTypes.filter { it.key != type.key }) })
                }
                TextButton(onClick = { event = event.copy(ticketTypes = event.ticketTypes + TicketType()) }) {
                    Icon(Icons.Filled.Add, null, tint = Pz.accent); Text(" " + L("Soort toevoegen"), color = Pz.accent)
                }
            }
            SectionFooter(L("Minstens één soort. Laat plekken leeg om de plekken van het event te delen."))
            SectionHeader(L("Branding"))
            Group { TkColorRow(event.color) { event = event.copy(color = it) } }
            Spacer(Modifier.height(8.dp))
            PzField(event.headerUrl ?: "", { event = event.copy(headerUrl = it) }, L("Header-afbeelding (link, optioneel)"), keyboardType = KeyboardType.Uri, autoCorrect = false)
            SectionFooter(L("Standaard het logo en de kleur van je zaak."))
            SectionFooter(L("Bij aanmelden vragen we voornaam, achternaam, e-mailadres en geboortedatum (verplicht). Op het ticket staat alleen de naam; de QR-code bevat geen persoonsgegevens."))
            message?.let { Spacer(Modifier.height(10.dp)); ErrorLine(it) }
            Spacer(Modifier.height(16.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (!event.isPublished && !event.isCancelled) {
                    BigButton(L("Online zetten"), { save("published") }, enabled = valid && !busy && business.isApproved, color = Pz.mint, foreground = Color.Black)
                    BigButton(L("Concept bewaren"), { save("draft") }, enabled = valid && !busy, color = Pz.card2, foreground = Pz.text)
                    if (!business.isApproved) SectionFooter(L("Je zaak is nog niet goedgekeurd. Online zetten kan pas daarna."))
                } else if (event.isPublished) {
                    BigButton(L("Offline halen (concept)"), { save("draft") }, enabled = valid && !busy, color = Pz.card2, foreground = Pz.text)
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun TicketTypeLine(type: TicketType, canDelete: Boolean, onChange: (TicketType) -> Unit, onDelete: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        PzField(type.name, { onChange(type.copy(name = it)) }, L("Naam (bijv. Toegang)"), modifier = Modifier.weight(1f))
        PzField(type.capacity?.toString() ?: "", { v -> onChange(type.copy(capacity = v.filter { it.isDigit() }.take(6).toIntOrNull())) },
            L("Plekken"), modifier = Modifier.weight(0.6f), keyboardType = KeyboardType.Number)
        if (canDelete) IconButton(onClick = onDelete) { Icon(Icons.Filled.Delete, L("Verwijderen"), tint = Pz.coral) }
    }
}

// Overzicht van een event

@Composable
fun EventDetailSheet(business: Business, initial: TicketEvent, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var event by remember { mutableStateOf(initial) }
    var rows by remember { mutableStateOf<List<EventRegistration>>(emptyList()) }
    var search by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf(false) }
    var sharing by remember { mutableStateOf(false) }
    var askCancel by remember { mutableStateOf(false) }
    var cancelMessage by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var tick by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(tick) {
        try {
            TkApi.events(business.id).firstOrNull { it.id == event.id }?.let { event = it }
            rows = TkApi.registrations(business.id, event.id)
            error = null
        } catch (e: Exception) { error = e.message }
    }
    val q = search.trim().lowercase()
    val filtered = if (q.isEmpty()) rows else rows.filter { it.fullName.lowercase().contains(q) || it.email.lowercase().contains(q) }

    FullSheet(onDismiss, event.name, cancelText = L("Klaar"), confirmText = if (event.isCancelled) null else L("Bewerken"),
        onConfirm = { editing = true }) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).imePadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            EventStats(event)
            if (event.isPublished) BigButton(L("Delen: link, QR en knop voor je website"), { sharing = true }, icon = Icons.Filled.QrCode)
            if (rows.isNotEmpty()) BigButton(L("Exporteer CSV"), { shareCsv(context, event, rows) }, color = Pz.card2, foreground = Pz.text)
            if (!event.isCancelled && !event.isPast) {
                BigButton(L("Event annuleren"), { askCancel = true }, enabled = !busy, color = Pz.coral)
            }
            SectionFooter(L("Scannen aan de deur gaat via Scannen. Kies daar dit event om alleen deze tickets toe te laten."))
            SectionHeader(L("Aanmeldingen"))
            PzField(search, { search = it }, L("Zoek op naam of e-mail"))
            if (rows.isEmpty()) Text(L("Nog geen aanmeldingen"), color = Pz.muted)
            if (filtered.isNotEmpty()) Group {
                filtered.forEachIndexed { i, r ->
                    if (i > 0) GroupDivider()
                    RegistrationLine(r)
                }
            }
            SectionFooter(L("Geboortedatum en e-mail zie alleen jij; ze staan niet op het ticket en niet in de QR-code."))
            error?.let { ErrorLine(it) }
        }
    }
    if (editing) EventEditorSheet(business, event) { editing = false; tick++ }
    if (sharing) TkShareSheet(event.name, event.addUrl,
        L("Klanten scannen deze code of openen de link en melden zich gratis aan. Hun ticket komt in Pasr en Wallet."),
        L("Klanten melden zich met één tik aan voor je event in Pasr. Zonder Pasr opent pasr.nl.")) { sharing = false }
    if (askCancel) {
        AlertDialog(
            onDismissRequest = { askCancel = false },
            title = { Text(L("Event annuleren?")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(L("Iedereen die zich heeft aangemeld krijgt een mail en melding met je bericht. Dit kan niet ongedaan worden gemaakt."))
                    PzField(cancelMessage, { cancelMessage = it }, L("Bericht aan de aanmeldingen"), singleLine = false, minLines = 2)
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    askCancel = false
                    busy = true
                    scope.launch {
                        try { TkApi.cancelEvent(business.id, event.id, cancelMessage); cancelMessage = ""; tick++ }
                        catch (e: Exception) { error = e.message } finally { busy = false }
                    }
                }) { Text(L("Event annuleren"), color = Pz.coral, fontWeight = FontWeight.Bold) }
            },
            dismissButton = { TextButton(onClick = { askCancel = false }) { Text(L("Terug"), color = Pz.accent) } },
            containerColor = Pz.card,
        )
    }
}

@Composable
fun EventStats(event: TicketEvent) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Pz.card).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(TkText.eventLine(event.startsAt, event.endsAt), color = Pz.muted, fontSize = 14.sp, modifier = Modifier.weight(1f))
            TkStatusPill(event.status)
        }
        if (event.address.isNotBlank()) Text(event.address, color = Pz.muted, fontSize = 14.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StatTile(L("Aangemeld"), "${event.registered} / ${event.capacity}", Pz.iris, Modifier.weight(1f))
            StatTile(L("Binnen"), "${event.checkedIn}", Pz.mint, Modifier.weight(1f))
            StatTile(L("Wachtlijst"), "${event.waiting}", Pz.amber, Modifier.weight(1f))
        }
        LinearProgressIndicator(progress = { if (event.capacity > 0) minOf(1f, event.registered.toFloat() / event.capacity) else 0f },
            modifier = Modifier.fillMaxWidth(), color = Pz.iris, trackColor = Pz.card2)
        Text(L("%lld plekken vrij", event.spotsLeft), color = Pz.muted, fontSize = 12.sp)
    }
}

@Composable
private fun StatTile(title: String, value: String, color: Color, modifier: Modifier) {
    Column(modifier.clip(RoundedCornerShape(12.dp)).background(Pz.card2).padding(10.dp)) {
        Text(title, color = Pz.muted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        Text(value, color = color, fontSize = 20.sp, fontWeight = FontWeight.Black)
    }
}

@Composable
private fun RegistrationLine(r: EventRegistration) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(r.fullName, color = Pz.text, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            when (r.status) {
                "checked_in" -> Pill(r.checkedInAt?.let { L("Binnen %@", TkText.clock(it)) } ?: L("Binnen"), Pz.mint)
                "waitlist" -> Pill(L("Wachtlijst"), Pz.amber)
                "cancelled" -> Pill(L("Afgemeld"), Pz.coral)
                else -> Pill(L("Aangemeld"), Pz.iris)
            }
        }
        Text(r.email, color = Pz.muted, fontSize = 13.sp)
        Text(listOfNotNull(r.birthDate?.let { TkText.dateNumeric(it) }, r.ticketType.takeIf { it.isNotBlank() }).joinToString(" · "),
            color = Pz.muted, fontSize = 13.sp)
    }
}

/** Aanmeldingen als CSV delen (alleen voor de eigenaar; via het deelvenster van Android). */
private fun shareCsv(context: android.content.Context, event: TicketEvent, rows: List<EventRegistration>) {
    fun esc(s: String) = "\"" + s.replace("\"", "\"\"") + "\""
    val text = buildString {
        append("voornaam;achternaam;email;geboortedatum;ticketsoort;status;aangemeld;binnen\n")
        for (r in rows) {
            append(listOf(r.firstName, r.lastName, r.email, r.birthDate?.let { TkFormat.day(it) } ?: "", r.ticketType, r.status,
                r.createdAt?.let { TkFormat.timestamp(it) } ?: "", r.checkedInAt?.let { TkFormat.timestamp(it) } ?: "").joinToString(";") { esc(it) })
            append('\n')
        }
    }
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "text/csv"
        putExtra(Intent.EXTRA_SUBJECT, event.name)
        putExtra(Intent.EXTRA_TEXT, text)
    }
    runCatching { context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}
