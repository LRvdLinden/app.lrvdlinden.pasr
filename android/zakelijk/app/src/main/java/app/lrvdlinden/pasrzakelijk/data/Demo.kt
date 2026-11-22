package app.lrvdlinden.pasrzakelijk.data

import java.util.Calendar
import java.util.Date
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Voorbeeldgegevens voor de schermafbeeldingen (previews in CI). Staat [enabled] uit (altijd in de app zelf),
 * dan wordt hier niets van gebruikt.
 */
object Demo {
    @Volatile var enabled = false

    val business = Business(
        id = "demo", name = "Koffiebar De Boon", city = "Apeldoorn", email = "info@deboon.nl", website = "deboon.nl",
        status = BusinessStatus.approved, role = BusinessRole.owner, cooldownMinutes = 5, maxPerScan = 10,
        listed = true, address = "Hoofdstraat 12, Apeldoorn",
        cards = listOf(
            BusinessCard("c1", "Koffiekaart", null, "#7B4B2A", null, 10, "1 gratis koffie", true, 214, 1873, 142),
            BusinessCard("c2", "Lunchkaart", null, "#2ED3A6", null, 8, "Gratis tosti", true, 87, 402, 31),
            BusinessCard("c3", "Gebakkaart", null, "#FF6B57", null, 6, "Gratis appeltaart", false, 0, 0, 0),
        ),
    )

    val scan = ScanResult(
        code = "PZAC23XHB38EEJ4E", suffix = "EJ4E", business = business.name, cardName = "Koffiekaart", color = "#7B4B2A",
        textColor = null, logo = null, stampsTotal = 10, reward = "1 gratis koffie", stamps = 7, rewardsRedeemed = 2,
        lastStampAt = Date(System.currentTimeMillis() - 3 * 86_400_000L), cooldownUntil = null, undoEventID = null,
        maxPerScan = 10, canRedeem = false,
    )

    val stats: List<DayStat> by lazy {
        val cal = Calendar.getInstance()
        (59 downTo 0).map { back ->
            val d = (cal.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, -back) }
            val weekday = d.get(Calendar.DAY_OF_WEEK)
            val weekend = weekday == Calendar.SATURDAY || weekday == Calendar.SUNDAY
            val base = 34 + 10 * sin(back / 4.0) + (if (weekend) 18 else 0) + (59 - back) * 0.25
            DayStat(d.time, base.roundToInt(), (base / 9).roundToInt(), (base / 6).roundToInt())
        }
    }

    val staff = listOf(
        StaffMember("s0", "Anna de Vries", "anna@deboon.nl", BusinessRole.owner, null, revoked = false, pending = false, expired = false),
        StaffMember("s1", "Sem", "sem@example.nl", BusinessRole.staff, null, revoked = false, pending = false, expired = false),
        StaffMember("s2", "Lotte", "lotte@example.nl", BusinessRole.staff, null, revoked = false, pending = true, expired = false),
        StaffMember("s3", "Daan", "", BusinessRole.staff, null, revoked = true, pending = false, expired = false),
    )

    val log: List<LogEvent> by lazy {
        val now = System.currentTimeMillis()
        listOf(
            LogEvent("l1", "stamp", 1, Date(now - 4 * 60_000), "Sem", "Koffiekaart", "EJ4E", "Android-telefoon", "staff", false),
            LogEvent("l2", "redeem", 1, Date(now - 26 * 60_000), "Anna", "Koffiekaart", "K7QP", "Android-tablet", "owner", false),
            LogEvent("l3", "undo", 1, Date(now - 47 * 60_000), "Sem", "Lunchkaart", "9MZX", "Android-telefoon", "staff", false),
            LogEvent("l4", "stamp", 2, Date(now - 49 * 60_000), "Sem", "Lunchkaart", "9MZX", "Android-telefoon", "staff", true),
            LogEvent("l5", "join", 1, Date(now - 3 * 3600_000), "", "Koffiekaart", "R2TA", null, "customer", false),
            LogEvent("l6", "stamp", 1, Date(now - 5 * 3600_000), "Anna", "Koffiekaart", "R2TA", "iPhone", "owner", false),
            LogEvent("l7", "claim", 1, Date(now - 26 * 3600_000), "", "Lunchkaart", "B8WE", null, "customer", false),
        )
    }
}
