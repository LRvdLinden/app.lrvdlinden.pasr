package app.lrvdlinden.pasrzakelijk.ui.cards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
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
import app.lrvdlinden.pasrzakelijk.data.BusinessCard
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/** Kaartgebonden instellingen met de echte Pasr Zakelijk-accountsession. */
@Composable
fun ProgramDialog(card: BusinessCard, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var rewardsOn by remember { mutableStateOf(false) }
    var rewardsText by remember { mutableStateOf("") }
    var referral by remember { mutableStateOf(false) }
    var retention by remember { mutableStateOf(false) }
    var campaign by remember { mutableStateOf(false) }
    var vip by remember { mutableStateOf(false) }
    var locations by remember { mutableStateOf(false) }
    var marketing by remember { mutableStateOf(false) }
    var community by remember { mutableStateOf(false) }
    var referralHelp by remember { mutableStateOf(false) }
    var locationsText by remember { mutableStateOf("") }
    var campaignName by remember { mutableStateOf("") }

    LaunchedEffect(card.id) {
        try {
            val r = Account.rpc("pasr_business_program", JSONObject().put("p_card", card.id)) as? JSONObject
            val s = r?.optJSONObject("settings") ?: JSONObject()
            val rew = s.optJSONArray("rewards") ?: JSONArray()
            rewardsOn = rew.length() > 0
            rewardsText = (0 until rew.length()).mapNotNull { i ->
                rew.optJSONObject(i)?.let { j -> j.optInt("stamps").toString() + ": " + j.optString("title") }
            }.joinToString("\n")
            referral = s.optJSONObject("referral")?.optBoolean("enabled") == true
            retention = s.optJSONObject("retention")?.optBoolean("enabled") == true
            campaign = s.optJSONObject("campaign")?.optBoolean("enabled") == true
            vip = s.optJSONObject("vip")?.optBoolean("enabled") == true
            locations = s.optJSONObject("locations")?.optBoolean("enabled") == true
            marketing = s.optJSONObject("marketing")?.optBoolean("enabled") == true
            community = s.optJSONObject("community")?.optBoolean("enabled") == true
            val arr = s.optJSONObject("locations")?.optJSONArray("names") ?: JSONArray()
            locationsText = (0 until arr.length()).map { arr.optString(it) }.joinToString("\n")
            campaignName = s.optJSONObject("marketing")?.optString("name").orEmpty()
        } catch (e: Exception) { message = e.message ?: "Instellingen niet beschikbaar." }
        loading = false
    }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("Acties en beloningen · " + card.name) },
        text = {
            Column(Modifier.fillMaxWidth().heightIn(max = 600.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (loading) CircularProgressIndicator()
                @Composable fun option(label: String, checked: Boolean, change: (Boolean) -> Unit) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(label, modifier = Modifier.weight(1f))
                        Checkbox(checked = checked, onCheckedChange = change)
                    }
                }
                option("Meerdere beloningen", rewardsOn) { rewardsOn = it }
                if (rewardsOn) {
                    OutlinedTextField(rewardsText, { rewardsText = it },
                        label = { Text("Bijvoorbeeld 3: Gratis koekje") }, modifier = Modifier.fillMaxWidth(), minLines = 3)
                }
                option("Terugkomacties", retention) { retention = it }
                Row { option("Vrienden uitnodigen", referral) { referral = it } }
                TextButton(onClick = { referralHelp = !referralHelp }) { Text("ⓘ Uitleg vrienden uitnodigen") }
                if (referralHelp) Text("De ondernemer bepaalt of deze kaart referrals gebruikt. Een bonus mag pas na een geverifieerde eerste aankoop worden uitgegeven, niet bij alleen aanmelden.")
                option("Tijdelijke stempelacties", campaign) { campaign = it }
                option("VIP-niveaus", vip) { vip = it }
                option("Meerdere vestigingen", locations) { locations = it }
                if (locations) OutlinedTextField(locationsText, { locationsText = it },
                    label = { Text("Vestigingen, één per regel") }, modifier = Modifier.fillMaxWidth())
                option("Marketingkalender", marketing) { marketing = it }
                if (marketing) OutlinedTextField(campaignName, { campaignName = it },
                    label = { Text("Naam campagne") }, modifier = Modifier.fillMaxWidth())
                option("Gezamenlijke winkelstraatactie", community) { community = it }
                if (message.isNotEmpty()) Text(message)
            }
        },
        confirmButton = {
            Button(enabled = !saving && !loading, onClick = {
                val r = JSONArray()
                if (rewardsOn) for (line in rewardsText.lines().filter { it.isNotBlank() }) {
                    val parts = line.split(":", limit = 2)
                    val n = parts.firstOrNull()?.trim()?.toIntOrNull()
                    if (n == null || n !in 2..card.stampsTotal || parts.size < 2 || parts[1].trim().length < 3) {
                        message = "Gebruik bijvoorbeeld 3: Gratis koekje"; return@Button
                    }
                    r.put(JSONObject().put("stamps", n).put("title", parts[1].trim()))
                }
                saving = true
                scope.launch {
                    try {
                        val cfg = JSONObject()
                            .put("rewards", r)
                            .put("retention", JSONObject().put("enabled", retention).put("days", 30))
                            .put("referral", JSONObject().put("enabled", referral).put("bonus", 1))
                            .put("campaign", JSONObject().put("enabled", campaign).put("multiplier", 2).put("weekday", 2))
                            .put("vip", JSONObject().put("enabled", vip).put("silver", 10).put("gold", 25))
                            .put("locations", JSONObject().put("enabled", locations)
                                .put("names", JSONArray(locationsText.lines().map { it.trim() }.filter { it.isNotEmpty() })))
                            .put("marketing", JSONObject().put("enabled", marketing).put("name", campaignName))
                            .put("community", JSONObject().put("enabled", community).put("name", ""))
                        Account.rpc("pasr_business_program", JSONObject().put("p_card", card.id).put("p_settings", cfg))
                        message = "Instellingen opgeslagen."
                    } catch (e: Exception) {
                        message = e.message ?: "Opslaan mislukt."
                    }
                    saving = false
                }
            }) { Text(if (saving) "Opslaan…" else "Opslaan") }
        },
        dismissButton = { TextButton(onClick = onClose) { Text("Sluiten") } }
    )
}
