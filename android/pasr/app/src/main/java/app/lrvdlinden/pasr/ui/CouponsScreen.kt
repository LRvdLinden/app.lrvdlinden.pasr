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

    suspend fun refresh() {
        busy = true
        try {
            available = (Api.publicRpc("pasr_business_coupon_list", JSONObject()) as? JSONArray)
                ?.let { j -> (0 until j.length()).mapNotNull(j::optJSONObject) } ?: emptyList()
            mine = if (Account.isSignedIn)
                (Api.rpc("pasr_business_coupon_mine", JSONObject()) as? JSONArray)
                    ?.let { j -> (0 until j.length()).mapNotNull(j::optJSONObject) } ?: emptyList()
                else emptyList()
            error = null
        } catch (e: Exception) {
            error = e.message ?: "De kortingsbonnen konden niet worden geladen."
        }
        busy = false
    }

    LaunchedEffect(Unit) { refresh() }

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
                item { Text("Mijn kortingsbonnen", style = MaterialTheme.typography.titleLarge) }
                items(mine, key = { "saved-" + it.optString("id") }) { x ->
                    Card {
                        Row(Modifier.fillMaxWidth().padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Outlined.ConfirmationNumber, null)
                            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                                Text(x.optString("title"), fontWeight = FontWeight.Bold)
                                Text(x.optString("business"))
                            }
                            Button(onClick = { openCode = x.optString("code") },
                                enabled = !x.optBoolean("redeemed")) {
                                Text(if (x.optBoolean("redeemed")) "Gebruikt" else "Toon")
                            }
                        }
                    }
                }
            }
            item { Text("Aanbiedingen", style = MaterialTheme.typography.titleLarge) }
            items(available, key = { it.optString("id") }) { c ->
                Card {
                    Column(Modifier.fillMaxWidth().padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(c.optString("business"), style = MaterialTheme.typography.titleSmall)
                        val value = c.optDouble("discount_value")
                        val amount = if (c.optString("discount_type") == "percent")
                            value.toInt().toString() + "% korting"
                            else "€ " + "%.2f".format(java.util.Locale.forLanguageTag("nl-NL"), value) + " korting"
                        Text(amount, style = MaterialTheme.typography.headlineMedium,
                            color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                        Text(c.optString("title"), fontWeight = FontWeight.Bold)
                        Text(c.optString("description"))
                        Button(onClick = {
                            if (!Account.isSignedIn) {
                                nav.push(Screen.AccountScreen)
                            } else scope.launch {
                                try {
                                    val v = Api.rpc("pasr_business_coupon_claim",
                                        JSONObject().put("p_coupon", c.optString("id"))) as? JSONObject
                                    openCode = v?.optString("code")
                                    refresh()
                                } catch (e: Exception) { error = e.message }
                            }
                        }) { Text(if (Account.isSignedIn) "Bewaar kortingsbon" else "Log in om te bewaren") }
                    }
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
