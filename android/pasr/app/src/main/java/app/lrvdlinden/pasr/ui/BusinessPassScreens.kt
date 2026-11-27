package app.lrvdlinden.pasr.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasr.R
import app.lrvdlinden.pasr.data.Account
import app.lrvdlinden.pasr.data.BusinessPasses
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.CardKind
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.MemberDiscount
import app.lrvdlinden.pasr.data.PasrError
import app.lrvdlinden.pasr.data.Prefs
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

/*
 * Gratis tickets en klantenkaarten met barcode van zaken (zelfde als EventTicketViews.swift en MemberCardViews.swift):
 * aanmelden (pasr.nl/add/e/<event>), ticket koppelen (pasr.nl/add/t/<ticket>?c=<code>), klantenkaart toevoegen
 * (pasr.nl/add/m/<kaart>) en wat er bij zo'n ticket of kaart in het detail staat.
 */

private val NL = Locale("nl", "NL")

/** Kiest het scherm bij een /add/-link. */
@Composable
fun AddLinkScreen(link: AddLink) {
    when {
        link.kind == 'e' -> EventSignupScreen(link.id)
        link.kind == 'm' -> MemberCardJoinScreen(link.id)
        link.isTicketClaim -> TicketClaimScreen(link.id, link.code ?: "")
        else -> AddToPasrScreen(link)
    }
}

/** Logo van de server (https of base64) als base64, zoals Card.logo het bewaart. */
@Composable
private fun rememberLogoBase64(source: String?): String? {
    var b64 by remember(source) { mutableStateOf<String?>(null) }
    LaunchedEffect(source) { b64 = app.lrvdlinden.pasr.data.Business.logoBase64(source) }
    return b64
}

@Composable
private fun rememberLogo(source: String?): android.graphics.Bitmap? {
    val b64 = rememberLogoBase64(source)
    return remember(b64) {
        b64?.let {
            runCatching {
                val bytes = android.util.Base64.decode(it, android.util.Base64.DEFAULT)
                android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }.getOrNull()
        }
    }
}

/** Kop van een event in de kleur van het event. */
@Composable
fun EventHeaderCard(event: BusinessPasses.EventInfo) {
    val ink = onCard(event.color)
    val logo = rememberLogo(event.logo)
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(hexColor(event.color)).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            logo?.let { Image(it.asImageBitmap(), null, contentScale = ContentScale.Fit, modifier = Modifier.height(28.dp).widthIn(max = 90.dp)) }
            Text(event.business ?: "", color = ink, fontWeight = FontWeight.Bold, fontSize = 13.sp, maxLines = 1, modifier = Modifier.weight(1f))
            Text(stringResource(R.string.biz_free_ticket), color = ink.copy(alpha = 0.8f), fontWeight = FontWeight.Black, fontSize = 10.sp)
        }
        Text(event.name, color = ink, fontWeight = FontWeight.Black, fontSize = 26.sp, lineHeight = 30.sp, maxLines = 2)
        event.whenText?.let { Text(it, color = ink, fontWeight = FontWeight.SemiBold) }
        event.doors?.let {
            Text(stringResource(R.string.biz_doors, DateTimeFormatter.ofPattern("HH:mm", NL).format(Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()))),
                color = ink)
        }
        event.address?.let { Text(it, color = ink, maxLines = 2) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventSignupScreen(eventId: String) {
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    val session by Account.session.collectAsState()
    val cards by CardStore.cards.collectAsState()
    var event by remember { mutableStateOf<BusinessPasses.EventInfo?>(null) }
    var missing by remember { mutableStateOf<String?>(null) }
    var first by remember { mutableStateOf(session?.firstName ?: "") }
    var last by remember { mutableStateOf(Prefs.string("event.lastName") ?: "") }
    var email by remember { mutableStateOf(session?.email ?: "") }
    var birth by remember { mutableStateOf(Prefs.string("event.birthDate")?.let { runCatching { LocalDate.parse(it) }.getOrNull() }) }
    var type by remember { mutableStateOf<String?>(null) }
    var count by remember { mutableIntStateOf(1) }
    var picking by remember { mutableStateOf(false) }
    var typeMenu by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var done by remember { mutableStateOf<BusinessPasses.Registration?>(null) }
    val generic = stringResource(R.string.add_error_generic)
    val mine = cards.filter { it.deletedAt == null && it.details.isEventTicket && it.details.eventId == eventId.lowercase() }

    LaunchedEffect(eventId) {
        try {
            val e = BusinessPasses.event(eventId)
            event = e
            type = (e.types.firstOrNull { (it.available ?: 1) > 0 } ?: e.types.firstOrNull())?.id
        } catch (e: CancellationException) { throw e } catch (e: Exception) { missing = e.message ?: generic }
    }

    fun openInPasr() {
        val card = BusinessPasses.ticketCard(eventId, done?.ticketIds?.firstOrNull())
        if (card != null) nav.replace(Screen.Detail(card.id)) else nav.home()
    }

    SimpleScaffold(stringResource(if (done != null) R.string.biz_done_title else R.string.biz_event_title)) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Gap(4.dp)
            val e = event
            when {
                missing != null -> {
                    Text(missing ?: "", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                    Text(stringResource(R.string.biz_event_missing), color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                }
                e == null -> Box(Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                done != null -> {
                    val waitlist = done?.waitlist == true
                    Icon(if (waitlist) Icons.Filled.HourglassTop else Icons.Filled.CheckCircle, null, Modifier.size(64.dp),
                        tint = if (waitlist) Color(0xFFFF9F0A) else Color(0xFF2ED3A6))
                    Text(stringResource(if (waitlist) R.string.biz_waitlist_title else R.string.biz_done_title),
                        style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    Text(when {
                        waitlist -> stringResource(R.string.biz_waitlist_done)
                        count == 1 -> stringResource(R.string.biz_done_one)
                        else -> stringResource(R.string.biz_done_many, count)
                    }, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                    EventHeaderCard(e)
                    BrandButton(stringResource(R.string.add_view_in_pasr)) { openInPasr() }
                }
                else -> {
                    EventHeaderCard(e)
                    e.description?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.fillMaxWidth()) }
                    if (mine.isNotEmpty()) {
                        Text(stringResource(R.string.biz_already_tickets, mine.size), color = Color(0xFF2ED3A6), fontWeight = FontWeight.SemiBold)
                        TextButton({ nav.replace(Screen.Detail(mine.alphabeticalFirst().id)) }) { Text(stringResource(R.string.add_view_in_pasr)) }
                    }
                    when {
                        e.isCancelled -> Notice(stringResource(R.string.biz_event_cancelled))
                        !e.signupOpen && !(e.isFull && e.waitlist) -> Notice(stringResource(R.string.biz_signup_closed))
                        session == null -> Notice(stringResource(R.string.biz_needs_account_event))
                        else -> {
                            Group {
                                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    OutlinedTextField(first, { first = it }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.biz_first_name)) }, singleLine = true)
                                    OutlinedTextField(last, { last = it }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.biz_last_name)) }, singleLine = true)
                                    OutlinedTextField(email, { email = it.trim() }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.biz_email)) },
                                        singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email))
                                    OutlinedButton({ picking = true }, Modifier.fillMaxWidth()) {
                                        Text(birth?.let { stringResource(R.string.biz_birth_date) + ": " + DateTimeFormatter.ofPattern("d MMMM yyyy", NL).format(it) }
                                            ?: stringResource(R.string.biz_pick_birth))
                                    }
                                    if (e.types.size > 1) Box {
                                        val current = e.types.firstOrNull { it.id == type }
                                        OutlinedButton({ typeMenu = true }, Modifier.fillMaxWidth()) {
                                            Text(stringResource(R.string.biz_ticket_type) + ": " + (current?.name ?: "—"))
                                        }
                                        DropdownMenu(typeMenu, { typeMenu = false }) {
                                            e.types.forEach { t ->
                                                val title = when {
                                                    t.available == null -> t.name
                                                    t.available <= 0 -> stringResource(R.string.biz_type_full, t.name)
                                                    else -> stringResource(R.string.biz_type_left, t.name, t.available)
                                                }
                                                DropdownMenuItem({ Text(title) }, { type = t.id; typeMenu = false })
                                            }
                                        }
                                    }
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text(stringResource(R.string.biz_count), Modifier.weight(1f))
                                        TextButton({ if (count > 1) count-- }, enabled = count > 1) { Text("−", fontSize = 20.sp) }
                                        Text("$count ×", fontWeight = FontWeight.Bold)
                                        TextButton({ if (count < e.maxPerPerson) count++ }, enabled = count < e.maxPerPerson) { Text("+", fontSize = 20.sp) }
                                    }
                                }
                            }
                            if (e.isFull && e.waitlist) Text(stringResource(R.string.biz_waitlist_hint), color = Color(0xFFFF9F0A), textAlign = TextAlign.Center)
                            error?.let { Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center) }
                            val valid = first.isNotBlank() && last.isNotBlank() && Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]{2,}$").matches(email.trim()) &&
                                birth?.isBefore(LocalDate.now()) == true && count in 1..e.maxPerPerson
                            BrandButton(if (busy) stringResource(R.string.add_busy)
                                else stringResource(if (e.isFull && e.waitlist) R.string.biz_waitlist_button else R.string.biz_signup_button),
                                enabled = valid && !busy) {
                                busy = true; error = null
                                scope.launch {
                                    try {
                                        val r = BusinessPasses.register(e.id, first, last, email, birth!!, type, count)
                                        Prefs.setString("event.lastName", last.trim())
                                        Prefs.setString("event.birthDate", birth.toString())
                                        done = r
                                    } catch (x: CancellationException) { throw x } catch (x: PasrError) { error = x.message } catch (x: Exception) { error = generic }
                                    busy = false
                                }
                            }
                            Text(stringResource(R.string.biz_privacy, e.business ?: stringResource(R.string.biz_organizer)),
                                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                        }
                    }
                }
            }
            Gap(24.dp)
        }
    }

    if (picking) {
        val initial = (birth ?: LocalDate.now().minusYears(30)).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        val state = rememberDatePickerState(initialSelectedDateMillis = initial)
        DatePickerDialog(
            onDismissRequest = { picking = false },
            confirmButton = {
                TextButton({
                    state.selectedDateMillis?.let { birth = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate() }
                    picking = false
                }) { Text(stringResource(R.string.biz_pick)) }
            },
            dismissButton = { TextButton({ picking = false }) { Text(stringResource(R.string.biz_cancel)) } },
        ) { DatePicker(state) }
    }
}

private fun List<Card>.alphabeticalFirst(): Card = sortedBy { it.storeName.lowercase() }.first()

@Composable
private fun Notice(text: String) {
    Text(text, fontWeight = FontWeight.SemiBold, modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
        .background(MaterialTheme.colorScheme.surfaceContainer).padding(14.dp))
}

/** /add/t/<ticket>?c=<code>: een ticket (aangemeld zonder account) aan je account koppelen. */
@Composable
fun TicketClaimScreen(ticketId: String, code: String) {
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    val session by Account.session.collectAsState()
    val cards by CardStore.cards.collectAsState()
    var added by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val generic = stringResource(R.string.add_error_generic)
    val existing = cards.firstOrNull { it.deletedAt == null && it.details.ticketId == (added ?: ticketId.lowercase()) }

    SimpleScaffold(stringResource(R.string.add_kind_ticket)) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Gap(8.dp)
            if (existing != null) {
                Icon(Icons.Filled.CheckCircle, null, Modifier.size(56.dp), tint = Color(0xFF2ED3A6))
                Text(stringResource(if (added == null) R.string.biz_claim_already else R.string.biz_done_title),
                    style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                CardFace(existing, Modifier.fillMaxWidth())
                BrandButton(stringResource(R.string.add_view_in_pasr)) { nav.replace(Screen.Detail(existing.id)) }
            } else {
                Text(stringResource(R.string.biz_claim_title), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text(stringResource(R.string.biz_claim_text), color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                error?.let { Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center) }
                if (session != null) {
                    BrandButton(if (busy) stringResource(R.string.add_busy) else stringResource(R.string.add_button), enabled = !busy) {
                        busy = true; error = null
                        scope.launch {
                            try { added = BusinessPasses.claim(ticketId, code) }
                            catch (x: CancellationException) { throw x } catch (x: PasrError) { error = x.message } catch (x: Exception) { error = generic }
                            busy = false
                        }
                    }
                } else {
                    Text(stringResource(R.string.biz_needs_account), color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
                }
            }
            Gap(24.dp)
        }
    }
}

/** pasr.nl/add/m/<kaart>: de klantenkaart van een zaak toevoegen, met "Mijn naam tonen aan <zaak>". */
@Composable
fun MemberCardJoinScreen(cardId: String) {
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    val session by Account.session.collectAsState()
    val cards by CardStore.cards.collectAsState()
    var info by remember { mutableStateOf<BusinessPasses.MemberCardInfo?>(null) }
    var missing by remember { mutableStateOf<String?>(null) }
    var shareName by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var added by remember { mutableStateOf<String?>(null) }
    val generic = stringResource(R.string.add_error_generic)
    val existing = cards.firstOrNull { it.deletedAt == null && it.details.memberCardId == cardId.lowercase() }
    val previewLogo = rememberLogoBase64(info?.logo)

    LaunchedEffect(cardId) {
        try { info = BusinessPasses.memberCard(cardId) }
        catch (e: CancellationException) { throw e } catch (e: Exception) { missing = e.message ?: generic }
    }

    SimpleScaffold(stringResource(if (added != null) R.string.add_done_title else R.string.add_title)) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Gap(8.dp)
            val i = info
            when {
                missing != null -> {
                    Text(missing ?: "", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                    Text(stringResource(R.string.biz_member_missing), color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                }
                i == null -> Box(Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                else -> {
                    if (added != null) {
                        Icon(Icons.Filled.CheckCircle, null, Modifier.size(64.dp), tint = Color(0xFF2ED3A6))
                    } else {
                        Text(stringResource(R.string.biz_member_kind), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    val preview = existing ?: Card(id = "preview-" + cardId.lowercase(), storeName = i.name, kindRaw = CardKind.LOYALTY.raw,
                        colorHex = i.color, number = "", logo = previewLogo)
                    CardFace(preview, Modifier.fillMaxWidth())
                    i.summary?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center) }
                    discountLine(i.discountNow, i.nextDiscount)?.let { Text(it, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center) }
                    error?.let { Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center) }
                    val card = existing
                    when {
                        card != null -> {
                            Text(stringResource(if (added == null) R.string.biz_member_already else R.string.biz_member_done),
                                color = if (added == null) Color(0xFF2ED3A6) else MaterialTheme.colorScheme.onSurfaceVariant,
                                fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                            BrandButton(stringResource(R.string.add_view_in_pasr)) { nav.replace(Screen.Detail(card.id)) }
                        }
                        session != null -> {
                            Group {
                                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Column(Modifier.weight(1f)) {
                                        Text(stringResource(R.string.biz_member_share, i.business ?: i.name))
                                        Text(stringResource(R.string.biz_member_share_off), style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    Switch(shareName, { shareName = it })
                                }
                            }
                            BrandButton(if (busy) stringResource(R.string.add_busy) else stringResource(R.string.biz_member_add), enabled = !busy) {
                                busy = true; error = null
                                scope.launch {
                                    try { added = BusinessPasses.join(cardId, shareName).id }
                                    catch (x: CancellationException) { throw x } catch (x: PasrError) { error = x.message } catch (x: Exception) { error = generic }
                                    busy = false
                                }
                            }
                        }
                        else -> Text(stringResource(R.string.biz_member_needs_account), color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
                    }
                }
            }
            Gap(24.dp)
        }
    }
}

/** "Nu 15% korting t/m 15 dec" of "Geen korting vandaag · volgende: …"; null als er niets te melden is. */
@Composable
fun discountLine(now: MemberDiscount?, next: MemberDiscount?): String? {
    val day = DateTimeFormatter.ofPattern("d MMM", NL)
    if (now != null) {
        var s = stringResource(R.string.biz_discount_now, now.percentText ?: "")
        now.label?.let { s += " · $it" }
        now.until?.let { s += " " + stringResource(R.string.biz_discount_until, day.format(Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()))) }
        return s
    }
    next ?: return null
    val parts = listOfNotNull(
        next.startsAt?.let { DateTimeFormatter.ofPattern("EEE d MMM HH:mm", NL).format(Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault())) },
        next.percentText, next.label,
    )
    return stringResource(R.string.biz_discount_next, parts.joinToString(" · "))
}

/** In het detail van een ticket van een zaak: wat de status betekent. */
@Composable
fun EventTicketSection(card: Card) {
    val d = card.details
    val text = when {
        d.ticketCancelled -> stringResource(R.string.biz_status_cancelled, d.businessName ?: stringResource(R.string.biz_organizer))
        d.ticketWaitlist -> stringResource(R.string.biz_status_waitlist)
        d.ticketUsed -> stringResource(R.string.biz_status_used)
        else -> return
    }
    Gap(14.dp)
    Text(text, fontWeight = FontWeight.SemiBold,
        color = when { d.ticketCancelled -> MaterialTheme.colorScheme.error; d.ticketWaitlist -> Color(0xFFFF9F0A); else -> MaterialTheme.colorScheme.onSurfaceVariant },
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.surfaceContainer).padding(14.dp))
}

/** In het detail van een klantenkaart van een zaak: korting, spaarstand, meldingen en verwijderen. */
@Composable
fun MemberCardSection(card: Card, onDelete: () -> Unit) {
    val scope = rememberCoroutineScope()
    val snack = LocalSnack.current
    val d = card.details
    val generic = stringResource(R.string.add_error_generic)
    SectionHeader(stringResource(R.string.biz_member_section))
    Group {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            discountLine(d.discountNow, d.nextDiscount)?.let { line ->
                Text(line, fontWeight = if (d.discountNow != null) FontWeight.Bold else FontWeight.Normal,
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
                        .background(hexColor(card.colorHex).copy(alpha = if (d.discountNow != null) 0.18f else 0f)).padding(8.dp))
            }
            val target = d.savingTarget
            if (target != null && target > 0) {
                val count = (d.savingCount ?: 0).coerceIn(0, target)
                Row {
                    Text(stringResource(R.string.biz_saving), fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    Text("$count/$target", fontWeight = FontWeight.Bold)
                }
                LinearProgressIndicator(progress = { count.toFloat() / target }, modifier = Modifier.fillMaxWidth(), color = hexColor(card.colorHex))
                val reward = d.savingReward ?: stringResource(R.string.biz_reward)
                Text(if (d.savingCanRedeem == true) stringResource(R.string.biz_saving_ready, reward)
                     else stringResource(R.string.biz_saving_left, (target - count).coerceAtLeast(0), reward),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (d.savingCanRedeem == true) Color(0xFF2ED3A6) else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        RowItem(Icons.Outlined.NotificationsActive, stringResource(R.string.biz_notify), trailing = {
            Switch(d.memberNotify == true, { on ->
                scope.launch {
                    try { BusinessPasses.setNotify(card, on) }
                    catch (x: CancellationException) { throw x } catch (x: PasrError) { snack.showSnackbar(x.message ?: generic) }
                }
            })
        })
        RowItem(Icons.Outlined.Delete, stringResource(R.string.biz_delete_card), tint = MaterialTheme.colorScheme.error, onClick = onDelete)
    }
}
