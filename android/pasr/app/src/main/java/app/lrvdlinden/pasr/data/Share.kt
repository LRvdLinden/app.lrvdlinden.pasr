package app.lrvdlinden.pasr.data

import android.net.Uri
import android.util.Base64
import org.json.JSONObject

/**
 * Een kaart delen als link: https://pasr.nl/kaart/#<base64url JSON> (velden v,n,c,f,h,k,t,w,b,e,x, zoals iOS). Alles
 * staat na de #, dus pasr.nl ziet de kaart nooit. Een zakelijke stempelkaart gaat als join-link van de zaak.
 * Datums in `x` volgen Swift's JSONEncoder: seconden sinds 1 januari 2001.
 */
object Share {
    private const val REF_2001 = 978_307_200L
    const val WEB_BASE = "https://pasr.nl/kaart/"

    fun link(card: Card): String {
        val d = card.details
        if (d.isBusiness && d.businessCardId != null) return Business.joinLink(d.businessCardId)
        val o = JSONObject().put("v", 1).put("n", card.storeName).put("c", card.number).put("f", card.formatRaw)
            .put("h", card.colorHex).put("k", card.kindRaw)
        card.templateID?.let { o.put("t", it) }
        card.website?.let { o.put("w", it) }
        if (card.kind == CardKind.VOUCHER) card.balance?.let { o.put("b", it) }
        if (card.kind.hasExpiry) card.expiresAt?.let { o.put("e", it / 1000) }
        val x = d.copy(captions = null, issuer = null, businessCardId = null, memberCode = null)
        if (!x.isEmpty) o.put("x", JSONObject().apply {
            x.eventDate?.let { put("eventDate", it / 1000.0 - REF_2001) }
            x.venue?.let { put("venue", it) }
            x.seat?.let { put("seat", it) }
            x.renewsAt?.let { put("renewsAt", it / 1000.0 - REF_2001) }
            x.cost?.let { put("cost", it) }
            x.period?.let { put("period", it) }
            x.codeAsBarcode?.let { put("codeAsBarcode", it) }
            x.stampsTotal?.let { put("stampsTotal", it) }
            x.stampsCount?.let { put("stampsCount", it) }
            x.reward?.let { put("reward", it) }
        })
        val enc = Base64.encodeToString(o.toString().toByteArray(), Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        return WEB_BASE + "#" + enc
    }

    /** Leest https://pasr.nl/kaart/#… en pasr://kaart#…. Geeft een nieuwe (nog niet bewaarde) kaart. */
    fun decode(uri: Uri): Card? {
        val host = uri.host?.lowercase().orEmpty()
        val web = (host == "pasr.nl" || host == "www.pasr.nl") && (uri.path ?: "").startsWith("/kaart")
        val app = uri.scheme == "pasr" && host == "kaart"
        if (!web && !app) return null
        val frag = uri.encodedFragment ?: return null
        val o = runCatching { JSONObject(String(Base64.decode(Uri.decode(frag), Base64.URL_SAFE or Base64.NO_WRAP))) }.getOrNull() ?: return null
        val name = o.str("n") ?: return null
        val number = o.optString("c")
        val kind = CardKind.of(o.str("k"))
        if (number.isEmpty() && kind != CardKind.STAMPS) return null
        val x = o.optJSONObject("x")
        fun date(key: String): Long? = (x?.opt(key) as? Number)?.let { ((it.toDouble() + REF_2001) * 1000).toLong() }
            ?: parseIso(x?.str(key))
        val details = if (x == null) CardDetails() else CardDetails(
            eventDate = date("eventDate"), venue = x.str("venue"), seat = x.str("seat"), renewsAt = date("renewsAt"),
            cost = (x.opt("cost") as? Number)?.toDouble(), period = x.str("period"), codeAsBarcode = x.opt("codeAsBarcode") as? Boolean,
            stampsTotal = x.int("stampsTotal"), stampsCount = x.int("stampsCount"), reward = x.str("reward"),
        )
        val balance = (o.opt("b") as? Number)?.toDouble()
        return Card(
            storeName = name, number = number, formatRaw = o.str("f") ?: "code128", colorHex = o.str("h") ?: "#2B2F3A",
            kindRaw = o.str("k") ?: "loyalty", templateID = o.str("t"), website = o.str("w"), balance = balance,
            currencyCode = if (balance != null) "EUR" else null,
            expiresAt = (o.opt("e") as? Number)?.toLong()?.let { it * 1000 }, details = details,
        )
    }
}
