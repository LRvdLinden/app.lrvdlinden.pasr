package app.lrvdlinden.pasr.notify

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import app.lrvdlinden.pasr.MainActivity
import app.lrvdlinden.pasr.R
import app.lrvdlinden.pasr.data.Prefs
import app.lrvdlinden.pasr.data.PurchaseCapture
import app.lrvdlinden.pasr.data.UseCapture
import app.lrvdlinden.pasr.ui.euro

/**
 * Aankopen vanzelf vastleggen op Android (opt-in, standaard uit). Android kent geen Opdrachten-automatisering, dus leest
 * Pasr met jouw toestemming ("Toegang tot meldingen") alleen betaalmeldingen: van Google Wallet en bekende bank-apps,
 * en van andere apps alleen als er een €-bedrag én een betaalwoord in staat. Daaruit haalt Pasr de winkel en het bedrag,
 * verder niets. Alles op het toestel: de melding wordt niet bewaard of verstuurd, de winkelnaam ook niet. Past er een
 * kaart, dan komt er een moment met het bedrag in Laatst gebruikt (cadeaukaart: eerst bevestigen). Geen kaart: niets.
 */
class PaymentListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val n = sbn ?: return
        if (!UseCapture.payCapture) return
        if (n.packageName == packageName) return
        if (n.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val extras = n.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()
        val known = n.packageName in PurchaseCapture.knownPayApps
        val payment = PurchaseCapture.parse(n.packageName, title, text, known) ?: return
        // dezelfde melding (bijgewerkt of opnieuw geplaatst) maar één keer
        val key = "pay.last"
        val fingerprint = "${n.packageName}|${payment.merchant}|${payment.amount}|${n.postTime / 60_000}"
        if (Prefs.string(key) == fingerprint) return
        Prefs.setString(key, fingerprint)
        val outcome = PurchaseCapture.record(payment.merchant, payment.amount, at = n.postTime)
        val card = outcome.card ?: return
        val pending = outcome.pending ?: return
        val useId = outcome.useId ?: return
        askToBook(this, card.id, useId, card.storeName, pending, card.currencyCode)
    }

    companion object {
        const val CHANNEL = "purchases"
        const val ACTION_BOOK = "app.lrvdlinden.pasr.PAY_BOOK"
        const val ACTION_SKIP = "app.lrvdlinden.pasr.PAY_SKIP"

        fun isGranted(context: Context): Boolean {
            val flat = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: return false
            val me = ComponentName(context, PaymentListener::class.java).flattenToString()
            return flat.split(':').any { it.equals(me, ignoreCase = true) }
        }

        /** Android-instellingen › Toegang tot meldingen (aan- of uitzetten). */
        fun settingsIntent(context: Context): Intent =
            if (Build.VERSION.SDK_INT >= 30) Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, ComponentName(context, PaymentListener::class.java).flattenToString())
            else Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")

        fun askToBook(context: Context, cardId: String, useId: String, store: String, amount: Double, currency: String?) {
            if (!Reminders.canNotify(context)) return
            if (Build.VERSION.SDK_INT >= 26) {
                context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                    NotificationChannel(CHANNEL, "Aankopen", NotificationManager.IMPORTANCE_DEFAULT).apply {
                        description = "Bedrag van een cadeaukaart afboeken na een betaling"
                    })
            }
            val id = useId.hashCode()
            fun action(a: String) = PendingIntent.getBroadcast(context, (a + useId).hashCode(),
                Intent(context, PayActionReceiver::class.java).setAction(a).putExtra("cardId", cardId).putExtra("useId", useId)
                    .putExtra("notification", id),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val open = PendingIntent.getActivity(context, id, Intent(context, MainActivity::class.java).putExtra("cardId", cardId)
                .setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val money = euro(amount, currency)
            val n = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_card)
                .setContentTitle("$money afboeken van $store?")
                .setContentText("Je betaalde net $money. Boek het af van je cadeaukaart in Pasr.")
                .setAutoCancel(true)
                .setContentIntent(open)
                .addAction(0, "Afboeken", action(ACTION_BOOK))
                .addAction(0, "Niet afboeken", action(ACTION_SKIP))
                .build()
            runCatching { NotificationManagerCompat.from(context).notify(id, n) }
        }
    }
}

/** "Afboeken" of "Niet afboeken" onder de melding. */
class PayActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val cardId = intent.getStringExtra("cardId") ?: return
        val useId = intent.getStringExtra("useId") ?: return
        // PasrApp.onCreate heeft de opslag al geopend (ook als alleen deze ontvanger start)
        when (intent.action) {
            PaymentListener.ACTION_BOOK -> PurchaseCapture.book(cardId, useId)
            PaymentListener.ACTION_SKIP -> PurchaseCapture.skip(cardId, useId)
        }
        NotificationManagerCompat.from(context).cancel(intent.getIntExtra("notification", 0))
    }
}
