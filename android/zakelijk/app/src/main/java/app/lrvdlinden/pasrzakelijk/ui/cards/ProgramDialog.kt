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
    var retentionDays by remember { mutableStateOf("30") }
    var referralBonus by remember { mutableStateOf("1") }
    var campaignMultiplier by remember { mutableStateOf("2") }
    var campaignWeekday by remember { mutableStateOf("2") }
    var vipSilver by remember { mutableStateOf("10") }
    var vipGold by remember { mutableStateOf("25") }
    var communityName by remember { mutableStateOf("") }
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
            retentionDays = (s.optJSONObject("retention")?.optInt("days", 30) ?: 30).toString()
            referralBonus = (s.optJSONObject("referral")?.optInt("bonus", 1) ?: 1).toString()
            campaignMultiplier = (s.optJSONObject("campaign")?.optInt("multiplier", 2) ?: 2).toString()
            campaignWeekday = (s.optJSONObject("campaign")?.optInt("weekday", 2) ?: 2).toString()
            vipSilver = (s.optJSONObject("vip")?.optInt("silver", 10) ?: 10).toString()
            vipGold = (s.optJSONObject("vip")?.optInt("gold", 25) ?: 25).toString()
            communityName = s.optJSONObject("community")?.optString("name").orEmpty()
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
                if (retention) OutlinedTextField(retentionDays, { retentionDays = it }, label = { Text("Na hoeveel dagen (7–365)") }, modifier = Modifier.fillMaxWidth())
                Row { option("Vrienden uitnodigen", referral) { referral = it } }
                TextButton(onClick = { referralHelp = !referralHelp }) { Text("ⓘ Uitleg vrienden uitnodigen") }
                if (referralHelp) Text("Je schakelt de vriendenactie per kaart in. Een klant deelt een persoonlijke uitnodigingslink; de nieuwe klant krijgt eerst een geverifieerde stempel aan de kassa. Pas daarna krijgen beiden de ingestelde bonus. Zelfuitnodigingen tellen niet mee.")
                if (referral) OutlinedTextField(referralBonus, { referralBonus = it }, label = { Text("Extra stempels per persoon (1–3)") }, modifier = Modifier.fillMaxWidth())
                option("Tijdelijke stempelacties", campaign) { campaign = it }
                if (campaign) {
                    OutlinedTextField(campaignMultiplier, { campaignMultiplier = it }, label = { Text("Stempelvermenigvuldiger (1–3)") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(campaignWeekday, { campaignWeekday = it }, label = { Text("Weekdag (0 zondag t/m 6 zaterdag)") }, modifier = Modifier.fillMaxWidth())
                }
                option("VIP-niveaus", vip) { vip = it }
                if (vip) {
                    OutlinedTextField(vipSilver, { vipSilver = it }, label = { Text("Zilver vanaf aantal bezoeken") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(vipGold, { vipGold = it }, label = { Text("Goud vanaf aantal bezoeken") }, modifier = Modifier.fillMaxWidth())
                }
                option("Meerdere vestigingen", locations) { locations = it }
                if (locations) OutlinedTextField(locationsText, { locationsText = it },
                    label = { Text("Vestigingen, één per regel") }, modifier = Modifier.fillMaxWidth())
                option("Marketingkalender", marketing) { marketing = it }
                if (marketing) OutlinedTextField(campaignName, { campaignName = it },
                    label = { Text("Naam campagne") }, modifier = Modifier.fillMaxWidth())
                option("Gezamenlijke winkelstraatactie", community) { community = it }
                if (community) OutlinedTextField(communityName, { communityName = it }, label = { Text("Naam gezamenlijke actie") }, modifier = Modifier.fillMaxWidth())
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
                val days = retentionDays.toIntOrNull()
                val bonus = referralBonus.toIntOrNull()
                val multiplier = campaignMultiplier.toIntOrNull()
                val weekday = campaignWeekday.toIntOrNull()
                val silver = vipSilver.toIntOrNull()
                val gold = vipGold.toIntOrNull()
                if (days == null || days !in 7..365 || bonus == null || bonus !in 1..3 ||
                    multiplier == null || multiplier !in 1..3 || weekday == null || weekday !in 0..6 ||
                    silver == null || silver !in 1..1000 || gold == null || gold !in (silver+1)..2000) {
                    message = "Controleer alle dagen, bonussen, actiedagen en VIP-grenzen."; return@Button
                }
                if (r.length() > 8) { message = "Maximaal acht mijlpalen per kaart."; return@Button }
                val milestones = (0 until r.length()).map { r.getJSONObject(it).optInt("stamps") }
                if (milestones.distinct().size != milestones.size) {
                    message = "Elke beloningsmijlpaal moet uniek zijn."; return@Button
                }
                val sortedRewards = JSONArray()
                (0 until r.length()).map { r.getJSONObject(it) }.sortedBy { it.optInt("stamps") }.forEach { sortedRewards.put(it) }
                saving = true
                scope.launch {
                    try {
                        val cfg = JSONObject()
                            .put("rewards", sortedRewards)
                            .put("retention", JSONObject().put("enabled", retention).put("days", days))
                            .put("referral", JSONObject().put("enabled", referral).put("bonus", bonus))
                            .put("campaign", JSONObject().put("enabled", campaign).put("multiplier", multiplier).put("weekday", weekday))
                            .put("vip", JSONObject().put("enabled", vip).put("silver", silver).put("gold", gold))
                            .put("locations", JSONObject().put("enabled", locations)
                                .put("names", JSONArray(locationsText.lines().map { it.trim() }.filter { it.isNotEmpty() })))
                            .put("marketing", JSONObject().put("enabled", marketing).put("name", campaignName))
                            .put("community", JSONObject().put("enabled", community).put("name", communityName.take(80)))
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
