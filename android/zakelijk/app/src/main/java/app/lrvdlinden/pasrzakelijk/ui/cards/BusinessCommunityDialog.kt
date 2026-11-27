package app.lrvdlinden.pasrzakelijk.ui.cards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasrzakelijk.data.Account
import app.lrvdlinden.pasrzakelijk.data.Business
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Dezelfde beveiligde community-RPC's als iOS en pasr.nl/zakelijk.
 * Eigenaar: starten, deelnemen, uitstappen, stoppen (alleen initiatiefnemer) en uitgeven.
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
    // lidcode per actie, zodat typen bij de ene actie de andere niet vult
    var memberCodes by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var campaigns by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf<Pair<String, JSONObject>?>(null) }   // "cancel"/"leave" + actie

    suspend fun reload() {
        try {
            val result = Account.rpc("pasr_business_community_list",
                JSONObject().put("p_business", business.id)) as? JSONArray
            campaigns = (0 until (result?.length() ?: 0)).mapNotNull { result?.optJSONObject(it) }
        } catch (e: Exception) { message = e.message ?: "Kan acties niet ophalen." }
    }

    fun call(fn: String, args: JSONObject, success: String) {
        busy = true
        scope.launch {
            try {
                Account.rpc(fn, args.put("p_business", business.id))
                message = success
                reload()
            } catch (e: Exception) { message = e.message ?: "Dat lukte niet." }
            busy = false
        }
    }

    fun endDate(campaign: JSONObject): String? = runCatching {
        OffsetDateTime.parse(campaign.optString("ends_at"))
            .format(DateTimeFormatter.ofPattern("d MMMM yyyy", Locale.forLanguageTag("nl-NL")))
    }.getOrNull()

    LaunchedEffect(business.id) { reload() }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("Samenwerkingen") },
        text = {
            Column(Modifier.fillMaxWidth().heightIn(max = 650.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (owner) {
                    Text("Nieuwe winkelstraatactie", fontWeight = FontWeight.Bold)
                    OutlinedTextField(name, { name = it }, label = { Text("Actienaam") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(reward, { reward = it }, label = { Text("Gezamenlijke beloning") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(required, { required = it }, label = { Text("Verschillende winkels (2–20)") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(days, { days = it }, label = { Text("Looptijd in dagen (1–366)") }, modifier = Modifier.fillMaxWidth())
                    Button(enabled = !busy, onClick = {
                        val needed = required.toIntOrNull()
                        val duration = days.toIntOrNull()
                        if (name.trim().length !in 3..80 || reward.trim().length !in 3..120 ||
                            needed == null || needed !in 2..20 || duration == null || duration !in 1..366) {
                            message = "Controleer de naam, beloning, winkels en looptijd."
                            return@Button
                        }
                        busy = true
                        scope.launch {
                            try {
                                Account.rpc("pasr_business_community_create", JSONObject()
                                    .put("p_business", business.id).put("p_name", name.trim())
                                    .put("p_reward", reward.trim()).put("p_required", needed)
                                    .put("p_days", duration))
                                name = ""; reward = ""
                                message = "Samenwerking gestart. Andere ondernemingen beslissen zelf of ze deelnemen."
                                reload()
                            } catch (e: Exception) { message = e.message ?: "Actie maken mislukt." }
                            busy = false
                        }
                    }) { Text("Samenwerking starten") }
                    Text("Klanten verzamelen een bezoek met een stempel bij elke deelnemende zaak. Er worden geen klantgegevens met andere ondernemers gedeeld.",
                        style = MaterialTheme.typography.bodySmall)
                    HorizontalDivider()
                }
                Text(if (owner) "Beschikbare gezamenlijke acties" else "Acties van je zaak", fontWeight = FontWeight.Bold)
                if (campaigns.isEmpty()) Text(if (owner) "Nog geen winkelstraatacties."
                    else "Je zaak doet nog niet mee aan een gezamenlijke actie.")
                campaigns.forEach { campaign ->
                    val id = campaign.optString("id")
                    val isLead = campaign.optBoolean("is_lead")
                    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(campaign.optString("name") + (if (isLead) " · initiatiefnemer" else ""), fontWeight = FontWeight.SemiBold)
                        val lead = listOf(campaign.optString("lead_business"), campaign.optString("lead_city"))
                            .filter { it.isNotBlank() }.joinToString(", ")
                        Text(lead + " · " + campaign.optInt("participants") + " deelnemende zaken",
                            style = MaterialTheme.typography.bodySmall)
                        val names = campaign.optJSONArray("participant_names")
                        if (names != null && names.length() > 0) Text(
                            (0 until names.length()).joinToString(", ") { names.optString(it) },
                            style = MaterialTheme.typography.bodySmall)
                        Text("Beloning: " + campaign.optString("reward") + " · " +
                            campaign.optInt("required") + " verschillende winkels")
                        endDate(campaign)?.let { Text("Loopt tot $it", style = MaterialTheme.typography.bodySmall) }
                        if (!campaign.optBoolean("joined")) {
                            if (owner) Button(enabled = !busy, onClick = {
                                call("pasr_business_community_join", JSONObject().put("p_campaign", id),
                                    "Je onderneming neemt nu deel.")
                            }) { Text("Met mijn onderneming deelnemen") }
                        } else {
                            val given = campaign.optInt("claims_here")
                            Text("✓ Je onderneming neemt deel" + (if (given > 0) " · ${given}x uitgegeven" else ""))
                            val code = memberCodes[id].orEmpty()
                            OutlinedTextField(code, { memberCodes = memberCodes + (id to it) },
                                label = { Text("Lidcode klant (PZ…)") }, modifier = Modifier.fillMaxWidth())
                            Button(enabled = !busy && code.trim().uppercase().startsWith("PZ"), onClick = {
                                busy = true
                                scope.launch {
                                    try {
                                        val result = Account.rpc("pasr_business_community_claim", JSONObject()
                                            .put("p_campaign", id)
                                            .put("p_business", business.id)
                                            .put("p_member_code", code.trim().uppercase())) as? JSONObject
                                        message = "Beloning uitgegeven: " +
                                            (result?.optString("reward")?.takeIf { it.isNotBlank() } ?: "gezamenlijke beloning")
                                        memberCodes = memberCodes - id
                                        reload()
                                    } catch (e: Exception) { message = e.message ?: "Beloning niet beschikbaar." }
                                    busy = false
                                }
                            }) { Text("Beloning controleren en uitgeven") }
                            if (owner) OutlinedButton(enabled = !busy, onClick = {
                                confirm = (if (isLead) "cancel" else "leave") to campaign
                            }) { Text(if (isLead) "Actie stoppen" else "Uitstappen") }
                        }
                    }
                    HorizontalDivider()
                }
                Text("Bij het scannen van een klant zie je vanzelf of die een gezamenlijke beloning heeft verdiend.",
                    style = MaterialTheme.typography.bodySmall)
                if (message.isNotBlank()) Text(message, color = MaterialTheme.colorScheme.primary)
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text("Sluiten") } }
    )
    confirm?.let { (kind, campaign) ->
        val cancel = kind == "cancel"
        AlertDialog(
            onDismissRequest = { confirm = null },
            title = { Text(if (cancel) "Actie stoppen?" else "Uitstappen?") },
            text = {
                Text(if (cancel) "De actie verdwijnt bij klanten en alle deelnemende zaken. Uitgegeven beloningen blijven geregistreerd."
                     else "Bezoeken bij jouw zaak tellen daarna niet meer mee voor klanten.")
            },
            confirmButton = {
                TextButton(onClick = {
                    confirm = null
                    val args = JSONObject().put("p_campaign", campaign.optString("id"))
                    if (cancel) call("pasr_business_community_cancel", args, "De actie is gestopt.")
                    else call("pasr_business_community_leave", args, "Je onderneming doet niet meer mee aan deze actie.")
                }) { Text(if (cancel) "Actie stoppen" else "Uitstappen", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirm = null }) { Text("Annuleren") } }
        )
    }
}
