package app.lrvdlinden.pasrzakelijk.data

import android.net.Uri
import app.lrvdlinden.pasrzakelijk.core.L
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

// Tickets (gratis events) en klantenkaarten met barcode. Zelfde databasefuncties en regels als TicketsAPI.swift.

object TkFormat {
    val zone: TimeZone = TimeZone.getTimeZone("Europe/Amsterdam")
    private fun fmt(p: String) = SimpleDateFormat(p, Locale.US).apply { timeZone = zone; isLenient = false }

    fun day(d: Date): String = fmt("yyyy-MM-dd").format(d)
    fun time(d: Date): String = fmt("HH:mm").format(d)
    fun timestamp(d: Date): String = fmt("yyyy-MM-dd'T'HH:mm:ssXXX").format(d)
    fun parseDay(s: String?): Date? = s?.take(10)?.let { runCatching { fmt("yyyy-MM-dd").parse(it) }.getOrNull() }
    /** "17:00" of "17:00:00" → tijdstip op 1 jan 1970 (alleen uur en minuut tellen). */
    fun parseTime(s: String?): Date? = s?.take(5)?.let { runCatching { fmt("HH:mm").parse(it) }.getOrNull() }

    fun calendar(d: Date = Date()): Calendar = Calendar.getInstance(zone).apply { time = d }

    fun percent(p: Double): String = if (p % 1.0 == 0.0) p.toLong().toString() else String.format(Locale.US, "%.1f", p)
}

data class TicketType(
    val key: String = UUID.randomUUID().toString(),
    val serverId: String = "",
    val name: String = "",
    val capacity: Int? = null,
) {
    fun payload(): JSONObject = JSONObject().apply {
        put("name", name.trim())
        put("capacity", capacity ?: JSONObject.NULL)
        if (serverId.isNotEmpty()) put("id", serverId)
    }

    companion object {
        fun from(j: J) = TicketType(serverId = j.string("id") ?: "", name = j.string("name") ?: "", capacity = j.int("capacity"))
    }
}

data class TicketEvent(
    val id: String = "",
    val name: String = "",
    val description: String = "",
    val startsAt: Date = defaultStart(),
    val endsAt: Date = Date(defaultStart().time + 3 * 3600_000L),
    val doorsAt: Date? = null,
    val address: String = "",
    val lat: Double? = null,
    val lng: Double? = null,
    val capacity: Int = 100,
    val maxPerPerson: Int = 4,
    val signupUntil: Date? = null,
    val waitlist: Boolean = true,
    val color: String? = null,
    val headerUrl: String? = null,
    val status: String = "draft",
    val ticketTypes: List<TicketType> = listOf(TicketType(name = L("Toegang"))),
    val registered: Int = 0,
    val checkedIn: Int = 0,
    val waiting: Int = 0,
) {
    val isPublished get() = status == "published"
    val isCancelled get() = status == "cancelled"
    val isPast get() = endsAt.before(Date())
    val addUrl get() = "https://pasr.nl/add/e/${id.lowercase()}"
    val spotsLeft get() = maxOf(0, capacity - registered)

    fun payload(newStatus: String): JSONObject = JSONObject().apply {
        put("name", name.trim())
        put("description", description)
        put("starts_at", TkFormat.timestamp(startsAt))
        put("ends_at", TkFormat.timestamp(endsAt))
        put("doors_at", doorsAt?.let { TkFormat.timestamp(it) } ?: JSONObject.NULL)
        put("address", address)
        put("lat", lat ?: JSONObject.NULL)
        put("lng", lng ?: JSONObject.NULL)
        put("capacity", capacity)
        put("max_per_person", maxPerPerson)
        put("signup_until", signupUntil?.let { TkFormat.timestamp(it) } ?: JSONObject.NULL)
        put("waitlist", waitlist)
        put("color", color ?: JSONObject.NULL)
        put("header_url", headerUrl?.takeIf { it.isNotBlank() } ?: JSONObject.NULL)
        put("status", newStatus)
        put("ticket_types", JSONArray(ticketTypes.filter { it.name.isNotBlank() }.map { it.payload() }))
        if (id.isNotEmpty()) put("id", id)
    }

    companion object {
        fun defaultStart(): Date = TkFormat.calendar().apply {
            add(Calendar.DAY_OF_MONTH, 14); set(Calendar.HOUR_OF_DAY, 16); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.time

        fun from(j: J): TicketEvent? {
            val id = j.string("id", "event_id") ?: return null
            val start = j.date("starts_at") ?: Date()
            // "waitlist" is bij opslaan ja/nee, in de lijst het aantal op de wachtlijst
            val rawWait = j.raw.opt("waitlist")
            val waitCount = if (rawWait is Number) rawWait.toInt() else j.int("waitlist_count", "waiting") ?: 0
            val waitOn = if (rawWait is Boolean) rawWait else j.bool("waitlist_enabled") ?: true
            var types = j.array("ticket_types").map { TicketType.from(it) }
            if (types.isEmpty()) (j.raw.opt("ticket_types") as? String)?.let { s ->
                runCatching { JSONArray(s) }.getOrNull()?.let { a -> types = a.objects().map { TicketType.from(it) } }
            }
            return TicketEvent(
                id = id, name = j.string("name") ?: "", description = j.string("description") ?: "",
                startsAt = start, endsAt = j.date("ends_at") ?: Date(start.time + 3 * 3600_000L), doorsAt = j.date("doors_at"),
                address = j.string("address") ?: "", lat = j.double("lat"), lng = j.double("lng"),
                capacity = j.int("capacity") ?: 0, maxPerPerson = j.int("max_per_person") ?: 4,
                signupUntil = j.date("signup_until"), waitlist = waitOn, color = j.string("color"), headerUrl = j.string("header_url"),
                status = (j.string("status") ?: "draft").lowercase(),
                ticketTypes = types.ifEmpty { listOf(TicketType(name = L("Toegang"))) },
                registered = j.int("registered") ?: 0, checkedIn = j.int("checked_in") ?: 0, waiting = waitCount,
            )
        }
    }
}

data class EventRegistration(
    val key: String,
    val ticketId: String,
    val firstName: String,
    val lastName: String,
    val email: String,
    val birthDate: Date?,
    val ticketType: String,
    val status: String,
    val createdAt: Date?,
    val checkedInAt: Date?,
) {
    val fullName get() = listOf(firstName, lastName).filter { it.isNotBlank() }.joinToString(" ")

    companion object {
        fun from(j: J, index: Int): EventRegistration {
            val ticket = j.string("ticket_id") ?: ""
            return EventRegistration(
                key = (j.string("registration_id") ?: "r$index") + "-" + ticket, ticketId = ticket,
                firstName = j.string("first_name") ?: "", lastName = j.string("last_name") ?: "", email = j.string("email") ?: "",
                birthDate = TkFormat.parseDay(j.string("birth_date")), ticketType = j.string("ticket_type") ?: "",
                status = (j.string("status") ?: "registered").lowercase(), createdAt = j.date("created_at"), checkedInAt = j.date("checked_in_at"),
            )
        }
    }
}

data class TicketScan(
    val code: String,
    val result: String,
    val firstName: String,
    val lastName: String,
    val ticketType: String,
    val eventId: String?,
    val eventName: String,
    val checkedInAt: Date?,
    val checkedIn: Int?,
    val registered: Int?,
    val capacity: Int?,
) {
    val isValid get() = result == "valid"
    val name get() = listOf(firstName, lastName).filter { it.isNotBlank() }.joinToString(" ")

    companion object {
        fun from(any: Any?, code: String): TicketScan? {
            val j = J.of(any) ?: return null
            val result = j.string("result", "status") ?: return null
            val counts = j.obj("counts")
            return TicketScan(
                code, result.lowercase(), j.string("first_name") ?: "", j.string("last_name") ?: "", j.string("ticket_type") ?: "",
                j.string("event_id"), j.string("event_name") ?: "", j.date("checked_in_at"),
                counts?.int("checked_in"), counts?.int("registered"), counts?.int("capacity"),
            )
        }
    }
}

// Klantenkaarten

data class DiscountPeriod(
    val key: String = UUID.randomUUID().toString(),
    val serverId: String? = null,
    val label: String = "",
    val percent: Double = 10.0,
    val startsOn: Date = TkFormat.calendar().apply { set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }.time,
    val endsOn: Date = Date(startsOn.time + 14 * 86_400_000L),
    /** 1 = ma … 7 = zo; leeg = elke dag. */
    val weekdays: Set<Int> = emptySet(),
    val fromTime: String? = null,
    val toTime: String? = null,
) {
    fun payload(): JSONObject = JSONObject().apply {
        put("label", label)
        put("percent", percent)
        put("starts_on", TkFormat.day(startsOn))
        put("ends_on", TkFormat.day(endsOn))
        put("weekdays", if (weekdays.isEmpty()) JSONObject.NULL else JSONArray(weekdays.sorted()))
        put("from_time", fromTime ?: JSONObject.NULL)
        put("to_time", toTime ?: JSONObject.NULL)
        serverId?.let { put("id", it) }
    }

    /** "1 dec – 15 dec · ma, di · 17:00–19:00 · 15%" */
    fun summary(): String {
        val parts = mutableListOf(TkText.dayMonth(startsOn) + " – " + TkText.dayMonth(endsOn))
        if (weekdays.isNotEmpty()) parts += weekdays.sorted().joinToString(", ") { TkText.weekday(it) }
        parts += if (fromTime != null && toTime != null) "$fromTime–$toTime" else L("hele dag")
        parts += TkFormat.percent(percent) + "%"
        return parts.joinToString(" · ")
    }

    companion object {
        fun from(j: J): DiscountPeriod {
            val start = TkFormat.parseDay(j.string("starts_on")) ?: Date()
            val days = (j.raw.opt("weekdays") as? JSONArray)?.let { a -> (0 until a.length()).mapNotNull { a.opt(it)?.toString()?.toIntOrNull() } } ?: emptyList()
            val id = j.string("id")
            return DiscountPeriod(
                key = id ?: UUID.randomUUID().toString(), serverId = id, label = j.string("label") ?: "", percent = j.double("percent") ?: 0.0,
                startsOn = start, endsOn = TkFormat.parseDay(j.string("ends_on")) ?: start, weekdays = days.toSet(),
                fromTime = j.string("from_time")?.take(5), toTime = j.string("to_time")?.take(5),
            )
        }
    }
}

data class MemberGoals(
    val membership: Boolean = true,
    val savingEnabled: Boolean = false,
    val savingUnit: String = "visits",
    val savingTarget: Int = 10,
    val savingReward: String = "",
    val fixedEnabled: Boolean = false,
    val fixedPercent: Double = 10.0,
    val periods: List<DiscountPeriod> = emptyList(),
) {
    fun payload(): JSONObject = JSONObject().apply {
        put("membership", membership)
        put("saving", JSONObject().put("enabled", savingEnabled).put("unit", savingUnit).put("target", savingTarget).put("reward", savingReward))
        put("fixed_discount", JSONObject().put("enabled", fixedEnabled).put("percent", fixedPercent))
        put("periods", JSONArray(periods.map { it.payload() }))
    }

    companion object {
        fun from(j: J?): MemberGoals {
            if (j == null) return MemberGoals()
            val s = j.obj("saving")
            val f = j.obj("fixed_discount")
            return MemberGoals(
                membership = j.bool("membership") ?: false,
                savingEnabled = s?.bool("enabled") ?: false, savingUnit = s?.string("unit") ?: "visits",
                savingTarget = s?.int("target") ?: 10, savingReward = s?.string("reward") ?: "",
                fixedEnabled = f?.bool("enabled") ?: false, fixedPercent = f?.double("percent") ?: 10.0,
                periods = j.array("periods").map { DiscountPeriod.from(it) },
            )
        }
    }
}

data class DiscountInfo(val percent: Double, val label: String, val until: Date?, val startsAt: Date?) {
    companion object {
        fun from(j: J?): DiscountInfo? {
            val p = j?.double("percent") ?: return null
            return DiscountInfo(p, j.string("label") ?: "", j.date("until", "ends_at"), j.date("starts_at"))
        }
    }
}

data class SavingInfo(val count: Int, val target: Int, val reward: String, val canRedeem: Boolean, val unit: String?) {
    companion object {
        fun from(j: J?): SavingInfo? {
            if (j == null) return null
            val count = j.int("count") ?: 0
            val target = maxOf(1, j.int("target") ?: 10)
            return SavingInfo(count, target, j.string("reward") ?: "", j.bool("can_redeem") ?: (count >= target), j.string("unit"))
        }
    }
}

data class MemberCard(
    val id: String = "",
    val name: String = "",
    val color: String = "#7B4B2A",
    val logo: String? = null,
    val barcodeType: String = "code128",
    val prefix: String = "",
    val status: String = "draft",
    val members: Int = 0,
    val goals: MemberGoals = MemberGoals(),
    val discountNow: DiscountInfo? = null,
    val nextDiscount: DiscountInfo? = null,
) {
    val isPublished get() = status == "published"
    val addUrl get() = "https://pasr.nl/add/m/${id.lowercase()}"
    val sampleNumber get() = if (barcodeType == "ean13") "8712345000124" else (if (prefix.isEmpty()) "000124" else prefix + "000124")

    fun payload(newStatus: String, logoChanged: Boolean): JSONObject = JSONObject().apply {
        put("name", name.trim())
        put("color", color.uppercase())
        put("barcode_type", barcodeType)
        put("prefix", if (barcodeType == "ean13") "" else prefix)
        put("status", newStatus)
        put("goals", goals.payload())
        if (id.isNotEmpty()) put("id", id)
        if (logoChanged || id.isEmpty()) put("logo", logo ?: JSONObject.NULL)
    }

    companion object {
        fun from(j: J): MemberCard? {
            val id = j.string("id", "card_id") ?: return null
            return MemberCard(
                id = id, name = j.string("name") ?: "", color = j.string("color") ?: "#7B4B2A", logo = j.string("logo"),
                barcodeType = (j.string("barcode_type") ?: "code128").lowercase(), prefix = j.string("prefix") ?: "",
                status = (j.string("status") ?: "draft").lowercase(), members = j.int("members", "members_count") ?: 0,
                goals = MemberGoals.from(j.obj("goals")), discountNow = DiscountInfo.from(j.obj("discount_now")),
                nextDiscount = DiscountInfo.from(j.obj("next_discount")),
            )
        }
    }
}

data class MemberScan(
    val code: String,
    val result: String,
    val cardId: String?,
    val cardName: String,
    val memberName: String?,
    val number: String,
    val discountNow: DiscountInfo?,
    val nextDiscount: DiscountInfo?,
    val saving: SavingInfo?,
) {
    val isValid get() = result == "valid"

    companion object {
        fun from(any: Any?, code: String): MemberScan? {
            val j = J.of(any) ?: return null
            val result = j.string("result", "status") ?: return null
            return MemberScan(
                code, result.lowercase(), j.string("card_id"), j.string("card_name") ?: "", j.string("member_name"),
                j.string("number") ?: code, DiscountInfo.from(j.obj("discount_now")), DiscountInfo.from(j.obj("next_discount")),
                SavingInfo.from(j.obj("saving")),
            )
        }
    }
}

/** Datums in de taal van de app ("za 19 dec · 16:00–19:00", "di 17:00"). */
object TkText {
    private val locale: Locale get() = if (app.lrvdlinden.pasrzakelijk.core.I18n.dutch) Locale("nl", "NL") else Locale.UK
    private fun p(pattern: String, d: Date) = SimpleDateFormat(pattern, locale).apply { timeZone = TkFormat.zone }.format(d)

    fun dayMonth(d: Date) = p("d MMM", d)
    fun clock(d: Date) = p("HH:mm", d)
    fun dateNumeric(d: Date) = p("dd-MM-yyyy", d)
    fun eventLine(start: Date, end: Date?) = p("EEE d MMM", start) + " · " + clock(start) + (end?.let { "–" + clock(it) } ?: "")
    fun soon(d: Date) = if (d.time - System.currentTimeMillis() < 6 * 86_400_000L) p("EEE HH:mm", d) else p("d MMM HH:mm", d)
    fun weekday(day: Int): String {
        val c = Calendar.getInstance(TkFormat.zone)
        c.set(Calendar.DAY_OF_WEEK, if (day == 7) Calendar.SUNDAY else day + 1)
        return p("EEE", c.time)
    }
    fun monthYear(d: Date) = p("MMMM yyyy", d)
}

object TkApi {
    private fun obj(vararg pairs: Pair<String, Any?>) = JSONObject().apply { for ((k, v) in pairs) put(k, v ?: JSONObject.NULL) }

    private fun rows(json: Any?): List<J> = when (json) {
        is JSONArray -> json.objects()
        is JSONObject -> J(json).array("events", "cards", "registrations", "rows", "items")
        else -> emptyList()
    }

    private fun idOf(json: Any?): String? = (json as? String) ?: J.of(json)?.string("id", "event_id", "card_id")

    suspend fun events(business: String): List<TicketEvent> =
        rows(Account.rpc("pasr_business_events", obj("p_business" to business))).mapNotNull { TicketEvent.from(it) }.sortedBy { it.startsAt }

    suspend fun saveEvent(event: TicketEvent, business: String, status: String): String? =
        idOf(Account.rpc("pasr_business_event_save", obj("p_business" to business, "p_event" to event.payload(status))))

    suspend fun registrations(business: String, event: String): List<EventRegistration> =
        rows(Account.rpc("pasr_business_event_registrations", obj("p_business" to business, "p_event" to event)))
            .mapIndexed { i, j -> EventRegistration.from(j, i) }

    suspend fun cancelEvent(business: String, event: String, message: String) {
        Account.rpc("pasr_business_event_cancel", obj("p_business" to business, "p_event" to event, "p_message" to message))
    }

    suspend fun scanTicket(business: String, code: String, event: String?): TicketScan =
        TicketScan.from(Account.rpc("pasr_business_ticket_scan", obj("p_business" to business, "p_code" to code, "p_event" to event)), code)
            ?: throw ApiError(L("Dit ticket is niet bekend."))

    suspend fun memberCards(business: String): List<MemberCard> =
        rows(Account.rpc("pasr_business_member_cards", obj("p_business" to business))).mapNotNull { MemberCard.from(it) }

    suspend fun saveMemberCard(card: MemberCard, business: String, status: String, logoChanged: Boolean): String? =
        idOf(Account.rpc("pasr_business_member_card_save", obj("p_business" to business, "p_card" to card.payload(status, logoChanged))))

    suspend fun scanMemberCard(business: String, code: String): MemberScan =
        MemberScan.from(Account.rpc("pasr_business_member_card_scan", obj("p_business" to business, "p_code" to code)), code)
            ?: throw ApiError(L("Deze klantenkaart is niet bekend."))

    suspend fun visit(business: String, code: String, points: Int?): SavingInfo? {
        val args = obj("p_business" to business, "p_code" to code)
        if (points != null) args.put("p_points", points)
        val j = J.of(Account.rpc("pasr_business_member_card_visit", args))
        return SavingInfo.from(j?.obj("saving") ?: j)
    }

    suspend fun redeem(business: String, code: String): SavingInfo? {
        val j = J.of(Account.rpc("pasr_business_member_card_redeem", obj("p_business" to business, "p_code" to code)))
        return SavingInfo.from(j?.obj("saving") ?: j)
    }
}

/** Wat de camera of het toetsenbord oplevert, ingedeeld naar soort code (zelfde regels als iOS). */
sealed interface ScanCode {
    data class Coupon(val code: String) : ScanCode
    data class StampCard(val code: String) : ScanCode
    data class Ticket(val code: String) : ScanCode
    data class MemberCardCode(val code: String) : ScanCode

    companion object {
        fun classify(text: String): ScanCode? {
            val t = text.trim()
            if (t.isEmpty()) return null
            if (Regex("^[a-zA-Z][a-zA-Z0-9+.-]*:").containsMatchIn(t)) {
                val uri = runCatching { Uri.parse(t) }.getOrNull()
                if (uri != null && (uri.path ?: "").contains("/add/t/")) {
                    runCatching { uri.getQueryParameter("c") }.getOrNull()?.takeIf { it.isNotBlank() }?.let { return Ticket(it) }
                }
                return MemberCode.extract(t)?.let { StampCard(it) }
            }
            val upper = t.uppercase()
            if (Regex("^PC[A-HJ-NP-Z2-9]{22}$").matches(upper)) return Coupon(upper)
            val compact = upper.replace(" ", "")
            if (Regex("^PZ[A-HJ-NP-Z2-9]{10,40}$").matches(compact)) return StampCard(compact)
            if (Regex("^[0-9]{13}$").matches(compact)) return MemberCardCode(compact)
            if (Regex("^[A-Z2-7]{20,64}$").matches(compact)) return Ticket(t.replace(" ", ""))
            if (t.length <= 32 && Regex("^[A-Za-z0-9][A-Za-z0-9 ._/-]*[0-9]$").matches(t) && !compact.startsWith("PZ")) return MemberCardCode(t)
            return MemberCode.extract(t)?.let { StampCard(it) }
        }
    }
}
