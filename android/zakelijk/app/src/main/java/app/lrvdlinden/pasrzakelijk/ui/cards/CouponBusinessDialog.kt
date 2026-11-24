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

/** Kortingsbonnen aanmaken en verzilveren, direct met de ondernemerrechten uit de accountsession. */
@Composable
fun CouponBusinessDialog(businessId: String, initialCode: String = "", onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    var title by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var type by remember { mutableStateOf("amount") }
    var value by remember { mutableStateOf("2.50") }
    var minSpend by remember { mutableStateOf("10") }
    var code by remember(initialCode) { mutableStateOf(initialCode) }
    var couponVerified by remember(initialCode) { mutableStateOf(false) }
    var published by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var processing by remember { mutableStateOf(false) }
    var coupons by remember { mutableStateOf<List<JSONObject>>(emptyList()) }

    suspend fun load() {
        try {
            val result = Account.rpc("pasr_business_coupon_list",
                JSONObject().put("p_business", businessId)) as? JSONArray
            coupons = (0 until (result?.length() ?: 0)).mapNotNull { result?.optJSONObject(it) }
        } catch (e: Exception) { message = e.message ?: "Kan bonnen niet laden." }
    }
    LaunchedEffect(businessId) { load() }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("Kortingsbonnen") },
        text = {
            Column(Modifier.fillMaxWidth().heightIn(max = 580.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Een nieuwe actie aanmaken")
                OutlinedTextField(title, { title = it }, label = { Text("Naam kortingsbon") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(description, { description = it }, label = { Text("Voorwaarden") }, modifier = Modifier.fillMaxWidth())
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton({ type = "amount" }) { Text(if (type == "amount") "✓ €" else "€") }
                    TextButton({ type = "percent" }) { Text(if (type == "percent") "✓ %" else "%") }
                }
                OutlinedTextField(value, { value = it }, label = { Text(if (type == "amount") "Kortingsbedrag €" else "Percentage") },
                    modifier = Modifier.fillMaxWidth())
                OutlinedTextField(minSpend, { minSpend = it }, label = { Text("Minimale besteding €") },
                    modifier = Modifier.fillMaxWidth())
                Row {
                    Text("Publiceer in Pasr", modifier = Modifier.weight(1f))
                    Checkbox(published, onCheckedChange = { published = it })
                }
                Button(enabled = !processing && title.length >= 3, onClick = {
                    val amount = value.replace(',', '.').toDoubleOrNull()
                    val minimum = minSpend.replace(',', '.').toDoubleOrNull()
                    if (amount == null || amount <= 0 || minimum == null || minimum < 0) {
                        message = "Controleer de bedragen."; return@Button
                    }
                    processing = true
                    scope.launch {
                        try {
                            val now = OffsetDateTime.now()
                            val payload = JSONObject()
                                .put("business_id", businessId).put("title", title.trim())
                                .put("description", description.trim())
                                .put("discount_type", type).put("discount_value", amount).put("min_spend", minimum)
                                .put("starts_at", now.toString()).put("ends_at", now.plusDays(30).toString())
                                .put("max_claims", 500).put("one_per_customer", true).put("public", published)
                            Account.rpc("pasr_business_coupon_save", JSONObject().put("p_coupon", payload))
                            title = ""; description = ""; message = "Kortingsbon opgeslagen."
                            load()
                        } catch (e: Exception) { message = e.message ?: "Opslaan mislukt." }
                        processing = false
                    }
                }) { Text("Kortingsbon aanmaken (30 dagen)") }
                Text("Bestaande kortingsbonnen")
                coupons.forEach { c ->
                    Text(c.optString("title") + " · " + c.optInt("claimed") +
                        " bewaard · " + c.optInt("redeemed") + " ingewisseld")
                }
                Text("Code van klant verzilveren")
                OutlinedTextField(code, { code = it; couponVerified = false }, label = { Text("PC-code") },
                    modifier = Modifier.fillMaxWidth())
                Button(enabled = code.trim().uppercase().startsWith("PC") && !processing && !couponVerified, onClick = {
                    processing = true
                    scope.launch {
                        try {
                            val result = Account.rpc("pasr_business_coupon_check",
                                JSONObject().put("p_code", code.trim().uppercase())) as? JSONObject
                            couponVerified = result?.optBoolean("valid", false) == true
                            message = if (couponVerified) {
                                "Geldige bon: " + result.optString("title") + ". Controleer de korting aan de kassa."
                            } else "Deze kortingsbon is ongeldig, verlopen of al gebruikt."
                        } catch (e: Exception) { couponVerified = false; message = e.message ?: "Bon niet geldig." }
                        processing = false
                    }
                }) { Text("Controleer kortingsbon") }
                if (couponVerified) {
                    Button(enabled = !processing, onClick = {
                        processing = true
                        scope.launch {
                            try {
                                val result = Account.rpc("pasr_business_coupon_redeem",
                                    JSONObject().put("p_code", code.trim().uppercase())) as? JSONObject
                                message = "Bon verzilverd: " + (result?.optString("title") ?: "")
                                code = ""
                                couponVerified = false
                                load()
                            } catch (e: Exception) {
                                couponVerified = false
                                message = e.message ?: "Bon kon niet worden verzilverd."
                            }
                            processing = false
                        }
                    }) { Text("Korting gegeven · bon definitief verzilveren") }
                }
                if (message.isNotBlank()) Text(message)
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text("Sluiten") } }
    )
}
