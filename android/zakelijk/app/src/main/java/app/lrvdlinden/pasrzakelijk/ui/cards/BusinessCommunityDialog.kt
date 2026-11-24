package app.lrvdlinden.pasrzakelijk.ui.cards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
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
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasrzakelijk.data.Account
import app.lrvdlinden.pasrzakelijk.data.Business
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/** Dezelfde beveiligde community-RPC's als iOS. */
@Composable
fun BusinessCommunityDialog(business: Business, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf("") }
    var reward by remember { mutableStateOf("") }
    var required by remember { mutableStateOf("3") }
    var days by remember { mutableStateOf("60") }
    var memberCode by remember { mutableStateOf("") }
    var campaigns by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }

    suspend fun reload() {
        try {
            val result = Account.rpc("pasr_business_community_list",
                JSONObject().put("p_business", business.id)) as? JSONArray
            campaigns = (0 until (result?.length() ?: 0)).mapNotNull { result?.optJSONObject(it) }
        } catch (e: Exception) { message = e.message ?: "Kan acties niet ophalen." }
    }
    LaunchedEffect(business.id) { reload() }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("Samenwerkingen") },
        text = {
            Column(Modifier.fillMaxWidth().heightIn(max = 650.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Nieuwe winkelstraatactie")
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
                Text("Er worden geen klantgegevens met andere ondernemers gedeeld.")
                Text("Beschikbare gezamenlijke acties")
                if (campaigns.isEmpty()) Text("Nog geen winkelstraatacties.")
                campaigns.forEach { campaign ->
                    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(campaign.optString("name"))
                        Text(campaign.optString("lead_business") + " · " +
                            campaign.optInt("participants") + " deelnemende zaken")
                        Text("Beloning: " + campaign.optString("reward") + " · " +
                            campaign.optInt("required") + " verschillende winkels")
                        if (!campaign.optBoolean("joined")) {
                            Button(enabled = !busy, onClick = {
                                busy = true
                                scope.launch {
                                    try {
                                        Account.rpc("pasr_business_community_join", JSONObject()
                                            .put("p_business", business.id)
                                            .put("p_campaign", campaign.optString("id")))
                                        message = "Je onderneming neemt nu deel."
                                        reload()
                                    } catch (e: Exception) { message = e.message ?: "Deelnemen mislukt." }
                                    busy = false
                                }
                            }) { Text("Met mijn onderneming deelnemen") }
                        } else {
                            Text("✓ Je onderneming neemt deel")
                            OutlinedTextField(memberCode, { memberCode = it },
                                label = { Text("Lidcode klant (PZ…)") }, modifier = Modifier.fillMaxWidth())
                            Button(enabled = !busy && memberCode.trim().uppercase().startsWith("PZ"), onClick = {
                                busy = true
                                scope.launch {
                                    try {
                                        val result = Account.rpc("pasr_business_community_claim", JSONObject()
                                            .put("p_campaign", campaign.optString("id"))
                                            .put("p_business", business.id)
                                            .put("p_member_code", memberCode.trim().uppercase())) as? JSONObject
                                        message = "Beloning uitgegeven: " +
                                            (result?.optString("reward") ?: "gezamenlijke beloning")
                                        memberCode = ""
                                    } catch (e: Exception) { message = e.message ?: "Beloning niet beschikbaar." }
                                    busy = false
                                }
                            }) { Text("Beloning controleren en uitgeven") }
                        }
                    }
                }
                if (message.isNotBlank()) Text(message)
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text("Sluiten") } }
    )
}
