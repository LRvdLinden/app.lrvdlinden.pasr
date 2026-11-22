package app.lrvdlinden.pasrzakelijk.data

import android.content.Context
import android.os.Build
import app.lrvdlinden.pasrzakelijk.BuildConfig
import app.lrvdlinden.pasrzakelijk.core.I18n
import app.lrvdlinden.pasrzakelijk.core.Prefs
import org.json.JSONObject
import java.util.UUID

/**
 * Meldt platform en appversie van dit toestel bij de server (voor de inzichten in het beheer: accounts en apparaten
 * per platform, versies, actieve apparaten). Contract van agent ANDROID-PASR, zie features-android.md.
 * Mislukt het, dan gebeurt er niets (nooit een fout in beeld).
 */
object DeviceRegistry {
    private var appContext: Context? = null

    fun init(context: Context) { appContext = context.applicationContext }

    /** Willekeurig id per installatie; geen hardware-id. */
    val installId: String
        get() {
            val existing = Prefs.string("device.install_id")
            if (existing.isNotEmpty()) return existing
            val new = UUID.randomUUID().toString()
            Prefs.putString("device.install_id", new)
            return new
        }

    suspend fun register() {
        if (!Account.isSignedIn) return
        // hoogstens één keer per 6 uur per versie
        val stamp = "${BuildConfig.VERSION_NAME}-${BuildConfig.VERSION_CODE}-${Account.session?.userID}"
        val last = Prefs.long("device.registered_at")
        if (Prefs.string("device.registered_for") == stamp && System.currentTimeMillis() - last < 6 * 3600_000L) return
        val body = JSONObject()
            .put("p_install_id", installId)
            .put("p_app", "pasr-zakelijk")
            .put("p_platform", "android")
            .put("p_version", BuildConfig.VERSION_NAME)
            .put("p_build", BuildConfig.VERSION_CODE.toString())
            .put("p_os_version", Build.VERSION.RELEASE ?: "")
            .put("p_device", BusinessApi.deviceName)
            .put("p_locale", I18n.languageCode)
        val ok = runCatching { Account.rpc(RPC, body) }.isSuccess
        if (ok) {
            Prefs.putString("device.registered_for", stamp)
            Prefs.putLong("device.registered_at", System.currentTimeMillis())
        }
    }

    const val RPC = "pasr_device_register"
}
