package app.lrvdlinden.pasrzakelijk.push

import app.lrvdlinden.pasrzakelijk.core.Prefs
import app.lrvdlinden.pasrzakelijk.data.BusinessStore
import app.lrvdlinden.pasrzakelijk.data.CommunityRouter
import app.lrvdlinden.pasrzakelijk.data.DeviceRegistry
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Ontvangt FCM-berichten en nieuwe tokens. */
class PushService : FirebaseMessagingService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onNewToken(token: String) {
        Prefs.putString("push.token", token)
        // meteen opnieuw melden bij de server, ook binnen de 24-uursrem
        scope.launch { DeviceRegistry.register(force = true) }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val title = message.notification?.title ?: data["title"] ?: "Pasr Zakelijk"
        val body = message.notification?.body ?: data["body"] ?: return
        val type = data["type"]
        Push.show(this, title, body, data["business_id"], data["url"], type, data["campaign"])
        // nieuwe uitnodiging of antwoord voor een gezamenlijke actie: badge meteen bijwerken
        if (type != null && type in CommunityRouter.pushTypes) {
            scope.launch(Dispatchers.Main) { BusinessStore.current?.let { CommunityRouter.refreshCount(it) } }
        }
    }
}
