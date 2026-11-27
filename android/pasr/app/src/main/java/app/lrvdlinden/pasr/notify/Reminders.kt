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
import app.lrvdlinden.pasr.data.Birthday
import app.lrvdlinden.pasr.data.ReminderPreferences
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
    const val CHANNEL_NEARBY = "nearby"

    fun setup(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = context.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Herinneringen", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Cadeaukaarten en kortingscodes die bijna verlopen, abonnementen die verlengen"
            })
            nm.createNotificationChannel(NotificationChannel(CHANNEL_STAMPS, "Stempelkaarten", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Een stempel erbij of je stempelkaart is vol"
            })
            nm.createNotificationChannel(NotificationChannel(CHANNEL_NEARBY, "Kaart tonen bij de winkel", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Alleen bij een bewaard filiaal en alleen na GPS-verificatie"
            })
            nm.createNotificationChannel(NotificationChannel(CHANNEL_NEWS, "Nieuws over mijn kaarten", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Berichten van Pasr over winkels waarvan je een kaart hebt"
            })
        }
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            "pasr-reminders-hourly", ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<LocalReminderWorker>(1, TimeUnit.HOURS).build(),
        )
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
        if (!Prefs.remindersEnabled || !canNotify(context)) return
        val localTime = java.time.LocalTime.now()
        if (ReminderPreferences.channel != "mail") {
            Birthday.notifyIfDue(context)
            if (localTime.hour >= 10 && ReminderPreferences.balance) notifyBalance(context)
            if (ReminderPreferences.expiry && localTime >= java.time.LocalTime.of(9, 30)) {
                for (card in CardStore.visible) {
                    val name = card.storeName.ifBlank { card.kind.title }
                    if (card.kind.hasExpiry) card.expiresAt?.let { expiry ->
                        val days = daysUntil(expiry)
                        val code = card.kind == CardKind.CODE
                        val subject = if (code) "Kortingscode $name" else name
                        val balance = card.balance?.takeIf { card.kind == CardKind.VOUCHER }
                            ?.let { money(it, card.currencyCode) }
                        when (days) {
                            7L -> once(context, "exp7-${card.id}-$expiry", "$subject verloopt over een week",
                                balance?.let { "Je hebt nog $it tegoed. Gebruik je kaart op tijd." }
                                    ?: if (code) "Gebruik je code op tijd." else "Gebruik je kaart op tijd.", card)
                            0L -> once(context, "exp0-${card.id}-$expiry", "$subject verloopt vandaag",
                                balance?.let { "Laatste dag om je $it te gebruiken." }
                                    ?: if (code) "Laatste dag om je code te gebruiken." else "Laatste dag om je kaart te gebruiken.", card)
                        }
                    }
                    if (card.kind == CardKind.SUBSCRIPTION) card.details.renewsAt?.let { renews ->
                        if (daysUntil(renews) == 2L) once(context, "renew-${card.id}-$renews", "$name verlengt over 2 dagen",
                            card.details.cost?.let { "Je betaalt dan ${money(it, card.currencyCode)}. Opzeggen? Doe het op tijd." }
                                ?: "Opzeggen? Doe het op tijd.", card)
                    }
                }
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

    private fun money(amount: Double, currency: String?): String =
        java.text.NumberFormat.getCurrencyInstance(java.util.Locale("nl", "NL")).apply {
            currency?.let { runCatching { this.currency = java.util.Currency.getInstance(it) } }
        }.format(amount)

    private fun notifyBalance(context: Context) {
        val date = LocalDate.now()
        val due = when (ReminderPreferences.interval) {
            "week" -> date.dayOfWeek == java.time.DayOfWeek.SATURDAY
            "quarter" -> date.dayOfMonth == 1 && (date.monthValue - 1) % 3 == 0
            else -> date.dayOfMonth == 1
        }
        if (!due) return
        val cards = CardStore.visible.filter { it.kind == CardKind.VOUCHER && !it.isExpired && (it.balance ?: 0.0) > 0.0 }
        val first = cards.firstOrNull() ?: return
        val key = "note.balance.$date"
        if (Prefs.bool(key)) return
        val currencies = cards.map { it.currencyCode ?: "EUR" }.distinct()
        val title = when {
            cards.size == 1 -> "Je hebt nog ${money(first.balance ?: 0.0, first.currencyCode)} bij ${first.storeName}"
            currencies.size == 1 -> "Je hebt nog ${money(cards.sumOf { it.balance ?: 0.0 }, currencies.single())} tegoed op ${cards.size} cadeaukaarten"
            else -> "Je hebt nog tegoed op ${cards.size} cadeaukaarten"
        }
        val body = if (cards.size == 1) "Vergeet je cadeaukaart niet." else {
            val top = cards.sortedByDescending { it.balance }.take(3)
                .joinToString(", ") { "${it.storeName} ${money(it.balance ?: 0.0, it.currencyCode)}" }
            top + if (cards.size > 3) " en ${cards.size - 3} meer" else ""
        }
        notify(context, key, CHANNEL, title, body, first.id.takeIf { cards.size == 1 })
        Prefs.setBool(key, true)
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

class LocalReminderWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        Reminders.check(applicationContext)
        return Result.success()
    }
}

class DailyWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val before = CardStore.visible.filter { it.isBusinessStamps }.associate { it.id to it.details.stampsFull }
        for (c in Business.refreshAll(force = true)) {
            // met push meldt de server het al (stempel erbij of vol); anders een lokale melding
            if (!Push.hasToken && before[c.id] == false && c.details.stampsFull) Reminders.stampsFull(applicationContext, c)
            GoogleWallet.updateIfSaved(c)
        }
        return Result.success()
    }
}
