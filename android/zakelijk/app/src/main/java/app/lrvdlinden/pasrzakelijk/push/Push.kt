package app.lrvdlinden.pasrzakelijk.push

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import app.lrvdlinden.pasrzakelijk.MainActivity
import app.lrvdlinden.pasrzakelijk.R
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.core.Prefs
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * Pushmeldingen via Firebase Cloud Messaging. Het token gaat met het apparaatcontract (pasr_device_register) naar de
 * server; de server (ANDROID-PASR) verstuurt de meldingen. Zonder google-services.json in de build is er geen Firebase
 * en doet dit niets.
 */
object Push {
    const val CHANNEL = "zakelijk"
    const val EXTRA_BUSINESS = "pasr.business_id"
    const val EXTRA_URL = "pasr.url"
    /** https-link uit een getikte melding die de app zelf niet kent; AppShell opent hem in Custom Tabs na het slot. */
    val pendingWeb = kotlinx.coroutines.flow.MutableStateFlow<android.net.Uri?>(null)

    fun isAvailable(context: Context): Boolean = runCatching { FirebaseApp.getApps(context).isNotEmpty() }.getOrDefault(false)

    /** Laatst bekende token (ook bewaard door onNewToken). */
    val savedToken: String get() = Prefs.string("push.token")

    suspend fun token(context: Context): String? {
        if (!isAvailable(context)) return null
        val fresh = runCatching {
            suspendCancellableCoroutine<String?> { cont ->
                FirebaseMessaging.getInstance().token
                    .addOnSuccessListener { cont.resume(it) }
                    .addOnFailureListener { cont.resume(null) }
            }
        }.getOrNull()
        if (!fresh.isNullOrBlank()) Prefs.putString("push.token", fresh)
        return fresh ?: savedToken.ifEmpty { null }
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(CHANNEL, "Pasr Zakelijk", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = L("Meldingen over je zaak, zoals goedkeuring en medewerkers.")
        }
        manager.createNotificationChannel(channel)
    }

    fun needsPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED

    /** Melding tonen (ook als de app open is). */
    fun show(context: Context, title: String, body: String, businessId: String?, url: String?) {
        val link = url?.takeIf { (it.startsWith("https://", ignoreCase = true) || it.startsWith("pasrzakelijk://")) && it.length <= 500 }
        ensureChannel(context)
        if (needsPermission(context)) return
        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            businessId?.let { putExtra(EXTRA_BUSINESS, it) }
            link?.let { putExtra(EXTRA_URL, it) }
        }
        val pending = PendingIntent.getActivity(
            context, (System.currentTimeMillis() and 0xFFFFFF).toInt(), open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_pasr)
            .setColor(0xFF2ED3A6.toInt())
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), n) }
    }
}
