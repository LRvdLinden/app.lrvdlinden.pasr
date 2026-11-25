package app.lrvdlinden.pasr.data

import android.net.Uri
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import org.json.JSONObject

object TempSharing {
    @Serializable
    data class Link(val token: String, val key: String, val name: String, val until: Long, val revoked: Boolean = false) {
        val url get() = "https://pasr.nl/tijdelijk/#$token"
    }

    private const val PREF = "temp_sharing"
    private val mutex = Mutex()
    fun links(): List<Link> = Prefs.string(PREF)?.let(Crypto::decryptString)?.let {
        runCatching { PasrJson.decodeFromString<List<Link>>(it) }.getOrNull()
    }.orEmpty().filter { it.until > nowMs() - 7 * 86_400_000L }

    private fun save(links: List<Link>) = Prefs.setString(PREF, Crypto.encryptString(PasrJson.encodeToString(links)))

    @Serializable
    data class Received(val token: String, val name: String)
    private const val RECEIVED = "temp_sharing.received"

    fun received(): List<Received> = Prefs.string(RECEIVED)?.let(Crypto::decryptString)?.let {
        runCatching { PasrJson.decodeFromString<List<Received>>(it) }.getOrNull()
    }.orEmpty()

    @Synchronized
    fun rememberReceived(token: String, name: String) {
        val current = received()
        if (current.any { it.token == token && it.name == name }) return
        val updated = (listOf(Received(token, name)) + current.filterNot { it.token == token }).take(40)
        Prefs.setString(RECEIVED, Crypto.encryptString(PasrJson.encodeToString(updated)))
    }

    suspend fun create(card: Card, until: Long): Link = mutex.withLock {
        require(!card.isBusinessStamps && card.number.isNotBlank())
        val data = JSONObject().put("storeName", card.storeName).put("number", card.number)
            .put("format", card.formatRaw).put("kind", card.kindRaw).put("colorHex", card.colorHex)
            .put("templateID", card.templateID).put("website", card.website)
        card.expiresAt?.let { data.put("expiresAt", isoOf(it)) }
        if (card.kind == CardKind.VOUCHER) {
            data.put("pin", card.pin).put("balance", card.balance).put("currencyCode", card.currencyCode)
        } else if (card.kind != CardKind.LOYALTY) {
            data.put("details", DetailsJson.toJson(card.details))
        }
        val result = Api.publicRpc("pasr_temp_share_create", JSONObject().put("p_card", data).put("p_expires", isoOf(until))) as? JSONObject
            ?: throw PasrError("Tijdelijke link maken is mislukt.")
        val link = Link(result.getString("token"), result.getString("key"), card.storeName, until)
        save(listOf(link) + links())
        link
    }

    suspend fun revoke(link: Link) = mutex.withLock {
        Api.publicRpc("pasr_temp_share_revoke", parameters(link))
        save(links().map { if (it.token == link.token) it.copy(revoked = true) else it })
    }

    suspend fun change(link: Link, until: Long) = mutex.withLock {
        val result = Api.publicRpc("pasr_temp_share_update", parameters(link).put("p_expires", isoOf(until))) as? JSONObject
        if (result?.optBoolean("ok") != true) throw PasrError("Deze link is niet meer actief.")
        save(links().map { if (it.token == link.token) it.copy(until = parseIso(result.str("expires_at")) ?: until) else it })
    }

    private fun parameters(link: Link) = JSONObject().put("p_token", link.token).put("p_key", link.key)

    fun token(uri: Uri): String? {
        val web = uri.scheme == "https" && uri.host in listOf("pasr.nl", "www.pasr.nl") && uri.pathSegments.firstOrNull() == "tijdelijk"
        val app = uri.scheme == "pasr" && uri.host == "tijdelijk"
        return uri.fragment?.takeIf { (web || app) && it.matches(Regex("[A-Za-z0-9_-]{16,40}")) }
    }

    suspend fun open(token: String): Pair<Card, Long> {
        val result = Api.publicRpc("pasr_temp_share_get", JSONObject().put("p_token", token)) as? JSONObject
        if (result?.optString("status") != "ok") throw PasrError("Deze kaart is verlopen of het delen is gestopt.")
        val until = parseIso(result.str("expires_at"))?.takeIf { it > nowMs() }
            ?: throw PasrError("Deze kaart is verlopen.")
        return Sync.fill(Card(), result.getJSONObject("card")) to until
    }
}

object SharedGroups {
    suspend fun overview(): JSONObject = Api.rpc("pasr_groups", JSONObject()) as? JSONObject
        ?: throw PasrError("Gedeelde Pasr ophalen is mislukt.")

    suspend fun action(name: String, body: JSONObject) {
        Api.rpc(name, body)
    }

    suspend fun invite(group: String, email: String): Boolean =
        Api.function("group-invite", JSONObject().put("group", group).put("email", email.trim().lowercase()), signedIn = true)
            .optBoolean("mailed")

    suspend fun move(card: Card, group: String?) {
        if (card.groupId == group) return
        if (!Account.isSignedIn || card.isBusinessStamps || card.isLocked) throw PasrError("Deze kaart kan niet worden verplaatst.")
        val memberIds = overview().getJSONArray("groups").objects().mapNotNull { it.str("id")?.lowercase() }
        if (group != null && group !in memberIds || card.groupId != null && card.groupId !in memberIds) {
            throw PasrError("Je hebt geen toegang meer tot deze groep.")
        }
        val replacement = card.copy(id = newId(), groupId = group, photos = emptyList())
        CardStore.upsert(replacement)
        card.photos.forEach { slot -> CardStore.photo(card.id, slot)?.let { CardStore.setPhoto(replacement.id, slot, it) } }
        Sync.sync()
        if (Sync.lastError.value != null || CardStore.get(replacement.id) == null) {
            throw PasrError("Synchroniseren is mislukt. De oorspronkelijke kaart is bewaard.")
        }
        CardStore.delete(card.id)
        Sync.sync()
    }
}
