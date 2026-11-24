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
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasrzakelijk.data.Account
import app.lrvdlinden.pasrzakelijk.data.Business
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/** Zelfde vestigings-RPC's en velden als Pasr Zakelijk iOS. */
@Composable
fun BusinessLocationsDialog(business: Business, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    var locations by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var counts by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var name by remember { mutableStateOf("") }
    var address by remember { mutableStateOf("") }
    var active by remember { mutableStateOf(true) }
    var selectedID by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }

    fun clear() { selectedID = null; name = ""; address = ""; active = true }
    suspend fun reload() {
        try {
            val response = Account.rpc("pasr_business_locations_list",
                JSONObject().put("p_business", business.id)) as? JSONArray
            locations = (0 until (response?.length() ?: 0)).mapNotNull { response?.optJSONObject(it) }
            val data = Account.rpc("pasr_business_location_insights",
                JSONObject().put("p_business", business.id)) as? JSONArray
            counts = (0 until (data?.length() ?: 0)).mapNotNull { i ->
                data?.optJSONObject(i)?.let { it.optString("id") to it.optInt("stamps_30d") }
            }.toMap()
        } catch (e: Exception) { message = e.message ?: "Kon vestigingen niet ophalen." }
    }
    LaunchedEffect(business.id) { reload() }

    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("Vestigingen") },
        text = {
            Column(Modifier.fillMaxWidth().heightIn(max = 630.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(if (selectedID == null) "Nieuwe vestiging" else "Vestiging bewerken")
                OutlinedTextField(name, { name = it }, label = { Text("Naam vestiging") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(address, { address = it }, label = { Text("Adres") }, modifier = Modifier.fillMaxWidth())
                Row { Text("Actief", modifier = Modifier.weight(1f)); Checkbox(active, { active = it }) }
                Button(enabled = !busy && name.trim().length >= 2, onClick = {
                    if (name.trim().length !in 2..100 || address.length > 200) {
                        message = "Controleer naam en adres."; return@Button
                    }
                    busy = true
                    scope.launch {
                        try {
                            val payload = JSONObject().put("p_business", business.id)
                                .put("p_name", name.trim()).put("p_address", address.trim())
                                .put("p_id", selectedID ?: JSONObject.NULL).put("p_active", active)
                            Account.rpc("pasr_business_location_save", payload)
                            clear()
                            message = "Vestiging opgeslagen."
                            reload()
                        } catch (e: Exception) { message = e.message ?: "Opslaan mislukt." }
                        busy = false
                    }
                }) { Text(if (selectedID == null) "Vestiging toevoegen" else "Wijzigingen opslaan") }
                if (selectedID != null) OutlinedButton(onClick = { clear() }) { Text("Bewerken annuleren") }
                Text("Mijn vestigingen")
                if (locations.isEmpty()) Text("Nog geen vestigingen.")
                locations.forEach { location ->
                    TextButton(onClick = {
                        selectedID = location.optString("id")
                        name = location.optString("name")
                        address = location.optString("address")
                        active = location.optBoolean("active", true)
                    }) {
                        Column {
                            Text(location.optString("name") +
                                if (location.optBoolean("active", true)) " · Actief" else " · Inactief")
                            if (location.optString("address").isNotEmpty()) Text(location.optString("address"))
                            Text("Stempels (30 dagen): " + (counts[location.optString("id")] ?: 0))
                        }
                    }
                }
                if (message.isNotEmpty()) Text(message)
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text("Sluiten") } }
    )
}
