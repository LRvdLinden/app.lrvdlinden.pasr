package app.lrvdlinden.pasrzakelijk.ui.cards

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.core.LogoImage
import app.lrvdlinden.pasrzakelijk.data.Account
import app.lrvdlinden.pasrzakelijk.data.Business
import app.lrvdlinden.pasrzakelijk.data.CommunityRouter
import app.lrvdlinden.pasrzakelijk.ui.shareText
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Gezamenlijke actie uit pasr_business_community_list; nieuwe velden tolerant (een oudere server kent ze nog niet). */
private class CommunityCampaign(val json: JSONObject) {
    val id: String = json.optString("id")
    val name: String = json.optString("name")
    val joined: Boolean = json.optBoolean("joined")
    val isLead: Boolean = json.optBoolean("is_lead")
    val participants: Int = json.optInt("participants")
    val role: String = json.optString("role").takeIf { it.isNotBlank() && it != "null" }
        ?: if (isLead) "owner" else if (joined) "participant" else ""
    val openSameCity: Boolean = json.optBoolean("open_same_city", false)
    val minParticipants: Int = json.optInt("min_participants", 0)
    val acceptedCount: Int = if (json.has("accepted_count") && !json.isNull("accepted_count")) json.optInt("accepted_count") else participants
    val state: String = json.optString("state").takeIf { it in setOf("waiting", "active", "ended", "cancelled") } ?: "active"
    val isOrganizer: Boolean get() = role == "owner" || isLead
    val isParticipant: Boolean get() = joined || role == "owner" || role == "participant"
    val running: Boolean get() = state == "waiting" || state == "active"

    fun stateLabel(): String = when (state) {
        "waiting" -> L("Wacht op %lld van %lld zaken", acceptedCount, maxOf(minParticipants, acceptedCount))
        "ended" -> L("Afgelopen")
        "cancelled" -> L("Gestopt")
        else -> L("Actief")
    }
}

private fun stateColor(state: String): Color = when (state) {
    "waiting" -> Color(0xFFFFB547)
    "ended" -> Color(0xFF9A98B3)
    "cancelled" -> Color(0xFFFF6B57)
    else -> Color(0xFF2ED3A6)
}

private fun inviteStatusLabel(status: String): String = when (status) {
    "accepted" -> L("Doet mee")
    "declined" -> L("Geweigerd")
    "revoked" -> L("Ingetrokken")
    else -> L("Uitgenodigd")
}

private fun inviteStatusColor(status: String): Color = when (status) {
    "accepted" -> Color(0xFF2ED3A6)
    "declined" -> Color(0xFFFF6B57)
    "revoked" -> Color(0xFF9A98B3)
    else -> Color(0xFF4FB3FF)
}

@Composable
private fun StatusPill(text: String, color: Color) {
    Text(text, color = color, fontSize = 12.sp, fontWeight = FontWeight.Bold,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(color.copy(alpha = 0.18f))
            .padding(horizontal = 8.dp, vertical = 3.dp))
}

private fun JSONArray?.objects(): List<JSONObject> = (0 until (this?.length() ?: 0)).mapNotNull { this?.optJSONObject(it) }

private fun JSONObject.str(key: String): String = optString(key).takeIf { it != "null" }.orEmpty()

private fun formatDate(value: String, pattern: String = "d MMMM yyyy"): String? = runCatching {
    OffsetDateTime.parse(value).format(DateTimeFormatter.ofPattern(pattern, if (Locale.getDefault().language == "nl") Locale.forLanguageTag("nl-NL") else Locale.ENGLISH))
}.getOrNull()

/**
 * Dezelfde beveiligde community-RPC's als iOS en pasr.nl/zakelijk. Meedoen kan alleen op uitnodiging van de
 * organisator, of zelf als de actie open staat voor zaken in dezelfde plaats.
 * Eigenaar: starten, zaken uitnodigen, uitnodigingen beantwoorden, uitstappen, stoppen (alleen organisator) en uitgeven.
 * Medewerker: alleen de acties van de eigen zaak en uitgeven (bij het scannen verschijnt de beloning ook vanzelf).
 */
@Composable
fun BusinessCommunityDialog(business: Business, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val owner = business.isOwner
    var name by remember { mutableStateOf("") }
    var reward by remember { mutableStateOf("") }
    var required by remember { mutableStateOf("3") }
    var days by remember { mutableStateOf("60") }
    var openSameCity by remember { mutableStateOf(false) }
    var minParticipants by remember { mutableIntStateOf(2) }
    // lidcode per actie, zodat typen bij de ene actie de andere niet vult
    var memberCodes by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var campaigns by remember { mutableStateOf<List<CommunityCampaign>>(emptyList()) }
    var invites by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var failed by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf<Pair<String, CommunityCampaign>?>(null) }   // "cancel"/"leave" + actie
    var confirmDecline by remember { mutableStateOf<JSONObject?>(null) }
    var managing by remember { mutableStateOf<CommunityCampaign?>(null) }
    var loaded by remember { mutableStateOf(false) }

    fun show(text: String, error: Boolean = false) { message = text; failed = error }

    suspend fun reload() {
        try {
            val result = Account.rpc("pasr_business_community_list",
                JSONObject().put("p_business", business.id)) as? JSONArray
            campaigns = result.objects().map { CommunityCampaign(it) }
        } catch (e: Exception) { show(e.message ?: L("Er ging iets mis. Probeer het opnieuw."), true) }
        if (owner) {
            // een oudere server kent deze functie nog niet: dan gewoon geen uitnodigingen
            runCatching {
                Account.rpc("pasr_business_community_my_invites", JSONObject().put("p_business", business.id)) as? JSONArray
            }.getOrNull()?.let { invites = it.objects() }
            CommunityRouter.inviteCount = invites.size
        }
        loaded = true
    }

    fun call(fn: String, args: JSONObject, success: String) {
        busy = true
        scope.launch {
            try {
                Account.rpc(fn, args.put("p_business", business.id))
                show(success)
                reload()
            } catch (e: Exception) { show(e.message ?: L("Er ging iets mis. Probeer het opnieuw."), true) }
            busy = false
        }
    }

    /** Melding of geaccepteerde link: juiste plek openen. */
    fun applyFocus() {
        val focus = CommunityRouter.focus ?: return
        CommunityRouter.focus = null
        focus.notice?.let { show(it, focus.failed) }
        when (focus.kind) {
            "community_invite_answered" -> {
                val row = campaigns.firstOrNull { it.id == focus.campaign }
                if (owner && row != null && row.isOrganizer) managing = row
            }
            "community_removed" -> show(L("Je zaak doet niet meer mee aan deze gezamenlijke actie."))
        }
    }

    LaunchedEffect(business.id) { reload(); applyFocus() }
    val focusStamp = CommunityRouter.focus?.stamp
    LaunchedEffect(focusStamp) {
        if (focusStamp != null && loaded) { reload(); applyFocus() }
    }

    AlertDialog(
        onDismissRequest = onClose,
        title = { Text(L("Samenwerkingen")) },
        text = {
            Column(Modifier.fillMaxWidth().heightIn(max = 650.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (message.isNotBlank()) Text(message, color = if (failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)
                if (owner && invites.isNotEmpty()) {
                    Text(L("Uitnodigingen (%lld)", invites.size), fontWeight = FontWeight.Bold)
                    invites.forEach { invite ->
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(invite.str("title"), fontWeight = FontWeight.SemiBold)
                            if (invite.str("reward").isNotBlank()) Text(L("Beloning: %@", invite.str("reward")))
                            val start = formatDate(invite.str("starts_at"), "d MMM yyyy")
                            val end = formatDate(invite.str("ends_at"), "d MMM yyyy")
                            if (end != null) Text(if (start != null) "$start – $end" else L("Loopt tot %@", end),
                                style = MaterialTheme.typography.bodySmall)
                            if (invite.str("initiator_name").isNotBlank())
                                Text(L("Organisator: %@", invite.str("initiator_name")), style = MaterialTheme.typography.bodySmall)
                            val names = invite.optJSONArray("participant_names")
                            if (names != null && names.length() > 0) Text(
                                L("Doen mee: %@", (0 until names.length()).joinToString(", ") { names.optString(it) }),
                                style = MaterialTheme.typography.bodySmall)
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button(enabled = !busy, onClick = {
                                    val title = invite.str("title")
                                    call("pasr_business_community_respond",
                                        JSONObject().put("p_invite", invite.str("invite_id")).put("p_accept", true),
                                        L("Je onderneming doet nu mee aan %@.", title))
                                }) { Text(L("Accepteren")) }
                                OutlinedButton(enabled = !busy, onClick = { confirmDecline = invite }) {
                                    Text(L("Weigeren"), color = MaterialTheme.colorScheme.error)
                                }
                            }
                        }
                        HorizontalDivider()
                    }
                    Text(L("Je beslist zelf of je zaak meedoet. Klantgegevens worden niet tussen ondernemingen gedeeld."),
                        style = MaterialTheme.typography.bodySmall)
                    HorizontalDivider()
                }
                if (owner) {
                    Text(L("Nieuwe gezamenlijke actie"), fontWeight = FontWeight.Bold)
                    OutlinedTextField(name, { name = it }, label = { Text(L("Actienaam")) }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(reward, { reward = it }, label = { Text(L("Gezamenlijke beloning")) }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(required, { required = it }, label = { Text(L("Verschillende winkels (2–20)")) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(days, { days = it }, label = { Text(L("Looptijd in dagen (1–366)")) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(L("Open voor zaken in dezelfde plaats"), Modifier.weight(1f))
                        Switch(checked = openSameCity, onCheckedChange = { openSameCity = it })
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(L("Minimum aantal zaken: %lld", minParticipants), Modifier.weight(1f))
                        TextButton(enabled = minParticipants > 2, onClick = { minParticipants-- }) { Text("−", fontSize = 20.sp) }
                        TextButton(enabled = minParticipants < 20, onClick = { minParticipants++ }) { Text("+", fontSize = 20.sp) }
                    }
                    Button(enabled = !busy, onClick = {
                        val needed = required.toIntOrNull()
                        val duration = days.toIntOrNull()
                        if (name.trim().length !in 3..80 || reward.trim().length !in 3..120 ||
                            needed == null || needed !in 2..20 || duration == null || duration !in 1..366) {
                            show(L("Controleer de naam, beloning, winkels en looptijd."), true)
                            return@Button
                        }
                        busy = true
                        scope.launch {
                            try {
                                val result = Account.rpc("pasr_business_community_create", JSONObject()
                                    .put("p_business", business.id).put("p_name", name.trim())
                                    .put("p_reward", reward.trim()).put("p_required", needed)
                                    .put("p_days", duration)
                                    .put("p_open_same_city", openSameCity)
                                    .put("p_min_participants", minParticipants))
                                val newId = (result as? JSONObject)?.let { j ->
                                    j.str("campaign_id").ifBlank { j.str("id") }
                                }.orEmpty()
                                name = ""; reward = ""; openSameCity = false; minParticipants = 2
                                show(L("Samenwerking gestart. Nodig nu zaken uit om mee te doen."))
                                reload()
                                campaigns.firstOrNull { it.id == newId && newId.isNotBlank() }?.let { managing = it }
                            } catch (e: Exception) { show(e.message ?: L("Er ging iets mis. Probeer het opnieuw."), true) }
                            busy = false
                        }
                    }) { Text(L("Samenwerking starten")) }
                    Text(L("Je nodigt zelf zaken uit; zij beslissen of ze meedoen. De actie start voor klanten zodra het minimum aantal zaken meedoet. Klanten verzamelen een bezoek met een stempel bij elke deelnemende zaak. Klantgegevens worden niet tussen ondernemingen gedeeld."),
                        style = MaterialTheme.typography.bodySmall)
                    HorizontalDivider()
                }
                Text(if (owner) L("Gezamenlijke acties") else L("Acties van je zaak"), fontWeight = FontWeight.Bold)
                if (loaded && campaigns.isEmpty()) Text(if (owner) L("Nog geen gezamenlijke acties")
                    else L("Je zaak doet nog niet mee aan een gezamenlijke actie"))
                campaigns.forEach { campaign ->
                    val json = campaign.json
                    val id = campaign.id
                    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(campaign.name + (if (campaign.isOrganizer) " · " + L("Organisator") else ""), fontWeight = FontWeight.SemiBold)
                        StatusPill(campaign.stateLabel(), stateColor(campaign.state))
                        val lead = listOf(json.str("lead_business"), json.str("lead_city"))
                            .filter { it.isNotBlank() }.joinToString(", ")
                        Text(lead + " · " + L("%lld deelnemende zaken", campaign.participants),
                            style = MaterialTheme.typography.bodySmall)
                        val names = json.optJSONArray("participant_names")
                        if (names != null && names.length() > 0) Text(
                            (0 until names.length()).joinToString(", ") { names.optString(it) },
                            style = MaterialTheme.typography.bodySmall)
                        Text(L("Beloning: %@", json.str("reward")))
                        Text(L("Bezoek %lld verschillende deelnemende winkels", json.optInt("required")),
                            style = MaterialTheme.typography.bodySmall)
                        formatDate(json.str("ends_at"))?.let { Text(L("Loopt tot %@", it), style = MaterialTheme.typography.bodySmall) }
                        if (campaign.openSameCity) Text(L("Open voor zaken in dezelfde plaats"), style = MaterialTheme.typography.bodySmall)
                        if (owner && campaign.isOrganizer && campaign.running) {
                            Button(enabled = !busy, onClick = { managing = campaign }) { Text(L("Zaken uitnodigen")) }
                        }
                        if (!campaign.isParticipant) {
                            if (owner && campaign.openSameCity && campaign.running) Button(enabled = !busy, onClick = {
                                call("pasr_business_community_join", JSONObject().put("p_campaign", id),
                                    L("Je onderneming neemt nu deel."))
                            }) { Text(L("Meedoen (open voor zaken in jouw plaats)")) }
                            else Text(L("Meedoen kan alleen op uitnodiging van de organisator."), style = MaterialTheme.typography.bodySmall)
                        } else {
                            val given = json.optInt("claims_here")
                            Text("✓ " + if (given > 0) L("Je onderneming neemt deel · %lldx uitgegeven", given) else L("Je onderneming neemt deel"))
                            if (campaign.state == "active") {
                                val code = memberCodes[id].orEmpty()
                                OutlinedTextField(code, { memberCodes = memberCodes + (id to it) },
                                    label = { Text(L("Lidcode bij de kassa (PZ…)")) }, modifier = Modifier.fillMaxWidth())
                                Button(enabled = !busy && code.trim().uppercase().startsWith("PZ"), onClick = {
                                    busy = true
                                    scope.launch {
                                        try {
                                            val result = Account.rpc("pasr_business_community_claim", JSONObject()
                                                .put("p_campaign", id)
                                                .put("p_business", business.id)
                                                .put("p_member_code", code.trim().uppercase())) as? JSONObject
                                            show(L("Beloning uitgegeven: %@. Een tweede inwisseling is niet mogelijk.",
                                                result?.str("reward")?.takeIf { it.isNotBlank() } ?: L("gezamenlijke beloning")))
                                            memberCodes = memberCodes - id
                                            reload()
                                        } catch (e: Exception) { show(e.message ?: L("Er ging iets mis. Probeer het opnieuw."), true) }
                                        busy = false
                                    }
                                }) { Text(L("Gezamenlijke beloning controleren en uitgeven")) }
                            }
                            if (owner && campaign.running) OutlinedButton(enabled = !busy, onClick = {
                                confirm = (if (campaign.isOrganizer) "cancel" else "leave") to campaign
                            }) { Text(if (campaign.isOrganizer) L("Actie stoppen") else L("Uitstappen")) }
                        }
                    }
                    HorizontalDivider()
                }
                Text(L("Bij het scannen van een klant zie je vanzelf of die een gezamenlijke beloning heeft verdiend."),
                    style = MaterialTheme.typography.bodySmall)
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text(L("Sluiten")) } }
    )
    confirm?.let { (kind, campaign) ->
        val cancel = kind == "cancel"
        AlertDialog(
            onDismissRequest = { confirm = null },
            title = { Text(if (cancel) L("Actie stoppen?") else L("Uitstappen?")) },
            text = {
                Text(if (cancel) L("De actie verdwijnt bij klanten en alle deelnemende zaken. Uitgegeven beloningen blijven geregistreerd.")
                     else L("Bezoeken bij jouw zaak tellen daarna niet meer mee voor klanten."))
            },
            confirmButton = {
                TextButton(onClick = {
                    confirm = null
                    val args = JSONObject().put("p_campaign", campaign.id)
                    if (cancel) call("pasr_business_community_cancel", args, L("De actie is gestopt."))
                    else call("pasr_business_community_leave", args, L("Je onderneming doet niet meer mee aan deze actie."))
                }) { Text(if (cancel) L("Actie stoppen") else L("Uitstappen"), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirm = null }) { Text(L("Annuleren")) } }
        )
    }
    confirmDecline?.let { invite ->
        AlertDialog(
            onDismissRequest = { confirmDecline = null },
            title = { Text(L("Uitnodiging weigeren?")) },
            text = { Text(L("De organisator ziet dat je zaak niet meedoet.")) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDecline = null
                    call("pasr_business_community_respond",
                        JSONObject().put("p_invite", invite.str("invite_id")).put("p_accept", false),
                        L("Uitnodiging geweigerd."))
                }) { Text(L("Weigeren"), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmDecline = null }) { Text(L("Annuleren")) } }
        )
    }
    managing?.let { campaign ->
        CommunityInviteDialog(business, campaign.id, campaign.name, campaign.stateLabel(), campaign.state) {
            managing = null
            scope.launch { reload() }
        }
    }
}

/**
 * Organisator: zaken zoeken en uitnodigen, uitnodigen via link of QR en de status per zaak (intrekken, verwijderen),
 * zoals CommunityInviteManagerView op iOS.
 */
@Composable
private fun CommunityInviteDialog(
    business: Business,
    campaignId: String,
    campaignName: String,
    stateLabel: String,
    state: String,
    onClose: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    var invites by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    var email by remember { mutableStateOf("") }
    var link by remember { mutableStateOf<String?>(null) }
    var sentTo by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var failed by remember { mutableStateOf(false) }
    var confirmRevoke by remember { mutableStateOf<JSONObject?>(null) }
    var confirmRemove by remember { mutableStateOf<JSONObject?>(null) }

    fun show(text: String, error: Boolean = false) { message = text; failed = error }
    val emailOk = email.trim().isEmpty() || Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(email.trim())

    suspend fun loadInvites() {
        try {
            invites = (Account.rpc("pasr_business_community_invites",
                JSONObject().put("p_business", business.id).put("p_campaign", campaignId)) as? JSONArray).objects()
        } catch (e: Exception) { show(e.message ?: L("Er ging iets mis. Probeer het opnieuw."), true) }
        loaded = true
    }

    suspend fun search() {
        val q = query.trim()
        if (q.length < 2) { results = emptyList(); return }
        searching = true
        try {
            val r = Account.rpc("pasr_business_community_search", JSONObject()
                .put("p_business", business.id).put("p_campaign", campaignId).put("p_query", q)) as? JSONArray
            if (q == query.trim()) results = r.objects().filter { it.str("business_id") != business.id }
        } catch (e: Exception) { show(e.message ?: L("Er ging iets mis. Probeer het opnieuw."), true) }
        searching = false
    }

    fun act(fn: String, args: JSONObject, success: String, after: suspend () -> Unit = {}) {
        busy = true
        scope.launch {
            try {
                Account.rpc(fn, args.put("p_business", business.id))
                show(success)
                loadInvites()
                after()
            } catch (e: Exception) { show(e.message ?: L("Er ging iets mis. Probeer het opnieuw."), true) }
            busy = false
        }
    }

    LaunchedEffect(campaignId) { loadInvites() }
    LaunchedEffect(query) {
        delay(400)
        search()
    }

    AlertDialog(
        onDismissRequest = onClose,
        title = { Text(L("Zaken uitnodigen")) },
        text = {
            Column(Modifier.fillMaxWidth().heightIn(max = 650.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(campaignName, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    StatusPill(stateLabel, stateColor(state))
                }
                if (state == "waiting") Text(L("De actie start zodra genoeg zaken meedoen."), style = MaterialTheme.typography.bodySmall)
                if (message.isNotBlank()) Text(message, color = if (failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)
                HorizontalDivider()

                Text(L("Zaken zoeken"), fontWeight = FontWeight.Bold)
                OutlinedTextField(query, { query = it }, label = { Text(L("Zoek op naam of plaats")) },
                    singleLine = true, modifier = Modifier.fillMaxWidth())
                if (searching) Text("…")
                results.forEach { result ->
                    val status = result.str("invite_status")
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        val logo = remember(result.str("logo_url")) {
                            // base64 of data-URL (zoals de logo's van zaken); een https-URL laten we hier weg
                            result.str("logo_url").takeIf { it.isNotBlank() && !it.startsWith("http") }
                                ?.let { LogoImage.bitmap(it) }
                        }
                        if (logo != null) {
                            Image(logo.asImageBitmap(), null, Modifier.size(36.dp).clip(RoundedCornerShape(8.dp)))
                            Spacer(Modifier.width(10.dp))
                        }
                        Column(Modifier.weight(1f)) {
                            Text(result.str("name"), fontWeight = FontWeight.SemiBold)
                            if (result.str("city").isNotBlank()) Text(result.str("city"), style = MaterialTheme.typography.bodySmall)
                        }
                        if (status == "invited" || status == "accepted") StatusPill(inviteStatusLabel(status), inviteStatusColor(status))
                        else Button(enabled = !busy, onClick = {
                            val target = result.str("business_id")
                            act("pasr_business_community_invite",
                                JSONObject().put("p_campaign", campaignId).put("p_target", target),
                                L("%@ is uitgenodigd.", result.str("name"))) { search() }
                        }) { Text(L("Uitnodigen")) }
                    }
                }
                if (!searching && results.isEmpty() && query.trim().length >= 2) Text(L("Geen zaken gevonden"))
                Text(L("De zaak krijgt een melding en beslist zelf of zij meedoet."), style = MaterialTheme.typography.bodySmall)
                HorizontalDivider()

                Text(L("Uitnodigen via link of QR"), fontWeight = FontWeight.Bold)
                OutlinedTextField(email, { email = it }, label = { Text(L("E-mailadres (optioneel)")) }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), modifier = Modifier.fillMaxWidth())
                Button(enabled = !busy && emailOk, onClick = {
                    val mail = email.trim().lowercase()
                    busy = true
                    scope.launch {
                        try {
                            val r = Account.rpc("pasr_business_community_invite_email", JSONObject()
                                .put("p_business", business.id).put("p_campaign", campaignId)
                                .put("p_email", if (mail.isEmpty()) JSONObject.NULL else mail)) as? JSONObject
                            val token = r?.str("token").orEmpty()
                            val url = r?.str("link")?.takeIf { it.isNotBlank() }
                                ?: if (token.isNotBlank()) "https://pasr.nl/zakelijk/uitnodiging/?t=$token" else null
                            if (url == null) show(L("Er ging iets mis. Probeer het opnieuw."), true)
                            else {
                                link = url
                                sentTo = mail.ifEmpty { null }
                                email = ""
                                message = ""
                                loadInvites()
                            }
                        } catch (e: Exception) { show(e.message ?: L("Er ging iets mis. Probeer het opnieuw."), true) }
                        busy = false
                    }
                }) { Text(L("Uitnodigingslink maken")) }
                link?.let { url ->
                    sentTo?.let { Text(L("Uitnodiging verstuurd naar %@", it), color = Color(0xFF2ED3A6), style = MaterialTheme.typography.bodySmall) }
                    Text(url, style = MaterialTheme.typography.bodySmall)
                    val qr = remember(url) { QrCode.bitmap(url, 480) }
                    if (qr != null) Image(qr.asImageBitmap(), L("QR-code van de uitnodigingslink"),
                        Modifier.size(200.dp).align(Alignment.CenterHorizontally))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = {
                            context.shareText(L("Doe mee met onze gezamenlijke Pasr-actie \"%@\".", campaignName) + "\n" + url, campaignName)
                        }) { Text(L("Delen")) }
                        OutlinedButton(onClick = {
                            val clipboard = context.getSystemService(android.content.ClipboardManager::class.java)
                            clipboard?.setPrimaryClip(android.content.ClipData.newPlainText("Pasr", url))
                            show(L("Link gekopieerd."))
                        }) { Text(L("Kopiëren")) }
                    }
                }
                Text(L("Voor zaken die je niet kunt vinden of die Pasr Zakelijk nog niet gebruiken. Met een e-mailadres stuurt Pasr de uitnodiging ook per mail."),
                    style = MaterialTheme.typography.bodySmall)
                HorizontalDivider()

                Text(L("Status per zaak"), fontWeight = FontWeight.Bold)
                if (loaded && invites.isEmpty()) Text(L("Nog niemand uitgenodigd"))
                invites.forEach { invite ->
                    val status = invite.str("status").ifBlank { "invited" }
                    val title = invite.str("name").ifBlank { invite.str("email") }.ifBlank { L("Uitnodigingslink") }
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(title, fontWeight = FontWeight.SemiBold)
                                val sub = listOfNotNull(invite.str("city").ifBlank { null }, formatDate(invite.str("created_at"), "d MMM yyyy"))
                                    .joinToString(" · ")
                                if (sub.isNotBlank()) Text(sub, style = MaterialTheme.typography.bodySmall)
                            }
                            StatusPill(inviteStatusLabel(status), inviteStatusColor(status))
                        }
                        val target = invite.str("business_id")
                        if (status == "invited") TextButton(enabled = !busy, onClick = { confirmRevoke = invite }) {
                            Text(L("Intrekken"), color = MaterialTheme.colorScheme.error)
                        } else if (status == "accepted" && target.isNotBlank() && target != business.id) TextButton(enabled = !busy, onClick = { confirmRemove = invite }) {
                            Text(L("Verwijderen uit actie"), color = MaterialTheme.colorScheme.error)
                        }
                    }
                    HorizontalDivider()
                }
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text(L("Klaar")) } }
    )
    confirmRevoke?.let { invite ->
        AlertDialog(
            onDismissRequest = { confirmRevoke = null },
            title = { Text(L("Uitnodiging intrekken?")) },
            text = { Text(L("De uitnodiging en de link werken daarna niet meer.")) },
            confirmButton = {
                TextButton(onClick = {
                    confirmRevoke = null
                    act("pasr_business_community_revoke", JSONObject().put("p_invite", invite.str("invite_id")),
                        L("Uitnodiging ingetrokken.")) { search() }
                }) { Text(L("Intrekken"), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmRevoke = null }) { Text(L("Annuleren")) } }
        )
    }
    confirmRemove?.let { invite ->
        AlertDialog(
            onDismissRequest = { confirmRemove = null },
            title = { Text(L("Zaak verwijderen uit de actie?")) },
            text = { Text(L("Bezoeken bij deze zaak tellen daarna niet meer mee voor klanten. De zaak krijgt hiervan een melding.")) },
            confirmButton = {
                TextButton(onClick = {
                    confirmRemove = null
                    act("pasr_business_community_remove",
                        JSONObject().put("p_campaign", campaignId).put("p_target", invite.str("business_id")),
                        L("Zaak verwijderd uit de actie."))
                }) { Text(L("Verwijderen"), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmRemove = null }) { Text(L("Annuleren")) } }
        )
    }
}
