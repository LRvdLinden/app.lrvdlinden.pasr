package app.lrvdlinden.pasr.data

import android.graphics.Bitmap
import android.os.Build
import android.util.Base64
import app.lrvdlinden.pasr.BuildConfig
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/** Meldt bij het opstarten welke app, welk platform en welke versie dit toestel draait (voor de inzichten in het beheer). */
object DeviceRegistry {
    suspend fun registerIfNeeded(force: Boolean = false) {
        val user = Account.session.value?.userID ?: "-"
        val stamp = "${BuildConfig.VERSION_NAME}|${BuildConfig.VERSION_CODE}|$user"
        val fresh = nowMs() - Prefs.long("device.at") < 24 * 3_600_000 && Prefs.string("device.stamp") == stamp
        if (fresh && !force) return
        val body = JSONObject()
            .put("p_device", Prefs.deviceId)
            .put("p_app", "pasr")
            .put("p_platform", "android")
            .put("p_version", BuildConfig.VERSION_NAME)
            .put("p_build", BuildConfig.VERSION_CODE.toString())
            .put("p_os", "Android ${Build.VERSION.RELEASE}")
            .put("p_country", Account.deviceCountry ?: JSONObject.NULL)
        runCatching { Api.publicRpc("pasr_device_register", body) }.onSuccess {
            Prefs.setLong("device.at", nowMs())
            Prefs.setString("device.stamp", stamp)
        }
    }
}

/**
 * "Opslaan in Google Wallet" via de functie google-wallet. Zonder issuer-account (secrets) zegt de functie
 * available=false en verbergt de app de knop. Per kaart bewaart de app een sleutel; daarmee werkt een volgende
 * aanroep het object bij (wijzigingen, ook stempels).
 */
object GoogleWallet {
    @Volatile private var available: Boolean? = null

    suspend fun isAvailable(): Boolean {
        available?.let { return it }
        val cached = Prefs.long("gw.checked")
        if (nowMs() - cached < 6 * 3_600_000) return Prefs.bool("gw.available").also { available = it }
        val ok = runCatching { Api.function("google-wallet", JSONObject().put("action", "status")).optBoolean("available") }.getOrDefault(false)
        Prefs.setBool("gw.available", ok); Prefs.setLong("gw.checked", nowMs())
        available = ok
        return ok
    }

    fun hasPass(card: Card) = Prefs.string("gw.key.${card.id.lowercase()}") != null

    private fun cardJson(card: Card): JSONObject = JSONObject().apply {
        put("id", card.id.lowercase()); put("name", card.storeName.ifBlank { card.kind.title }); put("number", card.number)
        put("format", card.formatRaw); put("kind", card.kindRaw); put("colorHex", card.colorHex)
        card.balance?.let { put("balance", it) }; card.currencyCode?.let { put("currency", it) }
        card.expiresAt?.let { put("expiresAt", isoOf(it)) }
        card.note.nilIfBlank()?.let { put("note", it.take(500)) }
        card.pin?.let { put("pin", it) }
        put("details", DetailsJson.toJson(card.details))
        logoPng(card)?.let { put("logo", it) }
    }

    private fun logoPng(card: Card): String? {
        val bmp = Catalog.logo(card) ?: return null
        val scaled = if (bmp.width > 360) Bitmap.createScaledBitmap(bmp, 360, (bmp.height * 360f / bmp.width).toInt().coerceAtLeast(1), true) else bmp
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray().takeIf { it.size < 200_000 }?.let { Base64.encodeToString(it, Base64.NO_WRAP) }
    }

    /** Maakt of werkt het object bij; geeft de "Opslaan in Google Wallet"-link. */
    suspend fun saveLink(card: Card): String {
        val keyName = "gw.key.${card.id.lowercase()}"
        val body = JSONObject().put("action", "save").put("card", cardJson(card))
        Prefs.string(keyName)?.let { body.put("key", it) }
        val r = Api.function("google-wallet", body)
        val url = r.str("url") ?: throw PasrError("Google Wallet is nu niet beschikbaar. Probeer het later opnieuw.")
        r.str("key")?.let { Prefs.setString(keyName, it) }
        return url
    }

    /** Na een wijziging: alleen als de kaart al in Google Wallet staat. Stil (fouten worden genegeerd). */
    suspend fun updateIfSaved(card: Card) {
        if (!hasPass(card) || !isAvailable()) return
        runCatching { saveLink(card) }
    }

    suspend fun removeIfSaved(card: Card) {
        val keyName = "gw.key.${card.id.lowercase()}"
        val key = Prefs.string(keyName) ?: return
        runCatching { Api.function("google-wallet", JSONObject().put("action", "remove").put("id", card.id.lowercase()).put("key", key)) }
        Prefs.setString(keyName, null)
    }
}
