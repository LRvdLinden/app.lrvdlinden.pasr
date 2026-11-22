package app.lrvdlinden.pasrzakelijk.ui

import app.lrvdlinden.pasrzakelijk.core.I18n
import app.lrvdlinden.pasrzakelijk.core.L
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Datums en tijdsduur in de taal van de app. */
object Fmt {
    val locale: Locale get() = if (I18n.dutch) Locale("nl", "NL") else Locale.UK
    private val zone: TimeZone = TimeZone.getTimeZone("Europe/Amsterdam")

    fun pattern(p: String, date: Date): String = SimpleDateFormat(p, locale).apply { timeZone = zone }.format(date)

    /** "4 min", "2 uur", "3 dagen" (afgerond). */
    fun duration(seconds: Long): String {
        val s = maxOf(0L, seconds)
        return when {
            s < 60 -> L("%lld s", s)
            s < 3600 -> L("%lld min", (s + 59) / 60)
            s < 86_400 -> L("%lld uur", s / 3600)
            s < 2 * 86_400 -> L("1 dag")
            else -> L("%lld dagen", s / 86_400)
        }
    }

    /** Hoe lang geleden (voor "Laatste stempel … geleden"). */
    fun ago(date: Date): String = duration((System.currentTimeMillis() - date.time) / 1000)

    /** "over 4 min" (voor de afkoeltijd). */
    fun until(date: Date): String = L("over %@", duration((date.time - System.currentTimeMillis()) / 1000))

    fun dayMonth(date: Date) = pattern("d MMM", date)
    fun dayMonthYear(date: Date) = pattern("d MMM yyyy", date)
    fun dayMonthTime(date: Date) = pattern("d MMM HH:mm", date)
    fun weekdayDayMonth(date: Date) = pattern("EEEE d MMMM", date)

    fun clock(seconds: Long): String {
        val s = maxOf(0L, seconds)
        return String.format(Locale.US, "%d:%02d", s / 60, s % 60)
    }
}
