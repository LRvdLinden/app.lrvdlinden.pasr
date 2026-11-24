package app.lrvdlinden.pasrzakelijk.ui.cards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
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
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.time.OffsetDateTime

/** Zelfgekozen, herbruikbare winkelactiecode. Niet hetzelfde als een persoonlijke PC-bon. */
@Composable
fun PromoCodesDialog(businessId: String, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var title by remember { mutableStateOf("") }
    var kind by remember { mutableStateOf("percent") }
    var amount by remember { mutableStateOf("10") }
    var minSpend by remember { mutableStateOf("0") }
    var maxUses by remember { mutableStateOf("100") }
    var days by remember { mutableStateOf("30") }
    var active by remember { mutableStateOf(false) }
    var verify by remember { mutableStateOf("") }
    var verified by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }

    suspend fun reload() {
        try {
            val res = Account.rpc("pasr_business_promo_list",
                JSONObject().put("p_business", businessId)) as? JSONArray
            rows = (0 until (res?.length() ?: 0)).mapNotNull { res?.optJSONObject(it) }
        } catch (e: Exception) { status = e.message ?: "Kan actiecodes niet laden." }
    }
    LaunchedEffect(businessId) { reload() }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("Actiecodes") },
        text = {
            Column(Modifier.fillMaxWidth().heightIn(max = 580.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Maak een eigen actiecode die klanten aan de kassa noemen. Apart van persoonlijke kortingsbonnen.")
                OutlinedTextField(code, { code = it.uppercase() }, label = { Text("Code, bv. HERFST20") },
                    modifier = Modifier.fillMaxWidth())
                OutlinedTextField(title, { title = it }, label = { Text("Naam actie") }, modifier = Modifier.fillMaxWidth())
                Row {
                    TextButton(onClick = { kind = "percent" }) { Text(if (kind == "percent") "✓ Percentage" else "Percentage") }
                    TextButton(onClick = { kind = "amount" }) { Text(if (kind == "amount") "✓ Bedrag €" else "Bedrag €") }
                }
                OutlinedTextField(amount, { amount = it }, label = { Text("Korting") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(minSpend, { minSpend = it }, label = { Text("Minimale besteding (€)") },
                    modifier = Modifier.fillMaxWidth())
                OutlinedTextField(days, { days = it }, label = { Text("Geldigheid vanaf nu (dagen)") },
                    modifier = Modifier.fillMaxWidth())
                OutlinedTextField(maxUses, { maxUses = it }, label = { Text("Maximaal aantal gebruiken") },
                    modifier = Modifier.fillMaxWidth())
                Row { Text("Actiecode activeren", Modifier.weight(1f)); Checkbox(active, onCheckedChange = { active = it }) }
                Button(enabled = !busy && code.length in 4..24 && title.length >= 3, onClick = {
                    val value = amount.replace(',', '.').toDoubleOrNull()
                    val minimum = minSpend.replace(',', '.').toDoubleOrNull()
                    val limit = maxUses.toIntOrNull()
                    val duration = days.toLongOrNull()
                    if (!code.matches(Regex("[A-Z0-9][A-Z0-9-]{3,23}")) ||
                        value == null || value <= 0 || (kind == "percent" && value > 100) ||
                        minimum == null || minimum < 0 || limit == null || limit !in 1..100000 ||
                        duration == null || duration !in 1..366) {
                        status = "Controleer code, korting, looptijd en limiet."
                    } else {
                        busy = true
                        scope.launch {
                            try {
                                val now = OffsetDateTime.now()
                                val payload = JSONObject().put("business_id", businessId).put("code", code)
                                    .put("title", title).put("discount_type", kind).put("discount_value", value)
                                    .put("min_spend", minimum).put("starts_at", now.toString())
                                    .put("ends_at", now.plusDays(duration).toString()).put("max_uses", limit)
                                    .put("active", active)
                                Account.rpc("pasr_business_promo_save", JSONObject().put("p_promo", payload))
                                status = "Actiecode opgeslagen."; code = ""; title = ""
                                reload()
                            } catch (e: Exception) { status = e.message ?: "Opslaan mislukt." }
                            busy = false
                        }
                    }
                }) { Text("Actiecode opslaan") }
                Text("Bestaande actiecodes")
                rows.forEach { row ->
                    Text(row.optString("code") + " · " + row.optString("title") +
                        " · " + row.optInt("used_count") + "/" + row.optInt("max_uses") +
                        if (row.optBoolean("active")) " · Actief" else " · Uit")
                }
                OutlinedTextField(verify, { verify = it.uppercase(); verified = false },
                    label = { Text("Actiecode controleren / gebruiken") }, modifier = Modifier.fillMaxWidth())
                Button(enabled = !busy && verify.length >= 4, onClick = {
                    busy = true
                    scope.launch {
                        try {
                            val result = Account.rpc("pasr_business_promo_check",
                                JSONObject().put("p_code", verify.trim())) as? JSONObject
                            verified = result?.optBoolean("valid", false) == true
                            status = if (verified) "Geldige actie: " + result?.optString("title") else "Code niet geldig of opgebruikt."
                        } catch (e: Exception) { verified = false; status = e.message ?: "Controleren mislukt." }
                        busy = false
                    }
                }) { Text("Controleer") }
                Button(enabled = verified && !busy, onClick = {
                    busy = true
                    scope.launch {
                        try {
                            Account.rpc("pasr_business_promo_redeem", JSONObject().put("p_code", verify.trim()))
                            status = "Gebruik geregistreerd."; verified = false; verify = ""; reload()
                        } catch (e: Exception) { verified = false; status = e.message ?: "Verzilveren mislukt." }
                        busy = false
                    }
                }) { Text("Eén keer gebruiken") }
                Text("Registreer gebruik pas nadat je de korting bij de kassa hebt toegepast.")
                if (status.isNotBlank()) Text(status)
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text("Sluiten") } },
    )
}
