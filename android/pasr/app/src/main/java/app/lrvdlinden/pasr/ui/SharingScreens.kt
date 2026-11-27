package app.lrvdlinden.pasr.ui

import android.content.Context
import android.content.Intent
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasr.Incoming
import app.lrvdlinden.pasr.data.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.time.MonthDay

private fun JSONObject.id() = getString("id")
private fun params(vararg fields: Pair<String, Any?>) =
    JSONObject().apply { fields.forEach { (key, value) -> put(key, value ?: JSONObject.NULL) } }

private fun shareText(context: Context, text: String) {
    val intent = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    Incoming.leavingOnPurpose = true
    context.startActivity(Intent.createChooser(intent, "Kaart delen"))
}

@Composable
fun ShareCardScreen(id: String) {
    val nav = LocalNav.current
    val context = LocalContext.current
    val cards by CardStore.cards.collectAsState()
    val card = cards.firstOrNull { it.id == id && it.deletedAt == null } ?: return
    val operation = rememberCoroutineScope()
    var working by remember { mutableStateOf(false) }
    var issue by remember { mutableStateOf("") }
    var prompt by remember { mutableStateOf(false) }
    SimpleScaffold("Kaart delen") {
        Group {
            RowItem(null, "Deel een kopie", if (card.isBusinessStamps) "Deel de link van de zaak" else "Via WhatsApp, mail of andere apps") {
                shareText(context, Share.link(card))
            }
            if (!card.isBusinessStamps && !card.isLocked) {
                RowItem(null, "Tijdelijk delen", "Maak een link met een einddatum") { prompt = true }
                if (Account.isSignedIn) {
                    RowItem(null, "Gedeelde Pasr", "Verplaats de kaart naar een gedeelde of privéverzameling") {
                        nav.push(Screen.Groups(id))
                    }
                }
            }
        }
        if (issue.isNotEmpty()) Text(issue)
    }
    if (prompt) DaysDialog("Hoe lang delen?", working, { prompt = false }) { days ->
        working = true
        operation.launch {
            try {
                val link = TempSharing.create(card, nowMs() + days * 86_400_000L)
                prompt = false
                shareText(context, "Bekijk mijn kaart van ${card.storeName} in Pasr:\n${link.url}")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                issue = e.message ?: "Delen is mislukt."
                prompt = false
            } finally {
                working = false
            }
        }
    }
}

@Composable
private fun DaysDialog(title: String, busy: Boolean, close: () -> Unit, submit: (Int) -> Unit) {
    var input by remember { mutableStateOf("7") }
    val days = input.toIntOrNull()?.takeIf { it in 1..90 }
    AlertDialog(onDismissRequest = { if (!busy) close() }, title = { Text(title) },
        text = { OutlinedTextField(input, { input = it.take(2) }, label = { Text("Aantal dagen (1–90)") }, singleLine = true) },
        confirmButton = { TextButton({ days?.let(submit) }, enabled = days != null && !busy) { Text("Bevestigen") } },
        dismissButton = { TextButton(close, enabled = !busy) { Text("Annuleren") } })
}

@Composable
fun TemporarySharesScreen() {
    val context = LocalContext.current
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    var links by remember { mutableStateOf(TempSharing.links()) }
    var edit by remember { mutableStateOf<TempSharing.Link?>(null) }
    var revoke by remember { mutableStateOf<TempSharing.Link?>(null) }
    var error by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    fun update(action: suspend () -> Unit) {
        if (busy) return
        busy = true
        error = ""
        scope.launch {
            try { action(); links = TempSharing.links() }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "Bijwerken is mislukt." }
            finally { busy = false; edit = null; revoke = null }
        }
    }

    SimpleScaffold("Tijdelijk gedeeld") {
        if (links.isEmpty() && TempSharing.received().isEmpty()) Text("Er zijn geen tijdelijk gedeelde kaarten.")
        if (error.isNotEmpty()) Text(error)
        for (link in links) {
            val active = !link.revoked && link.until > nowMs()
            SectionHeader(link.name)
            Group {
                val status = if (link.revoked) "Delen gestopt" else if (active) "Geldig tot" else "Verlopen op"
                RowItem(null, status, dateText(link.until))
                if (active) {
                    RowItem(null, "Link delen") { shareText(context, link.url) }
                    RowItem(null, "Stop delen") { if (!busy) revoke = link }
                }
                if (!link.revoked) RowItem(null, "Verander einddatum") { if (!busy) edit = link }
            }
        }
        val received = TempSharing.received()
        if (received.isNotEmpty()) SectionHeader("Ontvangen")
        for (item in received) {
            RowItem(null, item.name, "Opnieuw openen") { nav.push(Screen.Borrowed(item.token)) }
        }
    }
    edit?.let { link ->
        DaysDialog("Nieuwe einddatum", busy, { edit = null }) { days ->
            update { TempSharing.change(link, nowMs() + days * 86_400_000L) }
        }
    }
    revoke?.let { link ->
        AlertDialog(onDismissRequest = { if (!busy) revoke = null }, title = { Text("Delen stoppen?") },
            text = { Text("De ontvanger verliest toegang tot de kaart.") },
            confirmButton = { TextButton({ update { TempSharing.revoke(link) } }, enabled = !busy) { Text("Stop delen") } },
            dismissButton = { TextButton({ revoke = null }, enabled = !busy) { Text("Annuleren") } })
    }
}

@Composable
fun BorrowedCardScreen(token: String) {
    val context = LocalContext.current
    val activity = context as? app.lrvdlinden.pasr.MainActivity
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    val state by lifecycle.currentStateFlow.collectAsState()
    val locked by Incoming.locked.collectAsState()
    var result by remember(token) { mutableStateOf<Pair<Card, Long>?>(null) }
    var message by remember(token) { mutableStateOf("Kaart ophalen…") }
    DisposableEffect(activity) {
        activity?.setBorrowedCardVisible(true)
        onDispose { activity?.setBorrowedCardVisible(false) }
    }
    LaunchedEffect(token, state, locked) {
        result = null
        if (!state.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED) || locked) return@LaunchedEffect
        while (true) {
            try {
                val item = TempSharing.open(token)
                result = item
                TempSharing.rememberReceived(token, item.first.storeName)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                result = null
                message = e.message ?: "Kaart ophalen is mislukt."
            }
            val until = result?.second ?: Long.MAX_VALUE
            delay((until - nowMs()).coerceIn(200L, 30_000L))
            if (nowMs() >= until) result = null
        }
    }
    SimpleScaffold("Tijdelijk gedeelde kaart") {
        val item = result
        if (item == null) Text(message)
        else {
            val (card, until) = item
            CardFace(card)
            Text("Geldig tot ${dateText(until)}")
            if (card.showsCodeAsText) Text(card.number)
            else BarcodeImage(card.number, card.format)
            card.pin?.let { Text("Pincode: $it") }
        }
    }
}

private data class GroupInput(val title: String, val label: String, val value: String = "", val run: suspend (String) -> Unit)

@Composable
fun SharedGroupsScreen(cardId: String?) {
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    val session by Account.session.collectAsState()
    var info by remember(session?.userID) { mutableStateOf<JSONObject?>(null) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var input by remember { mutableStateOf<GroupInput?>(null) }
    val card = cardId?.let(CardStore::get)
    fun perform(work: suspend () -> Unit) {
        if (busy) return
        busy = true
        message = ""
        scope.launch {
            try {
                work()
                info = SharedGroups.overview()
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { message = e.message ?: "Bijwerken is mislukt." }
            finally { busy = false; input = null }
        }
    }
    LaunchedEffect(session?.userID) { if (session != null) perform { } }
    SimpleScaffold("Gedeelde Pasr") {
        if (session == null) {
            Text("Log in om kaarten te delen met je gezin of huisgenoten.")
            BrandButton("Naar mijn Pasr-account") { nav.push(Screen.AccountScreen) }
            return@SimpleScaffold
        }
        if (message.isNotEmpty()) Text(message)
        if (busy) Text("Even geduld…")
        if (info == null && !busy) TextButton({ perform {} }) { Text("Opnieuw proberen") }
        val overview = info ?: return@SimpleScaffold
        val groups = overview.optJSONArray("groups")?.objects().orEmpty()
        if (card != null && card.groupId != null) {
            RowItem(null, "Verplaats naar privé") { perform { SharedGroups.move(card, null); nav.home() } }
        }
        if (cardId == null && groups.size < (overview.optJSONObject("limits")?.optInt("groups") ?: 2)) {
            Button(enabled = !busy, onClick = {
                input = GroupInput("Nieuwe gedeelde Pasr", "Naam") { name ->
                    SharedGroups.action("pasr_group_create", params("p_name" to name))
                }
            }) { Text("Nieuwe gedeelde Pasr") }
        }
        for (invite in overview.optJSONArray("invites")?.objects().orEmpty()) {
            SectionHeader(invite.optString("group_name"))
            Text("Uitnodiging van ${invite.optString("from")}")
            for ((label, accept) in listOf("Accepteren" to true, "Weigeren" to false)) {
                TextButton(enabled = !busy, onClick = { perform {
                    SharedGroups.action("pasr_invite_respond", params("p_invite" to invite.id(), "p_accept" to accept))
                    Sync.sync()
                } }) { Text(label) }
            }
        }
        for (group in groups) {
            val groupId = group.id().lowercase()
            val name = group.optString("name")
            SectionHeader(name)
            Group {
                if (card != null) {
                    if (card.groupId != groupId) RowItem(null, "Verplaats naar $name") {
                        perform { SharedGroups.move(card, groupId); nav.home() }
                    }
                } else {
                    RowItem(null, "Hernoem groep") {
                        input = GroupInput("Hernoem groep", "Naam", name) { value ->
                            SharedGroups.action("pasr_group_rename", params("p_group" to groupId, "p_name" to value))
                        }
                    }
                    RowItem(null, "Nodig iemand uit") {
                        input = GroupInput("Nodig iemand uit", "E-mailadres") { email ->
                            if (!SharedGroups.invite(groupId, email)) message = "Uitnodiging aangemaakt. De e-mail kon niet worden verstuurd."
                        }
                    }
                    for (member in group.optJSONArray("members")?.objects().orEmpty()) {
                        val me = member.optBoolean("me")
                        val person = member.optString("first_name").takeUnless { it.isBlank() || it == "null" }
                            ?: member.optString("email")
                        RowItem(null, person, if (me) "Tik om de groep te verlaten" else "Tik om het lid te verwijderen") {
                            input = GroupInput(if (me) "Groep verlaten" else "Lid verwijderen", "Typ JA ter bevestiging") { answer ->
                                if (!answer.equals("JA", true)) throw PasrError("Bevestig met JA.")
                                SharedGroups.action("pasr_group_remove", params("p_group" to groupId, "p_user" to if (me) null else member.getString("user_id")))
                                Sync.sync()
                            }
                        }
                    }
                    for (invite in group.optJSONArray("invites")?.objects().orEmpty()) {
                        RowItem(null, invite.optString("email"), "Trek uitnodiging in") {
                            perform { SharedGroups.action("pasr_group_cancel_invite", params("p_invite" to invite.id())) }
                        }
                    }
                }
            }
        }
    }
    input?.let { prompt ->
        var value by remember(prompt) { mutableStateOf(prompt.value) }
        AlertDialog(onDismissRequest = { if (!busy) input = null }, title = { Text(prompt.title) },
            text = { OutlinedTextField(value, { value = it }, label = { Text(prompt.label) }, singleLine = true) },
            confirmButton = { TextButton({ perform { prompt.run(value.trim()) } }, enabled = !busy && value.isNotBlank()) { Text("Bevestigen") } },
            dismissButton = { TextButton({ input = null }, enabled = !busy) { Text("Annuleren") } })
    }
}

@Composable
fun BirthdayScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var day by remember { mutableStateOf(Birthday.value()?.dayOfMonth?.toString().orEmpty()) }
    var month by remember { mutableStateOf(Birthday.value()?.monthValue?.toString().orEmpty()) }
    var message by remember { mutableStateOf("") }
    val valid = runCatching { MonthDay.of(month.toInt(), day.toInt()) }.getOrNull()
    fun save(value: MonthDay?) {
        Birthday.set(value)
        scope.launch {
            try {
                Birthday.sync()
                app.lrvdlinden.pasr.notify.Reminders.check(context)
                message = if (value != null) "Verjaardag opgeslagen" else "Verjaardag verwijderd"
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                message = "Op dit toestel opgeslagen. Synchronisatie volgt zodra Pasr verbinding heeft."
            }
        }
    }
    SimpleScaffold("Verjaardag") {
        Text("Vul je dag en maand in. Pasr geeft je een seintje over verjaardagsvoordeel bij winkels waarvan je een kaart hebt.")
        Gap(12.dp)
        OutlinedTextField(day, { day = it.filter(Char::isDigit).take(2) }, label = { Text("Dag") }, singleLine = true)
        OutlinedTextField(month, { month = it.filter(Char::isDigit).take(2) }, label = { Text("Maand") }, singleLine = true)
        Gap(12.dp)
        BrandButton("Opslaan", enabled = valid != null) { valid?.let { save(it) } }
        TextButton({ day = ""; month = ""; save(null) }) { Text("Wis verjaardag") }
        if (message.isNotEmpty()) Text(message)
    }
}

@Composable
fun ReminderPreferencesScreen() {
    val scope = rememberCoroutineScope()
    val session by Account.session.collectAsState()
    var expiry by remember { mutableStateOf(ReminderPreferences.expiry) }
    var balance by remember { mutableStateOf(ReminderPreferences.balance) }
    var interval by remember { mutableStateOf(ReminderPreferences.interval) }
    var channel by remember { mutableStateOf(ReminderPreferences.channel) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    LaunchedEffect(session?.userID) {
        if (session != null) {
            busy = true
            try { ReminderPreferences.refresh(); channel = ReminderPreferences.channel }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { message = "E-mailinstellingen ophalen is mislukt." }
            finally { busy = false }
        }
    }
    fun update(mail: String = channel) {
        busy = true
        scope.launch {
            try {
                if (channel != "push" || mail != "push") ReminderPreferences.save(mail)
                ReminderPreferences.channel = mail
                channel = mail
                message = "Opgeslagen"
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { message = "E-mailinstellingen opslaan is mislukt." }
            finally { busy = false }
        }
    }
    SimpleScaffold("Herinneringen") {
        RowItem(null, "Vervaldatums en verlengingen", if (expiry) "Aan" else "Uit") {
            if (!busy) { expiry = !expiry; ReminderPreferences.expiry = expiry; update() }
        }
        RowItem(null, "Tegoed-herinnering", if (balance) "Aan" else "Uit") {
            if (!busy) { balance = !balance; ReminderPreferences.balance = balance; update() }
        }
        if (balance) for ((key, label) in listOf("week" to "Elke week", "month" to "Elke maand", "quarter" to "Elk kwartaal")) {
            RowItem(null, label, "Geselecteerd".takeIf { interval == key }) {
                if (!busy) { interval = key; ReminderPreferences.interval = key; update() }
            }
        }
        if (session != null) {
            SectionHeader("Herinneren via")
            for ((key, label) in listOf("push" to "Pushmelding", "mail" to "E-mail", "both" to "Beide")) {
                RowItem(null, label, "Geselecteerd".takeIf { channel == key }) { if (!busy) update(key) }
            }
        }
        if (message.isNotEmpty()) Text(message)
    }
}
