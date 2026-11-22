package app.lrvdlinden.pasrzakelijk.core

import app.lrvdlinden.pasrzakelijk.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Kijkt of er op pasr.nl/zakelijk/download/ een nieuwere APK staat (geen Play Store). Leest pasr-zakelijk.json
 * (velden version, code) en geeft de nieuwe versie terug, of null. Hoogstens 1x per 12 uur; fouten zijn stil.
 */
object UpdateCheck {
    data class Update(val version: String, val code: Int)

    private val sources = listOf(
        "https://pasr.nl/zakelijk/download/pasr-zakelijk.json",
        "https://pasr.nl/download/pasr-zakelijk.json",
    )

    suspend fun check(): Update? = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        val cached = Prefs.string("update.json")
        val json = if (cached.isNotEmpty() && now - Prefs.long("update.checked_at") < 12 * 3600_000L) cached else {
            sources.firstNotNullOfOrNull { fetch(it) }?.also {
                Prefs.putString("update.json", it)
                Prefs.putLong("update.checked_at", now)
            }
        } ?: return@withContext null
        val j = runCatching { JSONObject(json) }.getOrNull() ?: return@withContext null
        val code = j.optInt("code", 0)
        if (code > BuildConfig.VERSION_CODE) Update(j.optString("version", ""), code) else null
    }

    private fun fetch(url: String): String? = runCatching {
        val c = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 8000; readTimeout = 8000; setRequestProperty("Cache-Control", "no-cache")
        }
        try { if (c.responseCode == 200) c.inputStream.bufferedReader().use { it.readText() }.takeIf { it.trim().startsWith("{") } else null }
        finally { c.disconnect() }
    }.getOrNull()
}
