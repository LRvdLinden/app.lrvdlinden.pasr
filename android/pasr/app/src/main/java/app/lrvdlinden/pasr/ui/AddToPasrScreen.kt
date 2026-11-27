package app.lrvdlinden.pasr.ui

import android.net.Uri
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasr.R
import app.lrvdlinden.pasr.data.Account
import app.lrvdlinden.pasr.data.Api
import app.lrvdlinden.pasr.data.Business
import app.lrvdlinden.pasr.data.BusinessInfo
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.CardDetails
import app.lrvdlinden.pasr.data.CardKind
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.Catalog
import app.lrvdlinden.pasr.data.PasrError
import app.lrvdlinden.pasr.data.StoreTemplate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * "Voeg toe aan Pasr": https://pasr.nl/add/<soort>/<id> (App Link) of pasr://add/<soort>/<id> (terugvalpagina).
 * k = stempelkaart van een zaak, c = kortingsbon, a = actiecode (uuid), t = ticket, g = cadeaukaart, s = winkelkaart
 * (id uit de catalogus), e = aanmelden voor een event, m = klantenkaart van een zaak, t/<uuid>?c=<code> = ticket koppelen.
 * Zelfde gedrag als AddToPasrSheet op iOS.
 */
data class AddLink(val kind: Char, val id: String, val code: String? = null) {
    val isOffer get() = kind == 'c' || kind == 'a'
    /** Ticket van een zaak koppelen (/add/t/<ticket-uuid>?c=<code>) in plaats van een ticket uit de catalogus. */
    val isTicketClaim get() = kind == 't' && code != null && UUID.matches(id)
    val isCatalog get() = (kind == 't' && !isTicketClaim) || kind == 'g' || kind == 's'

    companion object {
        private val ID = Regex("^[A-Za-z0-9][A-Za-z0-9-]{0,63}$")
        private val UUID = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

        fun parse(uri: Uri): AddLink? {
            val host = uri.host?.lowercase() ?: return null
            var parts = uri.pathSegments.filter { it.isNotEmpty() }
            when {
                uri.scheme == "https" && (host == "pasr.nl" || host == "www.pasr.nl") -> {
                    if (parts.firstOrNull() != "add") return null
                    parts = parts.drop(1)
                }
                uri.scheme == "pasr" && host == "add" -> Unit
                else -> return null
            }
            if (parts.size != 2 || parts[0].length != 1 || parts[0][0] !in "kcatgsem" || !ID.matches(parts[1])) return null
            val kind = parts[0][0]
            // e = aanmelden voor een event van een zaak, m = klantenkaart met barcode van een zaak (sinds versionCode 141)
            if (kind in "kcaem") return if (UUID.matches(parts[1])) AddLink(kind, parts[1].lowercase()) else null
            if (kind == 't' && UUID.matches(parts[1])) {
                val code = runCatching { uri.getQueryParameter("c") ?: uri.getQueryParameter("code") }.getOrNull()?.trim()
                if (code != null && Regex("^[A-Za-z0-9-]{8,80}$").matches(code)) return AddLink(kind, parts[1].lowercase(), code)
            }
            return AddLink(kind, parts[1])
        }
    }
}

@Composable
private fun kindTitle(kind: Char) = stringResource(
    when (kind) {
        'k' -> R.string.add_kind_stamps
        'c' -> R.string.add_kind_coupon
        'a' -> R.string.add_kind_promo
        't' -> R.string.add_kind_ticket
        'g' -> R.string.add_kind_gift
        else -> R.string.add_kind_store
    }
)

@Composable
fun AddToPasrScreen(link: AddLink) {
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    var loading by remember { mutableStateOf(true) }
    var missing by remember { mutableStateOf<Int?>(null) }
    var added by remember { mutableStateOf(false) }
    var addedCardId by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var business by remember { mutableStateOf<BusinessInfo?>(null) }
    var offer by remember { mutableStateOf<JSONObject?>(null) }
    var offerSaved by remember { mutableStateOf(false) }
    var template by remember { mutableStateOf<StoreTemplate?>(null) }
    val cards by CardStore.cards.collectAsState()
    val existingStamp = if (link.kind == 'k') cards.firstOrNull { it.deletedAt == null && it.details.businessCardId.equals(link.id, true) } else null
    val existingStore = template?.let { t -> cards.filter { it.deletedAt == null && it.templateID.equals(t.id, true) } } ?: emptyList()
    val genericError = stringResource(R.string.add_error_generic)

    LaunchedEffect(link) {
        try {
            when {
                link.kind == 'k' -> {
                    business = Business.preview(link.id)
                    if (existingStamp == null && business?.active != true) missing = R.string.add_missing_stamps
                }
                link.isOffer -> {
                    val promo = link.kind == 'a'
                    val rows = Api.publicRpc(if (promo) "pasr_business_promo_public" else "pasr_business_coupon_list", JSONObject()) as? JSONArray
                    val match = rows?.let { r -> (0 until r.length()).mapNotNull(r::optJSONObject) }
                        ?.firstOrNull { it.optString("id").equals(link.id, true) }
                    if (Account.isSignedIn) {
                        val mine = runCatching { Api.rpc(if (promo) "pasr_business_promo_mine" else "pasr_business_coupon_mine", JSONObject()) as? JSONArray }.getOrNull()
                        offerSaved = mine?.let { m -> (0 until m.length()).mapNotNull(m::optJSONObject) }
                            ?.any { it.optString(if (promo) "promo_id" else "coupon_id").equals(link.id, true) } == true
                    }
                    if (match == null) missing = if (promo) R.string.add_missing_promo else R.string.add_missing_coupon
                    else {
                        if (promo) match.put("kind", "code")
                        val end = runCatching { java.time.Instant.parse(match.optString("ends_at")) }.getOrNull()
                        if (end != null && end.isBefore(java.time.Instant.now())) missing = R.string.add_missing_expired
                        offer = match
                    }
                }
                else -> {
                    if (Catalog.template(link.id) == null) Catalog.refresh()
                    template = Catalog.template(link.id)
                    if (template == null) missing = R.string.add_missing_store
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            missing = R.string.add_missing_offline
        }
        loading = false
    }

    fun openInPasr() {
        if (link.isOffer) { nav.replace(Screen.Coupons); return }
        val id = addedCardId ?: existingStamp?.id ?: existingStore.firstOrNull()?.id
        if (id != null) nav.replace(Screen.Detail(id)) else nav.home()
    }

    SimpleScaffold(if (added) stringResource(R.string.add_done_title) else stringResource(R.string.add_title)) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Gap(8.dp)
            if (loading) {
                Box(Modifier.fillMaxWidth().size(200.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                return@Column
            }
            val m = missing
            if (m != null && existingStamp == null) {
                Text(stringResource(m), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
                Gap(8.dp)
                Text(stringResource(R.string.add_missing_hint), color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                Gap(24.dp)
                BrandButton(stringResource(R.string.add_close)) { nav.pop() }
                return@Column
            }
            if (added) {
                Icon(Icons.Filled.CheckCircle, null, Modifier.size(64.dp), tint = Color(0xFF2ED3A6))
                Gap(8.dp)
                Text(stringResource(R.string.add_done_title), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Gap(16.dp)
            } else {
                Text(kindTitle(link.kind).uppercase(), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Gap(10.dp)
            }
            // voorbeeld in de stijl van de zaak (stempelkaart en catalogus: zoals de kaart in Pasr; bon: de bestaande bonweergave)
            when {
                link.kind == 'k' -> {
                    val i = business
                    val preview = existingStamp ?: Card(
                        storeName = i?.displayName ?: kindTitle('k'), kindRaw = CardKind.STAMPS.raw, colorHex = i?.color ?: "#6A5CFF",
                        number = "PZ", formatRaw = "qr", logo = i?.logo?.takeIf { !it.startsWith("http") }?.substringAfter(","),
                        details = CardDetails(issuer = "business", businessCardId = link.id, stampsTotal = i?.stampsTotal ?: 10, stampsCount = 0, reward = i?.reward),
                    )
                    CardFace(preview, Modifier.fillMaxWidth())
                }
                link.isOffer -> offer?.let { PasrOfferCard(it, saved = offerSaved || added) }
                else -> template?.let { t ->
                    CardFace(Card(storeName = t.name, templateID = t.id, kindRaw = t.kind.raw, colorHex = t.cardHex,
                        formatRaw = t.format.raw, number = ""), Modifier.fillMaxWidth())
                }
            }
            Gap(14.dp)
            val summary = when {
                added && link.isOffer -> stringResource(R.string.add_done_offer)
                added -> stringResource(R.string.add_done_card)
                link.kind == 'k' -> stringResource(R.string.add_summary_stamps, business?.stampsTotal ?: 10) +
                    (business?.reward?.let { " " + stringResource(R.string.add_summary_reward, it) } ?: "")
                link.isOffer -> offer?.let { it.optString("business") + " · " + it.optString("title") } ?: ""
                link.kind == 't' -> stringResource(R.string.add_summary_ticket)
                link.kind == 'g' -> stringResource(R.string.add_summary_gift)
                else -> stringResource(R.string.add_summary_store)
            }
            Text(summary, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            error?.let { Gap(10.dp); Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center) }
            Gap(22.dp)
            val already = !added && when {
                link.kind == 'k' -> existingStamp != null
                link.isOffer -> offerSaved
                else -> existingStore.isNotEmpty()
            }
            if (added || already) {
                if (already) {
                    Text(stringResource(if (link.isOffer) R.string.add_already_offer else R.string.add_already_card),
                        fontWeight = FontWeight.SemiBold, color = Color(0xFF2ED3A6), textAlign = TextAlign.Center)
                    Gap(12.dp)
                }
                BrandButton(stringResource(R.string.add_view_in_pasr)) { openInPasr() }
                if (already && link.isCatalog) {
                    TextButton({ template?.let { nav.replace(Screen.Editor(template = it, kind = it.kind)) } }, Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.add_another))
                    }
                }
            } else {
                val needsAccount = link.isOffer && !Account.isSignedIn
                BrandButton(if (busy) stringResource(R.string.add_busy) else stringResource(R.string.add_button), enabled = !busy && !needsAccount) {
                    if (link.isCatalog) {
                        template?.let { nav.replace(Screen.Editor(template = it, kind = it.kind)) }
                        return@BrandButton
                    }
                    busy = true; error = null
                    scope.launch {
                        try {
                            if (link.kind == 'k') {
                                addedCardId = Business.join(link.id, business).id
                            } else {
                                val promo = link.kind == 'a'
                                Api.rpc(if (promo) "pasr_business_promo_claim" else "pasr_business_coupon_claim",
                                    JSONObject().put(if (promo) "p_promo" else "p_coupon", link.id))
                                offerSaved = true
                            }
                            added = true
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: PasrError) {
                            error = e.message
                        } catch (e: Exception) {
                            error = genericError
                        }
                        busy = false
                    }
                }
                if (needsAccount) {
                    Gap(10.dp)
                    Text(stringResource(R.string.add_needs_account), color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
                }
                TextButton({ nav.pop() }, Modifier.fillMaxWidth()) { Text(stringResource(R.string.add_not_now)) }
            }
            Gap(24.dp)
        }
    }
}

