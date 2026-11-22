package app.lrvdlinden.pasr.data

import android.util.Base64
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.OffsetDateTime

fun isoOf(ms: Long): String = Instant.ofEpochMilli(ms).toString()

fun parseIso(s: String?): Long? {
    if (s.isNullOrBlank()) return null
    return runCatching { OffsetDateTime.parse(s).toInstant().toEpochMilli() }.getOrNull()
        ?: runCatching { Instant.parse(s).toEpochMilli() }.getOrNull()
        ?: runCatching { java.time.LocalDate.parse(s.take(10)).atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli() }.getOrNull()
}

/** Details naar en van JSON zoals iOS (CardDetails.json: datums als ISO 8601). */
object DetailsJson {
    fun toJson(d: CardDetails, withCaptions: Boolean = false): JSONObject = JSONObject().apply {
        d.eventDate?.let { put("eventDate", isoOf(it)) }
        d.venue?.let { put("venue", it) }
        d.seat?.let { put("seat", it) }
        d.renewsAt?.let { put("renewsAt", isoOf(it)) }
        d.cost?.let { put("cost", it) }
        d.period?.let { put("period", it) }
        d.codeAsBarcode?.let { put("codeAsBarcode", it) }
        if (withCaptions) d.captions?.let { put("captions", JSONArray(it)) }
        d.stampsTotal?.let { put("stampsTotal", it) }
        d.stampsCount?.let { put("stampsCount", it) }
        d.reward?.let { put("reward", it) }
        d.issuer?.let { put("issuer", it) }
        d.businessCardId?.let { put("businessCardId", it) }
        d.memberCode?.let { put("memberCode", it) }
    }

    fun fromJson(o: JSONObject): CardDetails = CardDetails(
        eventDate = parseIso(o.str("eventDate")),
        venue = o.str("venue"),
        seat = o.str("seat"),
        renewsAt = parseIso(o.str("renewsAt")),
        cost = (o.opt("cost") as? Number)?.toDouble(),
        period = o.str("period"),
        codeAsBarcode = o.opt("codeAsBarcode") as? Boolean,
        captions = o.optJSONArray("captions")?.let { a -> (0 until a.length()).map { a.optString(it) }.take(4) },
        stampsTotal = o.int("stampsTotal"),
        stampsCount = o.int("stampsCount"),
        reward = o.str("reward"),
        issuer = o.str("issuer"),
        businessCardId = o.str("businessCardId"),
        memberCode = o.str("memberCode"),
    )
}

/**
 * Houdt de kaarten in het Pasr-account gelijk met dit toestel (zelfde protocol als iOS, functie pasr_sync): wat hier
 * veranderde gaat omhoog, wat op de server sinds de vorige keer veranderde komt omlaag; de nieuwste wijziging wint.
 * Foto's blijven op het toestel; een eigen voorkant en eigen logo gaan mee als ze klein zijn.
 */
object Sync {
    private val mutex = Mutex()
    val running = MutableStateFlow(false)
    val lastError = MutableStateFlow<String?>(null)

    private fun sinceKey(u: String) = "sync.since.$u"
    private fun pushedKey(u: String) = "sync.pushed.$u"
    fun lastSync(user: String): Long? = Prefs.long(pushedKey(user)).takeIf { it > 0 }
    fun forget(user: String) { Prefs.setString(sinceKey(user), null); Prefs.setLong(pushedKey(user), 0) }

    suspend fun sync() {
        val user = Account.session.value?.userID ?: return
        if (mutex.isLocked) return
        mutex.withLock {
            running.value = true
            try {
                val started = nowMs()
                val pushed = lastSync(user) ?: 0L
                val changes = JSONArray()
                CardStore.cards.value.filter { it.changedAt > pushed }.forEach { changes.put(row(it)) }
                val body = JSONObject().put("changes", changes).put("since", Prefs.string(sinceKey(user)) ?: JSONObject.NULL)
                val result = Api.rpc("pasr_sync", body) as? JSONObject ?: return
                apply(result.optJSONArray("cards") ?: JSONArray())
                result.str("now")?.let { Prefs.setString(sinceKey(user), it) }
                Prefs.setLong(pushedKey(user), started)
                lastError.value = null
                val countryKey = "sync.country.$user"
                if (!Prefs.bool(countryKey)) Account.deviceCountry?.let { c ->
                    runCatching { Api.rpc("pasr_set_country", JSONObject().put("p_country", c)) }.onSuccess { Prefs.setBool(countryKey, true) }
                }
            } catch (e: PasrError) {
                lastError.value = e.message
            } catch (e: Exception) {
                lastError.value = "Synchroniseren lukte niet."
            } finally {
                running.value = false
            }
        }
    }

    private fun row(c: Card): JSONObject = JSONObject().apply {
        put("id", c.id)
        put("updated_at", isoOf(c.changedAt))
        put("deleted", c.deletedAt != null)
        if (c.deletedAt == null) put("card", payload(c))
    }

    private fun payload(c: Card): JSONObject = JSONObject().apply {
        put("storeName", c.storeName); put("number", c.number); put("format", c.formatRaw); put("kind", c.kindRaw)
        put("colorHex", c.colorHex); put("note", c.note); put("isFavorite", c.isFavorite); put("isLocked", c.isLocked)
        put("useCount", c.useCount); put("createdAt", isoOf(c.createdAt))
        c.templateID?.let { put("templateID", it) }
        c.lastUsed?.let { put("lastUsed", isoOf(it)) }
        c.balance?.let { put("balance", it) }
        c.currencyCode?.let { put("currencyCode", it) }
        c.pin?.let { put("pin", it) }
        c.expiresAt?.let { put("expiresAt", isoOf(it)) }
        c.website?.let { put("website", it) }
        c.balanceURL?.let { put("balanceURL", it) }
        put("details", DetailsJson.toJson(c.details))
        put("hasCover", c.cover != null)
        c.cover?.let { if (it.length < 160_000) put("cover", it) }
        put("history", JSONArray().apply {
            // gebruiksmomenten met een ingevuld bedrag gaan mee (Laatst gebruikt); oudere versies slaan "shown" over
            c.history.filter { it.kind != "shown" || it.amount != null }.take(60).forEach { e ->
                put(JSONObject().apply {
                    put("id", e.id); put("date", isoOf(e.date)); put("kind", e.kind)
                    e.amount?.let { put("amount", it) }; e.balance?.let { put("balance", it) }
                    // filiaalnaam van een gebruiksmoment blijft op het apparaat; plaats en provincie bewaart Pasr niet
                    if (e.kind != "shown") e.place?.let { put("place", it) }
                    e.spentID?.let { put("spentID", it) }
                })
            }
        })
        put("uses", true)
        if (c.places.isNotEmpty()) put("places", JSONArray().apply {
            c.places.forEach { put(JSONObject().put("name", it.name).put("lat", it.latitude).put("lon", it.longitude)) }
        })
        if (c.logo != null && !c.logoFromWebsite) {
            put("ownLogo", true)
            if (c.logo.length < 200_000) put("logo", c.logo)
        }
    }

    private fun apply(rows: JSONArray) {
        val byId = CardStore.cards.value.associateBy { it.id.uppercase() }.toMutableMap()
        var changed = false
        for (row in rows.objects()) {
            val id = row.str("id")?.uppercase() ?: continue
            val stamp = parseIso(row.str("updated_at")) ?: continue
            val local = byId[id]
            if (local != null && local.changedAt >= stamp) continue
            if (row.optBoolean("deleted")) {
                if (local != null && local.deletedAt == null) { byId[id] = local.copy(deletedAt = stamp); changed = true }
                continue
            }
            val f = row.optJSONObject("card") ?: continue
            byId[id] = fill(local ?: Card(id = id), f).copy(deletedAt = null, updatedAt = stamp)
            changed = true
        }
        if (changed) CardStore.replaceAll(byId.values.toList())
    }

    private fun fill(card: Card, f: JSONObject): Card {
        var c = card.copy(
            storeName = f.str("storeName") ?: card.storeName,
            number = f.optString("number", card.number),
            formatRaw = f.str("format") ?: card.formatRaw,
            kindRaw = f.str("kind") ?: card.kindRaw,
            colorHex = f.str("colorHex") ?: card.colorHex,
            templateID = f.str("templateID"),
            note = f.optString("note", ""),
            isFavorite = f.optBoolean("isFavorite", false),
            isLocked = f.optBoolean("isLocked", false),
            useCount = maxOf(card.useCount, f.optInt("useCount", 0)),
            lastUsed = maxOf(card.lastUsed ?: 0L, parseIso(f.str("lastUsed")) ?: 0L).takeIf { it > 0 },
            createdAt = parseIso(f.str("createdAt")) ?: card.createdAt,
            balance = (f.opt("balance") as? Number)?.toDouble(),
            currencyCode = f.str("currencyCode"),
            pin = f.str("pin"),
            expiresAt = parseIso(f.str("expiresAt")),
            website = f.str("website"),
            balanceURL = f.str("balanceURL"),
        )
        f.optJSONObject("details")?.let { d -> c = c.copy(details = DetailsJson.fromJson(d).copy(captions = card.details.captions)) }
        val cover = f.str("cover")
        if (cover != null) c = c.copy(cover = cover) else if (f.has("hasCover") && !f.optBoolean("hasCover")) c = c.copy(cover = null)
        if (f.has("history")) {
            val remote = f.optJSONArray("history")?.objects()?.mapNotNull { e ->
                val at = parseIso(e.str("date")) ?: return@mapNotNull null
                CardEvent(id = e.str("id") ?: newId(), date = at, kind = e.str("kind") ?: return@mapNotNull null,
                    amount = (e.opt("amount") as? Number)?.toDouble(), balance = (e.opt("balance") as? Number)?.toDouble(),
                    place = e.str("place"), spentID = e.str("spentID")?.uppercase())
            } ?: emptyList()
            val oldest = remote.minOfOrNull { it.date }
            val ids = remote.map { it.id }.toSet()
            // een oudere versie (zonder "uses") stuurt geen gebruiksmomenten: dan blijven de ingevulde bedragen van hier staan
            val remoteHasUses = f.optBoolean("uses", false)
            val localPlaces = card.history.filter { it.kind == "shown" && it.place != null }.associate { it.id to it.place }
            val merged = remote.map { if (it.kind == "shown" && it.place == null && localPlaces[it.id] != null) it.copy(place = localPlaces[it.id]) else it }
            c = c.copy(history = Card.trimHistory(merged + card.history.filter {
                it.id !in ids && ((it.kind == "shown" && (it.amount == null || !remoteHasUses)) || (oldest != null && it.date < oldest))
            }))
        }
        c = c.copy(places = f.optJSONArray("places")?.objects()?.mapNotNull { p ->
            val lat = (p.opt("lat") as? Number)?.toDouble() ?: return@mapNotNull null
            val lon = (p.opt("lon") as? Number)?.toDouble() ?: return@mapNotNull null
            CardPlace(name = p.optString("name"), latitude = lat, longitude = lon)
        } ?: emptyList())
        val logo = f.str("logo")?.takeIf { runCatching { Base64.decode(it, Base64.DEFAULT) }.isSuccess }
        c = when {
            logo != null -> c.copy(logo = logo, logoFromWebsite = false)
            !f.optBoolean("ownLogo") && (card.logoFromWebsite || card.logo == null) -> c.copy(logo = null, logoFromWebsite = false)
            else -> c
        }
        return c
    }
}
