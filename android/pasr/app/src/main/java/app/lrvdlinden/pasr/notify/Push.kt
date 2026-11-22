package app.lrvdlinden.pasr.notify

import android.content.Context
import app.lrvdlinden.pasr.data.Business
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.DeviceRegistry
import app.lrvdlinden.pasr.data.GoogleWallet
import app.lrvdlinden.pasr.data.Prefs
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * Pushmeldingen via Firebase Cloud Messaging. Het token gaat met pasr_device_register naar de server (provider fcm),
 * samen met "Nieuws over mijn kaarten", de winkel-id's van je kaarten en de klantcodes van zakelijke stempelkaarten.
 * Zonder google-services.json in de build is er geen Firebase: dan alleen lokale herinneringen.
 */
object Push {
    fun available(context: Context): Boolean = runCatching { FirebaseApp.getApps(context).isNotEmpty() }.getOrDefault(false)

    /** Het huidige FCM-token (of null zonder Firebase of netwerk). */
    suspend fun token(context: Context): String? {
        if (!available(context)) return null
        Prefs.string("fcm.token")?.let { return it }
        return suspendCancellableCoroutine { cont ->
            runCatching {
                FirebaseMessaging.getInstance().token
                    .addOnSuccessListener { t -> Prefs.setString("fcm.token", t); if (cont.isActive) cont.resume(t) }
                    .addOnFailureListener { if (cont.isActive) cont.resume(null) }
            }.onFailure { if (cont.isActive) cont.resume(null) }
        }
    }

    val hasToken: Boolean get() = Prefs.string("fcm.token") != null
}

class PasrMessagingService : FirebaseMessagingService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onNewToken(token: String) {
        Prefs.setString("fcm.token", token)
        scope.launch { DeviceRegistry.registerIfNeeded(applicationContext, force = true) }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val d = message.data
        val title = d["title"] ?: message.notification?.title ?: "Pasr"
        val body = d["body"] ?: message.notification?.body ?: return
        when (d["kind"]) {
            "stamps" -> {
                val code = d["code"]?.uppercase()
                val card = CardStore.visible.firstOrNull { it.details.memberCode?.uppercase() == code }
                Reminders.notify(applicationContext, "stamps-${code ?: title}", Reminders.CHANNEL_STAMPS, title, body, card?.id)
                // stand meteen ophalen (en de pas in Google Wallet bijwerken)
                if (card != null) scope.launch { Business.refresh(card)?.let { GoogleWallet.updateIfSaved(it) } }
            }
            else -> {
                // nieuws (met of zonder winkel) of een nieuwe winkel: tik opent de kaart van die winkel, anders Kaart toevoegen
                // met een https-link (bericht uit het beheer) opent een tik die link
                val store = d["store"]?.lowercase()
                val card = store?.let { s -> CardStore.visible.firstOrNull { it.templateID?.lowercase() == s } }
                val url = d["url"]?.takeIf { it.startsWith("https://", ignoreCase = true) && it.length <= 500 }
                Reminders.notify(applicationContext, "news-${d["id"] ?: title}", Reminders.CHANNEL_NEWS, title, body, card?.id,
                    store = if (card == null) store else null, url = if (store == null) url else null)
            }
        }
    }
}
