package app.lrvdlinden.pasrzakelijk.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.PersonAddAlt1
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material3.AlertDialog
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.data.Account
import app.lrvdlinden.pasrzakelijk.data.Business
import app.lrvdlinden.pasrzakelijk.data.BusinessApi
import app.lrvdlinden.pasrzakelijk.data.BusinessRole
import app.lrvdlinden.pasrzakelijk.data.BusinessStatus
import app.lrvdlinden.pasrzakelijk.data.BusinessStore
import kotlinx.coroutines.launch

/** Formulier voor de gegevens van de zaak (aanmelden of wijzigen). */
@Composable
private fun BusinessForm(
    existing: Business?,
    name: String, onName: (String) -> Unit,
    city: String, onCity: (String) -> Unit,
    website: String, onWebsite: (String) -> Unit,
    note: String, onNote: (String) -> Unit,
    message: String?,
) {
    Column(Modifier.padding(bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ZakelijkLogo(22f)
        Text(if (existing == null) L("Meld je zaak aan") else L("Gegevens van je zaak"), fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Pz.text)
        Text(L("De naam en plaats komen op je stempelkaart. Pasr kijkt je aanmelding na; daarna kun je kaarten publiceren en stempels zetten."), color = Pz.muted, fontSize = 15.sp)
    }
    SectionHeader(L("Zaak"))
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PzField(name, onName, L("Naam van je zaak"), capitalization = KeyboardCapitalization.Words)
        PzField(city, onCity, L("Plaats"), capitalization = KeyboardCapitalization.Words)
        PzField(website, { onWebsite(it.trim()) }, L("Website (bijv. jouwzaak.nl)"), keyboardType = KeyboardType.Uri,
            capitalization = KeyboardCapitalization.None, autoCorrect = false)
    }
    SectionFooter(L("Met je website neemt Pasr je logo en kleuren over op je stempelkaart."))
    Spacer(Modifier.height(10.dp))
    PzField(note, onNote, L("Wat voor zaak is het? (optioneel)"), singleLine = false, minLines = 2)
    SectionFooter(L("Je e-mailadres blijft privé."))
    message?.let { Spacer(Modifier.height(8.dp)); ErrorLine(it) }
}

/** Zaak aanmelden (als je nog geen zaak hebt). Daarna kijkt Pasr de aanmelding na. */
@Composable
fun RegisterBusinessScreen() {
    var name by rememberSaveable { mutableStateOf("") }
    var city by rememberSaveable { mutableStateOf("") }
    var website by rememberSaveable { mutableStateOf("") }
    var note by rememberSaveable { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var askInvite by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()

    Box(Modifier.fillMaxSize().background(Pz.bg), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.widthIn(max = 560.dp).fillMaxWidth().safeDrawingPadding().imePadding()
                .verticalScroll(rememberScrollState()).padding(20.dp),
        ) {
            BusinessForm(null, name, { name = it }, city, { city = it }, website, { website = it }, note, { note = it }, message)
            Spacer(Modifier.height(18.dp))
            BigButton(L("Aanmelden"), {
                busy = true; message = null
                scope.launch {
                    try {
                        BusinessApi.register(name.trim(), city.trim(), website.ifBlank { null }, note.ifBlank { null })
                        haptics.success()
                        BusinessStore.load()
                    } catch (e: Exception) { message = e.message; haptics.error() } finally { busy = false }
                }
            }, enabled = name.trim().length >= 2, busy = busy)
            Spacer(Modifier.height(20.dp))
            Group {
                SettingsRow(L("Ik heb een uitnodiging als medewerker"), titleColor = Pz.accent, onClick = { askInvite = true })
                GroupDivider()
                SettingsRow(L("Uitloggen"), titleColor = Pz.coral, onClick = { scope.launch { Account.signOut() } })
            }
            SectionFooter(L("Werk je bij een zaak? Open de uitnodigingslink die je van de eigenaar kreeg, of plak de code hier."))
        }
    }
    if (askInvite) InviteCodeDialog { askInvite = false }
}

/** Code of link van een uitnodiging plakken. */
@Composable
fun InviteCodeDialog(onDismiss: () -> Unit) {
    var code by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(L("Uitnodiging")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(L("Plak de link of de code uit de uitnodiging."))
                PzField(code, { code = it }, L("Code"), capitalization = KeyboardCapitalization.None, autoCorrect = false)
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val c = code.trim()
                if (Regex("^[a-zA-Z][a-zA-Z0-9+.-]*://").containsMatchIn(c)) BusinessStore.handle(android.net.Uri.parse(c))
                else if (c.isNotEmpty()) BusinessStore.pendingInvite = c
                onDismiss()
            }) { Text(L("Verder"), fontWeight = FontWeight.Bold, color = Pz.accent) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(L("Annuleer"), color = Pz.accent) } },
        containerColor = Pz.card,
    )
}

/** Gegevens van de zaak wijzigen (eigenaar), met aanbod om de huisstijl opnieuw op te halen bij een nieuwe website. */
@Composable
fun EditBusinessSheet(existing: Business, onDismiss: () -> Unit) {
    var name by rememberSaveable { mutableStateOf(existing.name) }
    var city by rememberSaveable { mutableStateOf(existing.city) }
    var website by rememberSaveable { mutableStateOf(existing.website ?: "") }
    var note by rememberSaveable { mutableStateOf(existing.note ?: "") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var offerBrand by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()

    FullSheet(onDismiss, L("Gegevens van je zaak"), confirmText = L("Opslaan"), confirmEnabled = name.trim().length >= 2, busy = busy, onConfirm = {
        busy = true; message = null
        scope.launch {
            try {
                BusinessApi.register(name.trim(), city.trim(), website.ifBlank { null }, note.ifBlank { null })
                haptics.success()
                BusinessStore.load()
                val old = (existing.website ?: "").trim()
                val new = website.trim()
                if (new.isNotEmpty() && new != old && existing.isOwner && existing.cards.isNotEmpty()) offerBrand = true else onDismiss()
            } catch (e: Exception) { message = e.message; haptics.error() } finally { busy = false }
        }
    }) {
        Column(Modifier.imePadding().verticalScroll(rememberScrollState()).padding(20.dp)) {
            BusinessForm(existing, name, { name = it }, city, { city = it }, website, { website = it }, note, { note = it }, message)
        }
    }
    if (offerBrand) {
        AlertDialog(
            onDismissRequest = { offerBrand = false; onDismiss() },
            title = { Text(L("Huisstijl opnieuw ophalen?")) },
            text = { Text(L("Je website is gewijzigd. Pasr kan het logo en de kleuren opnieuw ophalen en op je kaarten zetten.")) },
            confirmButton = {
                TextButton(onClick = {
                    offerBrand = false; busy = true
                    scope.launch {
                        val business = BusinessStore.businesses.firstOrNull { it.id == existing.id } ?: existing
                        val brand = BusinessApi.brand(business.id, website.trim())
                        if (brand != null) {
                            for (card in business.cards) {
                                val updated = card.copy(
                                    logo = brand.logo ?: card.logo, color = brand.color ?: card.color, textColor = brand.textColor,
                                )
                                runCatching { BusinessApi.saveCard(updated, business, brand.logo != null) }
                            }
                            BusinessStore.load()
                        }
                        busy = false
                        onDismiss()
                    }
                }) { Text(L("Ophalen en op mijn kaarten zetten"), color = Pz.accent, fontWeight = FontWeight.Bold) }
            },
            dismissButton = { TextButton(onClick = { offerBrand = false; onDismiss() }) { Text(L("Niet nu"), color = Pz.accent) } },
            containerColor = Pz.card,
        )
    }
}

/** Aanmelding nog niet goedgekeurd (of geblokkeerd). */
@Composable
fun PendingScreen(business: Business) {
    var editing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val open = rememberOpenUrl()
    val blocked = business.status == BusinessStatus.blocked
    ScreenScaffold("", actions = {
        IconButton(onClick = { scope.launch { Account.signOut() } }) {
            Icon(Icons.AutoMirrored.Filled.Logout, L("Uitloggen"), tint = Pz.coral)
        }
    }) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Column(
                Modifier.widthIn(max = 520.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                Icon(if (blocked) Icons.Filled.PanTool else Icons.Filled.HourglassTop, null,
                    tint = if (blocked) Pz.coral else Pz.amber, modifier = Modifier.padding(top = 30.dp).size(56.dp))
                Text(if (blocked) L("Zaak geblokkeerd") else L("Wacht op goedkeuring"), fontSize = 28.sp, fontWeight = FontWeight.Bold, color = Pz.text)
                Text(business.name + if (business.city.isEmpty()) "" else " · " + business.city, fontWeight = FontWeight.SemiBold, color = Pz.muted, fontSize = 17.sp)
                Text(
                    if (blocked) L("Deze zaak kan Pasr Zakelijk niet meer gebruiken. Neem contact op via pasr.nl/support als je denkt dat dit niet klopt.")
                    else L("Pasr kijkt je aanmelding zo snel mogelijk na. Je krijgt een mail als je zaak is goedgekeurd. Daarna kun je stempelkaarten publiceren en scannen."),
                    color = Pz.muted, textAlign = TextAlign.Center,
                )
                BigButton(L("Opnieuw kijken"), { scope.launch { BusinessStore.load() } }, icon = Icons.Filled.Refresh, busy = BusinessStore.loading)
                if (business.isOwner && business.status == BusinessStatus.pending) LinkButton(L("Gegevens wijzigen"), { editing = true })
                TextButton(onClick = { open("https://pasr.nl/support/") }) {
                    Icon(Icons.AutoMirrored.Outlined.HelpOutline, null, tint = Pz.accent, modifier = Modifier.size(18.dp))
                    Text("  " + L("Support"), color = Pz.accent)
                }
            }
        }
    }
    if (editing) EditBusinessSheet(business) { editing = false }
}

/** Uitnodiging accepteren (medewerker, of eigenaar van een zaak die het beheer klaarzette). */
@Composable
fun InviteAcceptSheet(code: String, onDismiss: () -> Unit) {
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var info by remember { mutableStateOf<BusinessApi.InviteInfo?>(null) }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    LaunchedEffect(code) { info = BusinessApi.inviteInfo(code) }
    val owner = info?.role == BusinessRole.owner

    FullSheet(onDismiss, "") {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Icon(Icons.Filled.PersonAddAlt1, null, tint = Pz.mint, modifier = Modifier.padding(top = 20.dp).size(52.dp))
            Text(if (owner) L("Je zaak staat klaar") else L("Uitnodiging als medewerker"), fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Pz.text, textAlign = TextAlign.Center)
            info?.let { Text(it.business + if (it.city.isEmpty()) "" else " · " + it.city, fontWeight = FontWeight.SemiBold, color = Pz.iris, fontSize = 17.sp) }
            Text(
                if (owner) L("Pasr heeft deze zaak voor je klaargezet. Na het accepteren ben je eigenaar en kun je kaarten maken en scannen.")
                else L("Je bent uitgenodigd om stempels te zetten voor een zaak. Na het accepteren zie je die zaak in de scanner."),
                color = Pz.muted, textAlign = TextAlign.Center,
            )
            Account.session?.email?.let { Text(L("Je accepteert met %@.", it), color = Pz.muted, fontSize = 13.sp) }
            message?.let { Text(it, color = Pz.coral, textAlign = TextAlign.Center) }
            BigButton(L("Accepteren"), {
                busy = true; message = null
                scope.launch {
                    try {
                        val id = BusinessApi.accept(code)
                        haptics.success()
                        BusinessStore.load()
                        if (id != null && BusinessStore.businesses.any { it.id == id }) BusinessStore.select(id)
                        onDismiss()
                    } catch (e: Exception) { message = e.message; haptics.error() } finally { busy = false }
                }
            }, color = Pz.mint, foreground = androidx.compose.ui.graphics.Color.Black, busy = busy)
        }
    }
}
