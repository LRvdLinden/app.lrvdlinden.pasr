package app.lrvdlinden.pasr.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.TextButton
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.outlined.ConfirmationNumber
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasr.data.Account
import app.lrvdlinden.pasr.data.Api
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
import org.json.JSONArray
import org.json.JSONObject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Eigen Pasr-scherm: de bon wordt pas uitgegeven na een server-side claim voor het account. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CouponsScreen() {
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    var available by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var mine by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var openCode by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(true) }

    var marked by remember { mutableStateOf<Set<String>>(emptySet()) }
    var removing by remember { mutableStateOf(false) }
    val used = mine.filter { it.optBoolean("redeemed") }

    suspend fun refresh(background: Boolean = false) {
        if (removing) return
        if (!background) busy = true
        try {
            val publicCoupons = (Api.publicRpc("pasr_business_coupon_list", JSONObject()) as? JSONArray)
                ?.let { j -> (0 until j.length()).mapNotNull(j::optJSONObject) } ?: emptyList()
            val publicCodes = (Api.publicRpc("pasr_business_promo_public", JSONObject()) as? JSONArray)
                ?.let { j -> (0 until j.length()).mapNotNull(j::optJSONObject)?.onEach { it.put("kind", "code") } }
                ?: emptyList()
            available = publicCoupons + publicCodes
            mine = if (Account.isSignedIn) {
                val coupons = (Api.rpc("pasr_business_coupon_mine", JSONObject()) as? JSONArray)
                    ?.let { j -> (0 until j.length()).mapNotNull(j::optJSONObject) } ?: emptyList()
                val promos = (Api.rpc("pasr_business_promo_mine", JSONObject()) as? JSONArray)
                    ?.let { j -> (0 until j.length()).mapNotNull(j::optJSONObject)?.onEach { it.put("kind", "code") } }
                    ?: emptyList()
                coupons + promos
            } else emptyList()
            marked = marked.intersect(mine.filter { it.optBoolean("redeemed") }.map { it.optString("id") }.toSet())
            if (mine.none { !it.isNull("code") && it.optString("code") == openCode }) openCode = null
            if (!background) error = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!background) error = e.message ?: "De kortingsbonnen konden niet worden geladen."
        } finally { if (!background) busy = false }
    }

    fun remove(items: List<JSONObject>) {
        if (removing || items.isEmpty()) return
        removing = true
        scope.launch {
            try {
                val payload = JSONArray(items.map {
                    JSONObject().put("id", it.optString("id"))
                        .put("kind", if (it.optString("kind") == "code") "code" else "coupon")
                })
                Api.rpc("pasr_customer_hide_used_offers", JSONObject().put("p_items", payload))
                val ids = items.map { it.optString("id") }.toSet()
                mine = mine.filterNot { it.optString("id") in ids }
                marked = marked - ids
                error = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) { error = e.message ?: "Verwijderen mislukt." }
            finally { removing = false }
        }
    }

    LaunchedEffect(Unit) {
        refresh()
        while (true) {
            delay(30_000)
            if (!busy) refresh(background = true)
        }
    }

    Scaffold(topBar = {
        TopAppBar(title = { Text("Kortingsbonnen", fontWeight = FontWeight.Bold) },
            navigationIcon = { IconButton(onClick = { nav.pop() }) { Icon(Icons.Filled.ArrowBack, "Terug") } })
    }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                Text("Kortingsbonnen van deelnemende ondernemers in Pasr.",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(vertical = 10.dp))
                if (busy) CircularProgressIndicator()
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                if (!Account.isSignedIn)
                    Text("Log in bij je Pasr-account om een persoonlijke kortingsbon te bewaren.",
                        color = MaterialTheme.colorScheme.primary)
            }
            if (openCode != null) {
                item {
                    Card {
                        Column(Modifier.fillMaxWidth().padding(18.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text("Jouw unieke kortingsbon", style = MaterialTheme.typography.titleMedium)
                            val bitmap = remember(openCode) { openCode?.let(::couponQR) }
                            bitmap?.let {
                                Image(it.asImageBitmap(), "Scanbare QR-code voor de ondernemer",
                                    modifier = Modifier.size(250.dp).background(Color.White).padding(12.dp))
                            }
                            Text(openCode!!, fontWeight = FontWeight.Bold)
                            Text("Laat de ondernemer de code scannen. Alleen de ondernemer kan deze bon verzilveren.")
                            Button(onClick = { openCode = null }) { Text("Sluiten") }
                        }
                    }
                }
            }
            if (mine.isNotEmpty()) {
                item {
                    Text("Mijn kortingsbonnen", style = MaterialTheme.typography.titleLarge)
                    if (used.isNotEmpty()) TextButton(onClick = { marked = used.map { it.optString("id") }.toSet() }) {
                        Text("Alle gebruikte selecteren")
                    }
                    if (marked.isNotEmpty()) TextButton(
                        enabled = !removing,
                        onClick = { remove(used.filter { it.optString("id") in marked }) },
                    ) { Text("Selectie verwijderen", color = MaterialTheme.colorScheme.error) }
                }
                items(mine, key = { "saved-" + it.optString("id") }) { x ->
                    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        PasrOfferCard(x, saved = true)
                        if (x.optBoolean("redeemed")) {
                            Text("PASR · GEBRUIKT · Niet opnieuw te gebruiken")
                            val id = x.optString("id")
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Checkbox(id in marked, onCheckedChange = { checked ->
                                    marked = if (checked) marked + id else marked - id
                                })
                                Text("Selecteer " + x.optString("title"), Modifier.weight(1f))
                                TextButton(enabled = !removing, onClick = { remove(listOf(x)) }) {
                                    Text("Verwijderen", color = MaterialTheme.colorScheme.error)
                                }
                            }
                        } else if (x.optBoolean("disabled") || x.isNull("code") || x.optString("code").isBlank()) {
                            Text("Deze aanbieding is niet meer geldig.")
                        } else Button(onClick = { openCode = x.optString("code") }) {
                            Text("Toon persoonlijke QR-code")
                        }
                    }
                }
            }
            item { Text("Aanbiedingen", style = MaterialTheme.typography.titleLarge) }
            items(available, key = { it.optString("id") }) { c ->
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    PasrOfferCard(c, saved = false)
                    if (c.optString("description").isNotBlank()) Text(c.optString("description"))
                    Button(onClick = {
                        if (!Account.isSignedIn) {
                            nav.push(Screen.AccountScreen)
                        } else scope.launch {
                            try {
                                val promo = c.optString("kind") == "code"
                                val v = Api.rpc(if (promo) "pasr_business_promo_claim"
                                    else "pasr_business_coupon_claim",
                                    JSONObject().put(if (promo) "p_promo" else "p_coupon", c.optString("id")))
                                    as? JSONObject
                                openCode = v?.optString("code")?.takeIf { it.isNotBlank() && it != "null" }
                                refresh()
                            } catch (e: Exception) { error = e.message }
                        }
                    }) { Text(if (!Account.isSignedIn) "Log in om te bewaren"
                             else if (c.optString("kind") == "code") "Bewaar actiecode in Pasr"
                             else "Bewaar kortingsbon") }
                }
            }
            if (!busy && available.isEmpty()) item {
                Text("Er zijn momenteel geen beschikbare kortingsbonnen.")
            }
        }
    }
}

private fun couponQR(text: String): Bitmap? = runCatching {
    val matrix = MultiFormatWriter().encode(text, BarcodeFormat.QR_CODE, 300, 300)
    Bitmap.createBitmap(300, 300, Bitmap.Config.ARGB_8888).apply {
        for (y in 0 until 300) for (x in 0 until 300)
            setPixel(x, y, if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
    }
}.getOrNull()
