package app.lrvdlinden.pasr.notify

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
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.lrvdlinden.pasr.MainActivity
import app.lrvdlinden.pasr.R
import app.lrvdlinden.pasr.data.Business
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.CardKind
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.GoogleWallet
import app.lrvdlinden.pasr.data.Prefs
import app.lrvdlinden.pasr.data.nowMs
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.concurrent.TimeUnit

/**
 * Lokale meldingen (geen push op Android: er is geen Firebase-project). Elke dag rond de ochtend kijkt Pasr of een
 * cadeaukaart of kortingscode bijna verloopt (7 dagen ervoor en op de dag), of een abonnement over 2 dagen verlengt,
 * en of een zakelijke stempelkaart vol is.
 */
object Reminders {
    const val CHANNEL = "reminders"
    const val CHANNEL_STAMPS = "stamps"
    const val CHANNEL_NEWS = "news"

    fun setup(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = context.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Herinneringen", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Cadeaukaarten en kortingscodes die bijna verlopen, abonnementen die verlengen"
            })
            nm.createNotificationChannel(NotificationChannel(CHANNEL_STAMPS, "Stempelkaarten", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Een stempel erbij of je stempelkaart is vol"
            })
            nm.createNotificationChannel(NotificationChannel(CHANNEL_NEWS, "Nieuws over mijn kaarten", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Berichten van Pasr over winkels waarvan je een kaart hebt"
            })
        }
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            "pasr-daily", ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<DailyWorker>(12, TimeUnit.HOURS).build(),
        )
    }

    fun canNotify(context: Context) = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun notify(context: Context, id: String, channel: String, title: String, text: String, cardId: String?, store: String? = null,
               url: String? = null, receipt: String? = null) {
        if (!canNotify(context)) return
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            cardId?.let { putExtra("cardId", it) }
            store?.let { putExtra("store", it) }
            url?.let { putExtra("url", it) }
            receipt?.let { putExtra("receipt", it); removeExtra("cardId") }
        }
        val pi = PendingIntent.getActivity(context, id.hashCode(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_stat_card)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(id.hashCode(), n) }
    }

    private fun daysUntil(ms: Long): Long {
        val zone = ZoneId.systemDefault()
        return ChronoUnit.DAYS.between(LocalDate.now(zone), Instant.ofEpochMilli(ms).atZone(zone).toLocalDate())
    }

    /** Wat er vandaag te melden is; elke melding hoogstens één keer (sleutel in de instellingen). */
    fun check(context: Context) {
        if (!Prefs.remindersEnabled) return
        for (c in CardStore.visible) {
            val name = c.storeName.ifBlank { c.kind.title }
            if (c.kind.hasExpiry) c.expiresAt?.let { e ->
                val d = daysUntil(e)
                val what = if (c.kind == CardKind.VOUCHER) "Je cadeaukaart van $name" else "Je kortingscode van $name"
                when (d) {
                    7L -> once(context, "exp7-${c.id}-$e", what, "$what verloopt over 7 dagen.", c)
                    0L -> once(context, "exp0-${c.id}-$e", what, "$what verloopt vandaag. Gebruik hem nog!", c)
                }
            }
            if (c.kind == CardKind.SUBSCRIPTION) c.details.renewsAt?.let { r ->
                if (daysUntil(r) == 2L) once(context, "renew-${c.id}-$r", "Abonnement $name", "Je abonnement bij $name verlengt over 2 dagen.", c)
            }
        }
        // bonnetjes: een maand voordat de garantie afloopt (en tot een week erna nog, als de telefoon uit stond)
        for (r in app.lrvdlinden.pasr.data.ReceiptStore.receipts.value) {
            val until = r.warrantyUntil ?: continue
            val d = daysUntil(until)
            if (d in 23L..31L) {
                val k = "note.warranty-${r.id}-$until"
                if (Prefs.bool(k)) continue
                Prefs.setBool(k, true)
                val what = r.title.ifBlank { r.storeName }
                notify(context, "warranty-${r.id}", CHANNEL, "Garantie loopt over een maand af",
                    "De garantie op $what (${r.storeName}) loopt tot ${app.lrvdlinden.pasr.ui.dateText(until)}. Je bon staat in Pasr.",
                    r.cardID, receipt = r.id)
            }
        }
    }

    private fun once(context: Context, key: String, title: String, text: String, card: Card) {
        val k = "note.$key"
        if (Prefs.bool(k)) return
        Prefs.setBool(k, true)
        notify(context, key, CHANNEL, title, text, card.id)
    }

    fun stampsFull(context: Context, card: Card) {
        val reward = card.details.reward?.takeIf { it.isNotBlank() }
        notify(context, "full-${card.id}-${nowMs() / 3_600_000}", CHANNEL_STAMPS, "Je stempelkaart van ${card.storeName} is vol",
            reward?.let { "Wissel je beloning in: $it." } ?: "Wissel je beloning in bij je volgende bezoek.", card.id)
    }
}

class DailyWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        Reminders.check(applicationContext)
        val before = CardStore.visible.filter { it.isBusinessStamps }.associate { it.id to it.details.stampsFull }
        for (c in Business.refreshAll(force = true)) {
            // met push meldt de server het al (stempel erbij of vol); anders een lokale melding
            if (!Push.hasToken && before[c.id] == false && c.details.stampsFull) Reminders.stampsFull(applicationContext, c)
            GoogleWallet.updateIfSaved(c)
        }
        return Result.success()
    }
}
