package app.lrvdlinden.pasr.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import android.util.LruCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.Normalizer

data class LogoStyle(val card: String, val tint: String?, val plate: String?, val opaque: Boolean)

/** Een bekende winkel: naam, website (voor het logo), kaartkleur en de gebruikelijke barcode. */
data class StoreTemplate(
    val id: String,
    val name: String,
    val domain: String,
    val category: String,
    val colorHex: String,
    val format: BarcodeFormat,
    val aliases: List<String> = emptyList(),
    val kind: CardKind = CardKind.LOYALTY,
    val style: LogoStyle? = null,
    val hasAssetLogo: Boolean = false,
    /** Uit het beheer: kleur en logo zijn op elkaar afgestemd. */
    val managed: Boolean = false,
    val remoteLogo: String? = null,
    val cover: String? = null,
    val guide: JSONObject? = null,
) {
    val cardHex: String get() = if (managed) colorHex else style?.card ?: colorHex
    val searchKey: String by lazy { Catalog.fold("$name ${aliases.joinToString(" ")} $domain") }
}

/**
 * Winkelcatalogus: de lijst in de app (assets/catalog.json, zelfde als iOS) plus wat het beheer heeft toegevoegd of
 * gewijzigd (pasr_store_catalog, alleen wat nieuw is sinds de vorige keer). Het beheer is leidend.
 */
object Catalog {
    private lateinit var app: Context
    private var builtIn: List<StoreTemplate> = emptyList()
    private val remote = mutableMapOf<String, JSONObject>()
    private val removed = mutableSetOf<String>()
    val all = MutableStateFlow<List<StoreTemplate>>(emptyList())
    var balancePages: Map<String, String> = emptyMap(); private set
    private val bitmaps = LruCache<String, Bitmap>(80)
    private val cacheFile get() = File(app.filesDir, "catalog-remote.json")

    fun init(context: Context) {
        app = context.applicationContext
        builtIn = runCatching {
            val arr = JSONArray(app.assets.open("catalog.json").bufferedReader().use { it.readText() })
            arr.objects().map { o ->
                val st = o.optJSONObject("style")
                StoreTemplate(
                    id = o.getString("id"), name = o.getString("name"), domain = o.optString("domain"),
                    category = o.optString("category"), colorHex = o.optString("color", "#2B2F3A"),
                    format = BarcodeFormat.of(o.optString("format")),
                    aliases = o.optJSONArray("aliases")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList(),
                    kind = CardKind.of(o.optString("kind")),
                    style = st?.let { LogoStyle(it.optString("card"), it.str("tint"), it.str("plate"), it.optBoolean("opaque")) },
                    hasAssetLogo = o.optBoolean("logo"),
                )
            }
        }.getOrElse { emptyList() }
        runCatching {
            if (cacheFile.exists()) {
                val o = JSONObject(cacheFile.readText())
                o.optJSONObject("stores")?.let { s -> s.keys().forEach { k -> remote[k] = s.getJSONObject(k) } }
                o.optJSONArray("removed")?.let { r -> (0 until r.length()).forEach { removed.add(r.getString(it)) } }
                o.optJSONObject("balance")?.let { b -> balancePages = b.keys().asSequence().associateWith { b.getString(it) } }
            }
        }
        rebuild()
    }

    private fun remoteTemplate(o: JSONObject): StoreTemplate? {
        val id = o.str("id") ?: return null
        val name = o.str("name") ?: return null
        return StoreTemplate(
            id = id, name = name, domain = o.optString("domain"), category = o.optString("category", "Overig"),
            colorHex = o.str("card_hex") ?: "#2B2F3A", format = BarcodeFormat.of(o.str("format")),
            aliases = o.optJSONArray("aliases")?.let { a -> (0 until a.length()).map { a.optString(it) } } ?: emptyList(),
            kind = CardKind.of(o.str("kind")), managed = true, remoteLogo = o.str("logo"), cover = o.str("cover"),
            guide = o.optJSONObject("guide"),
        )
    }

    private fun rebuild() {
        val byId = remote.values.mapNotNull { remoteTemplate(it) }.associateBy { it.id.lowercase() }
        val ids = builtIn.map { it.id.lowercase() }.toSet()
        val list = builtIn.filter { it.id.lowercase() !in removed }.map { t ->
            byId[t.id.lowercase()]?.let { r -> r.copy(id = t.id, style = t.style, hasAssetLogo = t.hasAssetLogo) } ?: t
        } + byId.values.filter { it.id.lowercase() !in ids }
        all.value = list.sortedWith { a, b -> java.text.Collator.getInstance(java.util.Locale("nl")).compare(a.name, b.name) }
    }

    /** Nieuwe en gewijzigde winkels ophalen (bij opstarten, hoogstens eens per 6 uur). */
    suspend fun refresh(force: Boolean = false) {
        if (!force && nowMs() - Prefs.long("catalog.at") < 6 * 3_600_000) return
        val since = Prefs.string("catalog.since")
        val result = runCatching {
            Api.post("rest/v1/rpc/pasr_store_catalog", JSONObject().put("p_since", since ?: JSONObject.NULL)) as? JSONObject
        }.getOrNull() ?: return
        result.optJSONArray("stores")?.objects()?.forEach { o ->
            val id = o.str("id")?.lowercase() ?: return@forEach
            if (o.optBoolean("removed")) { remote.remove(id); removed.add(id) } else { remote[id] = o; removed.remove(id) }
        }
        result.optJSONObject("balance_pages")?.let { b -> balancePages = b.keys().asSequence().associateWith { b.getString(it) } }
        result.str("now")?.let { Prefs.setString("catalog.since", it) }
        Prefs.setLong("catalog.at", nowMs())
        withContext(Dispatchers.IO) {
            runCatching {
                cacheFile.writeText(JSONObject().put("stores", JSONObject(remote as Map<*, *>)).put("removed", JSONArray(removed.toList()))
                    .put("balance", JSONObject(balancePages)).toString())
            }
        }
        bitmaps.evictAll()
        rebuild()
    }

    fun template(id: String?): StoreTemplate? {
        if (id == null) return null
        return all.value.firstOrNull { it.id == id } ?: all.value.firstOrNull { it.id.equals(id, ignoreCase = true) }
    }

    fun fold(s: String): String = Normalizer.normalize(s.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")

    fun search(query: String, kind: CardKind? = null): List<StoreTemplate> {
        val q = fold(query.trim())
        return all.value.filter { (kind == null || it.kind == kind) && (q.isEmpty() || it.searchKey.contains(q)) }
    }

    fun normalizedDomain(input: String?): String? {
        var t = input?.trim()?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
        t.indexOf("://").takeIf { it >= 0 }?.let { t = t.substring(it + 3) }
        t.indexOf('/').takeIf { it >= 0 }?.let { t = t.substring(0, it) }
        if (t.startsWith("www.")) t = t.substring(4)
        return t.takeIf { it.contains('.') && !it.contains(' ') }
    }

    fun decodeBase64Bitmap(b64: String?): Bitmap? {
        if (b64.isNullOrEmpty()) return null
        return runCatching {
            val raw = b64.substringAfter(",")
            val bytes = Base64.decode(raw, Base64.DEFAULT)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        }.getOrNull()
    }

    /** Logo van een winkel: uit het beheer (base64) of uit de app (assets/logos/<domein>.png). */
    fun logo(t: StoreTemplate?): Bitmap? {
        t ?: return null
        val key = "t:${t.id}"
        bitmaps.get(key)?.let { return it }
        val bmp = decodeBase64Bitmap(t.remoteLogo) ?: if (t.hasAssetLogo) assetLogo(t.domain) else null
        if (bmp != null) bitmaps.put(key, bmp)
        return bmp
    }

    fun assetLogo(domain: String?): Bitmap? {
        domain ?: return null
        val key = "d:$domain"
        bitmaps.get(key)?.let { return it }
        return runCatching { app.assets.open("logos/$domain.png").use { BitmapFactory.decodeStream(it) } }.getOrNull()
            ?.also { bitmaps.put(key, it) }
    }

    /** Logo voor een kaart: eigen/zakelijk logo, anders dat van de winkel of website. */
    fun logo(card: Card): Bitmap? {
        card.logo?.let { b64 ->
            val key = "c:${card.id}:${b64.length}:${b64.hashCode()}"
            bitmaps.get(key)?.let { return it }
            decodeBase64Bitmap(b64)?.let { bitmaps.put(key, it); return it }
        }
        template(card.templateID)?.let { t -> logo(t)?.let { return it } }
        return assetLogo(normalizedDomain(card.website))
    }

    fun styleFor(card: Card): LogoStyle? {
        if (card.logo != null) return null
        val t = template(card.templateID) ?: return null
        return if (t.managed) null else t.style
    }

    fun coverBitmap(card: Card): Bitmap? {
        card.cover?.let { return decodeBase64Bitmap(it) }
        if (card.kind == CardKind.VOUCHER) {
            val t = template(card.templateID) ?: return null
            val key = "cov:${t.id}"
            bitmaps.get(key)?.let { return it }
            return decodeBase64Bitmap(t.cover)?.also { bitmaps.put(key, it) }
        }
        return null
    }

    val categories: List<String> get() = all.value.map { it.category }.distinct().sorted()
}
