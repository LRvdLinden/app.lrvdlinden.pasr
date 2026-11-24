package app.lrvdlinden.pasr.data

import android.net.Uri
import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.URL

/** Een stempelkaart in de zoeklijst (pasr_business_directory). */
data class DirectoryCard(
    val cardId: String,
    val cardName: String,
    val business: String,
    val city: String?,
    val logo: String?,
    val color: String?,
    val stampsTotal: Int?,
    val reward: String?,
    val distanceKm: Double?,
)

/** Wat de server over een zakelijke stempelkaart zegt (alles optioneel, meerdere veldnamen zoals iOS). */
data class BusinessInfo(
    val cardId: String?, val memberCode: String?, val name: String?, val business: String?, val logo: String?,
    val color: String?, val stampsTotal: Int?, val stampsCount: Int?, val reward: String?, val active: Boolean,
    val status: String?,
) {
    val displayName get() = business ?: name ?: "Stempelkaart"

    companion object {
        fun from(json: Any?): BusinessInfo? {
            val d = (json as? JSONObject) ?: (json as? JSONArray)?.optJSONObject(0) ?: return null
            val card = d.optJSONObject("card")
            val status = d.str("status")?.lowercase()
            val hex = (d.str("color", "card_hex", "colour", "color_hex") ?: card?.str("color"))?.trim()?.let { if (it.startsWith("#")) it else "#$it" }
                ?.takeIf { Regex("^#[0-9A-Fa-f]{6}$").matches(it) }?.uppercase()
            return BusinessInfo(
                cardId = d.str("business_card_id", "card_id") ?: card?.str("id") ?: d.str("id"),
                memberCode = d.str("member_code", "code"),
                name = d.str("name", "card_name", "title") ?: card?.str("name"),
                business = d.str("business_name", "business") ?: d.optJSONObject("business")?.str("name") ?: card?.str("business"),
                logo = d.str("logo", "logo_url") ?: card?.str("logo"),
                color = hex,
                stampsTotal = d.int("stamps_total", "stampsTotal", "total") ?: card?.int("stamps_total"),
                stampsCount = d.int("stamps_count", "stampsCount", "stamps", "count"),
                reward = d.str("reward") ?: card?.str("reward"),
                active = d.opt("published") != false && status !in setOf("blocked", "removed", "unpublished", "inactive", "not_found"),
                status = status,
            )
        }
    }
}

/**
 * Pasr voor ondernemers: zakelijke stempelkaarten. Je sluit aan via de zoeklijst, de join-link of de QR van de zaak
 * (pasr_business_join) en krijgt een eigen klantcode. Alleen de zaak zet stempels; Pasr toont de stand (alleen-lezen).
 */
object Business {
    private val codeRegex = Regex("^PZ([A-HJ-NP-Z2-9]{10}|[A-HJ-NP-Z2-9]{14})$")
    private val uuidRegex = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

    suspend fun directory(query: String?, lat: Double? = null, lng: Double? = null): List<DirectoryCard> {
        val body = JSONObject().put("p_query", query?.trim()?.takeIf { it.isNotEmpty() } ?: JSONObject.NULL)
            .put("p_lat", lat ?: JSONObject.NULL).put("p_lng", lng ?: JSONObject.NULL).put("p_limit", 80)
        val arr = Api.publicRpc("pasr_business_directory", body) as? JSONArray ?: return emptyList()
        return arr.objects().mapNotNull { o ->
            DirectoryCard(
                cardId = o.str("card_id") ?: return@mapNotNull null, cardName = o.optString("card_name"),
                business = o.optString("business_name"), city = o.str("city"), logo = o.str("logo"), color = o.str("color"),
                stampsTotal = o.int("stamps_total"), reward = o.str("reward"), distanceKm = (o.opt("distance_km") as? Number)?.toDouble(),
            )
        }
    }

    suspend fun preview(cardId: String): BusinessInfo? =
        runCatching { BusinessInfo.from(Api.publicRpc("pasr_business_card", JSONObject().put("p_card", cardId))) }.getOrNull()

    suspend fun member(code: String): BusinessInfo {
        val info = BusinessInfo.from(Api.publicRpc("pasr_business_member", JSONObject().put("p_code", code)))
        if (info == null || info.status == "not_found") throw PasrError("Deze stempelkaart is niet (meer) bekend bij de zaak.")
        return info
    }

    private suspend fun makeCard(cardId: String, code: String, info: BusinessInfo?, preview: BusinessInfo?): Card {
        val logo = logoBase64(info?.logo ?: preview?.logo)
        val card = Card(
            storeName = info?.displayName ?: preview?.displayName ?: "Stempelkaart",
            number = code, formatRaw = BarcodeFormat.QR.raw, kindRaw = CardKind.STAMPS.raw,
            colorHex = info?.color ?: preview?.color ?: "#6A5CFF",
            logo = logo, logoFromWebsite = false,
            details = CardDetails(
                issuer = "business", businessCardId = cardId.lowercase(), memberCode = code,
                stampsTotal = info?.stampsTotal ?: preview?.stampsTotal ?: 10,
                stampsCount = info?.stampsCount ?: 0, reward = info?.reward ?: preview?.reward,
            ),
        )
        CardStore.upsert(card)
        return card
    }

    /** Aansluiten: nieuwe klantcode, stand ophalen, kaart in Pasr zetten. */
    suspend fun join(cardId: String, preview: BusinessInfo?, referralToken: String? = null): Card {
        val json = if (!referralToken.isNullOrBlank()) {
            if (!Account.isSignedIn) throw PasrError("Log in bij je Pasr-account om deze uitnodiging te gebruiken.")
            Api.rpc("pasr_business_referral_join", JSONObject().put("p_card", cardId).put("p_token", referralToken))
        } else Api.publicRpc("pasr_business_join", JSONObject().put("p_card", cardId))
        val joined = BusinessInfo.from(json)
        val code = (json as? String) ?: joined?.memberCode
        if (code.isNullOrEmpty() || code.length > 120) throw PasrError("Aanmelden bij deze stempelkaart lukte niet. Probeer het later opnieuw.")
        val info = runCatching { member(code) }.getOrNull() ?: joined
        return makeCard(cardId, code, info, preview)
    }

    /** Een lidcode uit de browser overnemen (stempels gaan mee). null = onbekende code (dan gewoon aansluiten). */
    suspend fun claim(code: String, cardId: String, preview: BusinessInfo?): Card? {
        val json = Api.publicRpc("pasr_business_claim", JSONObject().put("p_code", code))
        val info = BusinessInfo.from(json)
        if (info?.status == "blocked") throw PasrError("Deze stempelkaart is niet meer beschikbaar.")
        if (info == null || !info.active || info.memberCode == null) return null
        return makeCard(info.cardId ?: cardId, code, info, preview)
    }

    /** Stand van één kaart bijwerken; geeft de nieuwe kaart als er iets veranderde. */
    suspend fun refresh(card: Card): Card? {
        val d = card.details
        val code = d.memberCode ?: return null
        if (!d.isBusiness) return null
        val info = runCatching { member(code) }.getOrNull() ?: return null
        val nd = d.copy(
            stampsTotal = info.stampsTotal?.coerceIn(2, 30) ?: d.stampsTotal,
            stampsCount = info.stampsCount?.coerceAtLeast(0) ?: d.stampsCount,
            reward = info.reward ?: d.reward,
        )
        var c = card
        if (nd != d) c = c.copy(details = nd)
        if (info.color != null && !info.color.equals(c.colorHex, true)) c = c.copy(colorHex = info.color)
        if (c.logo == null) logoBase64(info.logo)?.let { c = c.copy(logo = it) }
        if (c == card) return null
        CardStore.upsert(c)
        return c
    }

    suspend fun refreshAll(force: Boolean = false): List<Card> {
        if (!force && nowMs() - Prefs.long("business.at") < 120_000) return emptyList()
        Prefs.setLong("business.at", nowMs())
        return CardStore.visible.filter { it.isBusinessStamps }.mapNotNull { refresh(it) }
    }

    private suspend fun logoBase64(value: String?): String? {
        if (value.isNullOrEmpty()) return null
        if (value.startsWith("https://")) return withContext(Dispatchers.IO) {
            runCatching {
                val bytes = URL(value).openStream().use { it.readBytes() }
                if (bytes.size < 600_000) Base64.encodeToString(bytes, Base64.NO_WRAP) else null
            }.getOrNull()
        }
        val raw = value.substringAfter(",")
        return raw.takeIf { runCatching { Base64.decode(it, Base64.DEFAULT) }.isSuccess && it.length < 800_000 }
    }

    // ---- links ----

    /** https://pasr.nl/zakelijk/kaart/<uuid>/, de oude vorm …/zakelijk/kaart/#<uuid> (ook www. en ?id=) en pasr://zakelijk/kaart#<uuid> of pasr://zakelijk#<uuid>. */
    fun cardId(uri: Uri): String? {
        val host = uri.host?.lowercase().orEmpty()
        val web = (host == "pasr.nl" || host == "www.pasr.nl") && (uri.path ?: "").startsWith("/zakelijk/kaart")
        val app = uri.scheme == "pasr" && host == "zakelijk"
        if (!web && !app) return null
        return listOfNotNull(uri.fragment, uri.getQueryParameter("id"), uri.lastPathSegment)
            .map { it.trim('/', ' ').lowercase() }.firstOrNull { uuidRegex.matches(it) }
    }

    fun memberCode(uri: Uri): String? {
        val raw = runCatching { uri.getQueryParameter("code") ?: uri.getQueryParameter("lid") }.getOrNull() ?: return null
        return raw.trim().uppercase().takeIf { codeRegex.matches(it) }
    }

    /** Eigen pagina van de kaart (met de kaart als OG-afbeelding bij delen). */
    fun joinLink(cardId: String) = "https://pasr.nl/zakelijk/kaart/${cardId.lowercase()}/"
}
