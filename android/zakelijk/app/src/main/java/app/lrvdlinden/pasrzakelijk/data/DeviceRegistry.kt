package app.lrvdlinden.pasrzakelijk.data

import android.content.Context
import android.os.Build
import app.lrvdlinden.pasrzakelijk.BuildConfig
import app.lrvdlinden.pasrzakelijk.core.Prefs
import org.json.JSONObject
import java.util.Locale
import java.util.UUID

/**
 * Meldt platform en appversie van dit toestel bij de server (voor de inzichten in het beheer: apparaten per platform,
 * versies, actieve apparaten). Contract van ANDROID-PASR (features-android.md, blok `-- android 1.0`):
 * pasr_device_register(p_device, p_app 'zakelijk', p_platform 'android', p_version, p_build, p_os, p_country).
 * Bij start hoogstens 1x per 24 uur, en meteen na inloggen/uitloggen of als versie/build verandert.
 * Mislukt het, dan gebeurt er niets (nooit een fout in beeld).
 */
object DeviceRegistry {
    fun init(@Suppress("UNUSED_PARAMETER") context: Context) {}

    /** Willekeurig id per installatie (UUID zonder streepjes); geen hardware-id. */
    val installId: String
        get() {
            val existing = Prefs.string("device.install_id")
            if (existing.isNotEmpty()) return existing
            val new = UUID.randomUUID().toString().replace("-", "")
            Prefs.putString("device.install_id", new)
            return new
        }

    suspend fun register() {
        // opnieuw bij een andere versie/build of een ander account (inloggen/uitloggen), anders 1x per 24 uur
        val stamp = "${BuildConfig.VERSION_NAME}-${BuildConfig.VERSION_CODE}-${Account.session?.userID ?: "-"}"
        val last = Prefs.long("device.registered_at")
        if (Prefs.string("device.registered_for") == stamp && System.currentTimeMillis() - last < 24 * 3600_000L) return
        val country = Locale.getDefault().country.takeIf { it.length == 2 }
        val body = JSONObject()
            .put("p_device", installId)
            .put("p_app", "zakelijk")
            .put("p_platform", "android")
            .put("p_version", BuildConfig.VERSION_NAME)
            .put("p_build", BuildConfig.VERSION_CODE.toString())
            .put("p_os", "Android ${Build.VERSION.RELEASE}".take(40))
            .put("p_country", country ?: JSONObject.NULL)
        val ok = runCatching {
            if (Account.isSignedIn) Account.rpc(RPC, body) else Account.rpcAnon(RPC, body)
        }.isSuccess
        if (ok) {
            Prefs.putString("device.registered_for", stamp)
            Prefs.putLong("device.registered_at", System.currentTimeMillis())
        }
    }

    /** Bij account verwijderen: dit toestel afmelden. */
    suspend fun unregister() {
        runCatching { Account.rpcAnon("pasr_device_unregister", JSONObject().put("p_device", installId)) }
        Prefs.putString("device.registered_for", "")
    }

    const val RPC = "pasr_device_register"
}
