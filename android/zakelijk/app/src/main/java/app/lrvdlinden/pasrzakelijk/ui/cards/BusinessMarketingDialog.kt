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
import app.lrvdlinden.pasrzakelijk.data.Business
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate

/** Dezelfde campagne-RPC's en invoervelden als de iOS marketingkalender. */
@Composable
fun BusinessMarketingDialog(business: Business, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    var title by remember { mutableStateOf("") }
    var details by remember { mutableStateOf("") }
    var cardID by remember { mutableStateOf("") }
    var start by remember { mutableStateOf(LocalDate.now().toString()) }
    var end by remember { mutableStateOf(LocalDate.now().plusDays(7).toString()) }
    var channel by remember { mutableStateOf("social") }
    var status by remember { mutableStateOf("planned") }
    var events by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }

    suspend fun reload() {
        try {
            val r = Account.rpc("pasr_business_marketing_list",
                JSONObject().put("p_business", business.id)) as? JSONArray
            events = (0 until (r?.length() ?: 0)).mapNotNull { r?.optJSONObject(it) }
        } catch (e: Exception) { message = e.message ?: "Kan campagnes niet ophalen." }
    }
    LaunchedEffect(business.id) { reload() }

    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("Marketingkalender") },
        text = {
            Column(Modifier.fillMaxWidth().heightIn(max = 630.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Campagne plannen")
                OutlinedTextField(title, { title = it }, label = { Text("Naam van de actie") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(details, { details = it }, label = { Text("Omschrijving") }, modifier = Modifier.fillMaxWidth())
                Text("Kies een kaart (of algemene actie)")
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(onClick = { cardID = "" }) { Text(if (cardID.isEmpty()) "✓ Algemeen" else "Algemeen") }
                }
                business.cards.forEach { card ->
                    TextButton(onClick = { cardID = card.id }) {
                        Text((if (cardID == card.id) "✓ " else "") + card.name)
                    }
                }
                OutlinedTextField(start, { start = it }, label = { Text("Begin (JJJJ-MM-DD)") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(end, { end = it }, label = { Text("Einde (JJJJ-MM-DD)") }, modifier = Modifier.fillMaxWidth())
                Text("Kanaal")
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    listOf("social", "winkel", "web", "email").forEach { value ->
                        TextButton(onClick = { channel = value }) { Text((if (channel == value) "✓ " else "") + value) }
                    }
                }
                Text("Status")
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    listOf("draft", "planned", "completed").forEach { value ->
                        TextButton(onClick = { status = value }) { Text((if (status == value) "✓ " else "") + value) }
                    }
                }
                Button(enabled = !busy && title.trim().length >= 3, onClick = {
                    val from = runCatching { LocalDate.parse(start) }.getOrNull()
                    val to = runCatching { LocalDate.parse(end) }.getOrNull()
                    if (from == null || to == null || to.isBefore(from) || to.isAfter(from.plusDays(366)) ||
                        title.trim().length !in 3..100 || details.length > 600) {
                        message = "Controleer datums, titel en omschrijving."; return@Button
                    }
                    busy = true
                    scope.launch {
                        try {
                            val payload = JSONObject().put("business_id", business.id)
                                .put("card_id", cardID.ifEmpty { JSONObject.NULL })
                                .put("title", title.trim()).put("details", details)
                                .put("starts_on", start).put("ends_on", end)
                                .put("channel", channel).put("status", status)
                            Account.rpc("pasr_business_marketing_save", JSONObject().put("p_event", payload))
                            title = ""; details = ""; message = "Campagne opgeslagen."
                            reload()
                        } catch (e: Exception) { message = e.message ?: "Opslaan mislukt." }
                        busy = false
                    }
                }) { Text(if (busy) "Opslaan…" else "Campagne opslaan") }
                Text("Campagnes worden gepland. Zonder toestemming worden geen automatische berichten verzonden.")
                Text("Mijn campagnes")
                if (busy && events.isEmpty()) CircularProgressIndicator()
                events.forEach { event ->
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(event.optString("title"))
                        Text(event.optString("starts_on") + " – " + event.optString("ends_on") +
                            " · " + event.optString("channel") + " · " + event.optString("status"))
                        if (event.optString("details").isNotEmpty()) Text(event.optString("details"))
                        TextButton(enabled = !busy, onClick = {
                            busy = true
                            scope.launch {
                                try {
                                    Account.rpc("pasr_business_marketing_delete",
                                        JSONObject().put("p_event", event.optString("id")))
                                    reload()
                                    message = "Campagne verwijderd."
                                } catch (e: Exception) { message = e.message ?: "Verwijderen mislukt." }
                                busy = false
                            }
                        }) { Text("Verwijderen") }
                    }
                }
                if (message.isNotEmpty()) Text(message)
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text("Sluiten") } }
    )
}
