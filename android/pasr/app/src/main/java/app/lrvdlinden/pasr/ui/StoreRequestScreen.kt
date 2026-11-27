package app.lrvdlinden.pasr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasr.data.Account
import app.lrvdlinden.pasr.data.Api
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * "Mis je een winkel?" in de app, zoals op de iPhone: naam, website en een opmerking naar het beheer
 * (pasr_store_request), met de status van je eigen aanvragen (pasr_my_store_requests). Kan met een Pasr-account,
 * zodat de melding "toegevoegd" bij jou terechtkomt.
 */
@Composable
fun StoreRequestScreen() {
    val nav = LocalNav.current
    val session by Account.session.collectAsState()
    val scope = rememberCoroutineScope()
    var voucher by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var website by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val mine = remember { mutableStateListOf<Pair<String, String>>() }

    suspend fun loadMine() {
        if (session == null) return
        val rows = runCatching { Api.rpc("pasr_my_store_requests", JSONObject()) as? JSONArray }.getOrNull() ?: return
        mine.clear()
        for (i in 0 until minOf(rows.length(), 20)) {
            val r = rows.optJSONObject(i) ?: continue
            mine += r.optString("name") to r.optString("status", "open")
        }
    }
    LaunchedEffect(session) { loadMine() }

    SimpleScaffold("Mis je een winkel?") {
        if (session == null) {
            Text("Een winkel aanvragen kan met een gratis Pasr-account, zodat de melding bij jou terechtkomt.",
                Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button({ nav.push(Screen.AccountScreen) }, Modifier.padding(horizontal = 16.dp).fillMaxWidth()) { Text("Inloggen of account maken") }
            return@SimpleScaffold
        }
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(!voucher, { voucher = false }, { Text("Klantenkaart") })
                FilterChip(voucher, { voucher = true }, { Text("Cadeaukaart of voucher") })
            }
            OutlinedTextField(name, { name = it.take(80) }, Modifier.fillMaxWidth(), singleLine = true,
                label = { Text(if (voucher) "Naam van de cadeaukaart, bijv. VVV" else "Naam van de winkel") })
            OutlinedTextField(website, { website = it.take(120) }, Modifier.fillMaxWidth(), singleLine = true,
                label = { Text("Website, bijv. winkel.nl") })
            OutlinedTextField(note, { note = it.take(300) }, Modifier.fillMaxWidth(), maxLines = 3,
                label = { Text("Opmerking (optioneel)") })
            Text("Met de website vinden we het logo en de kleuren. Ook cadeaukaarten en vouchers kun je aanvragen.",
                color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
            Button({
                busy = true; message = null
                scope.launch {
                    val ok = runCatching {
                        Api.rpc("pasr_store_request", JSONObject().put("p_name", name.trim()).put("p_website", website.trim())
                            .put("p_note", note.trim()).put("p_kind", if (voucher) "voucher" else "loyalty"))
                    }
                    busy = false
                    message = if (ok.isSuccess) { name = ""; website = ""; note = ""; loadMine()
                        "Aangevraagd. Je krijgt bericht zodra de winkel in Pasr staat." }
                        else "Versturen lukte niet: " + (ok.exceptionOrNull()?.message ?: "probeer het later opnieuw")
                }
            }, Modifier.fillMaxWidth(), enabled = !busy && name.trim().length >= 2) { Text("Aanvragen") }
            message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
            if (mine.isNotEmpty()) {
                SectionHeader("Je aanvragen")
                mine.forEach { (n, s) ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                        Text(n, Modifier.weight(1f))
                        Text(when (s) { "added" -> "Toegevoegd"; "rejected" -> "Niet toegevoegd"; else -> "Aangevraagd" },
                            color = if (s == "added") MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}
