package app.lrvdlinden.pasr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasr.data.CardKind
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.Account
import app.lrvdlinden.pasr.data.Api
import org.json.JSONArray
import org.json.JSONObject
import java.text.NumberFormat
import java.text.DateFormat
import java.util.Date
import java.util.Locale

/** Eigen Pasr-voordelenoverzicht met bekende, door de klant bijgehouden bedragen.
 * Saldi worden niet bij uitgevers uitgelezen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BenefitsScreen() {
    val nav = LocalNav.current
    val all by CardStore.cards.collectAsState()
    var community by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    LaunchedEffect(Unit) {
        if (Account.isSignedIn) {
            community = runCatching {
                val json = Api.rpc("pasr_business_community_progress", JSONObject()) as? JSONArray
                (0 until (json?.length() ?: 0)).mapNotNull { json?.optJSONObject(it) }
            }.getOrDefault(emptyList())
        }
    }
    val vouchers = all.filter { it.deletedAt == null && it.kind == CardKind.VOUCHER }
    val total = vouchers.filter { it.currencyCode == null || it.currencyCode.equals("EUR", true) }
        .sumOf { it.balance ?: 0.0 }
    val dated = all.filter {
        it.deletedAt == null && it.expiresAt != null &&
            it.kind in listOf(CardKind.VOUCHER, CardKind.SUBSCRIPTION, CardKind.CODE) &&
            it.expiresAt < System.currentTimeMillis() + 45L * 24 * 60 * 60 * 1000
    }.sortedBy { it.expiresAt }
    val euro = NumberFormat.getCurrencyInstance(Locale.forLanguageTag("nl-NL"))
    Scaffold(topBar = {
        TopAppBar(title = { Text("Mijn voordelen", fontWeight = FontWeight.Bold) },
            navigationIcon = { IconButton(onClick = nav::pop) { Icon(Icons.Filled.ArrowBack, "Terug") } })
    }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                Card(Modifier.fillMaxWidth().padding(top = 12.dp)) {
                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Totaal cadeaukaarttegoed", style = MaterialTheme.typography.titleMedium)
                        Text(euro.format(total), style = MaterialTheme.typography.headlineLarge,
                            fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.primary)
                        Text("Op basis van de bedragen die je zelf in Pasr bijhoudt. Niet live gecontroleerd bij de uitgevers.",
                            style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
            item { Text("Cadeaukaarten", style = MaterialTheme.typography.titleLarge) }
            if (vouchers.isEmpty()) item { Text("Nog geen cadeaukaarten.") }
            items(vouchers, key = { it.id }) { card ->
                Card {
                    Row(Modifier.fillMaxWidth().padding(16.dp),
                        horizontalArrangement = Arrangement.SpaceBetween) {
                        Column(Modifier.weight(1f)) {
                            Text(card.storeName, fontWeight = FontWeight.Bold)
                            Text(card.expiresAt?.let { "Geldig tot " + DateFormat.getDateInstance().format(Date(it)) } ?: "Geen vervaldatum",
                                style = MaterialTheme.typography.bodySmall)
                        }
                        Text(card.balance?.let { euro.format(it) } ?: "Saldo onbekend")
                    }
                }
            }
            if (community.isNotEmpty()) {
                item { Text("Gezamenlijke winkelstraatacties", style = MaterialTheme.typography.titleLarge) }
                items(community, key = { "community-" + it.optString("id") }) { campaign ->
                    val visited = campaign.optInt("visited")
                    val needed = campaign.optInt("required").coerceAtLeast(1)
                    Card {
                        Column(Modifier.fillMaxWidth().padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(campaign.optString("name"), fontWeight = FontWeight.Bold)
                            Text("Bezocht: $visited van $needed verschillende winkels")
                            androidx.compose.material3.LinearProgressIndicator(
                                progress = { (visited.toFloat() / needed).coerceIn(0f, 1f) },
                                modifier = Modifier.fillMaxWidth())
                            Text("Beloning: " + campaign.optString("reward"))
                            campaign.optJSONArray("businesses")?.takeIf { it.length() > 0 }?.let { list ->
                                Text("Doen mee: " + (0 until list.length()).mapNotNull { list.optJSONObject(it) }
                                    .joinToString(", ") { (if (it.optBoolean("visited")) "✓ " else "") + it.optString("name") })
                            }
                            runCatching {
                                java.time.OffsetDateTime.parse(campaign.optString("ends_at")).format(
                                    java.time.format.DateTimeFormatter.ofPattern("d MMMM yyyy", java.util.Locale.forLanguageTag("nl-NL")))
                            }.getOrNull()?.let { Text("Loopt tot $it") }
                            if (campaign.optBoolean("claimed")) Text("✓ Beloning al uitgegeven")
                            else if (visited >= needed) Text(
                                "Beloning beschikbaar. Laat je lidcode bij een deelnemende zaak scannen.",
                                color = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
            item { Text("Verloopt binnenkort", style = MaterialTheme.typography.titleLarge) }
            if (dated.isEmpty()) item { Text("Geen kaarten of lidmaatschappen die binnen 45 dagen verlopen.") }
            items(dated, key = { "expires-" + it.id }) { card ->
                Card {
                    Row(Modifier.fillMaxWidth().padding(16.dp),
                        horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(card.storeName, fontWeight = FontWeight.SemiBold)
                        Text(card.expiresAt?.let { DateFormat.getDateInstance().format(Date(it)) } ?: "",
                            color = MaterialTheme.colorScheme.primary)
                    }
                }
            }
        }
    }
}
