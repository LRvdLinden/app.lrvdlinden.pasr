package app.lrvdlinden.pasr.data

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Tickets (gratis events) en klantenkaarten met barcode van zaken in Pasr Zakelijk (zelfde als BusinessPasses.swift).
 * De server is de bron (pasr_my_event_tickets en pasr_my_member_cards op je account); Pasr zet ze als gewone kaarten in
 * de portemonnee (ticket en klantenkaart), zodat groeperen, vegen en widgets vanzelf werken. Ze gaan niet mee in de
 * kaartsynchronisatie. Geboortedatum en e-mail worden nooit in de app bewaard.
 */
object BusinessPasses {
    private val NL = Locale("nl", "NL")

    // ---- ophalen en bijwerken ----

    /** Tickets en klantenkaarten bijwerken; hoogstens eens per minuut vanzelf. Geeft de kaarten die veranderden. */
    suspend fun refreshAll(force: Boolean = false): List<Card> {
        if (!Account.isSignedIn) return emptyList()
        if (!force && nowMs() - Prefs.long("bizpasses.at") < 60_000) return emptyList()
        Prefs.setLong("bizpasses.at", nowMs())
        return refreshTickets() + refreshMemberCards()
    }

    private fun rows(json: Any?, key: String): List<JSONObject>? = when (json) {
        is JSONArray -> json.objects()
        is JSONObject -> (json.optJSONArray(key) ?: json.optJSONArray("rows"))?.objects()
        else -> null
    }

    suspend fun refreshTickets(): List<Card> {
        val list = rows(runCatching { Api.rpc("pasr_my_event_tickets", JSONObject()) }.getOrNull() ?: return emptyList(), "tickets")
            ?: return emptyList()
        val changed = mutableListOf<Card>()
        val seen = mutableSetOf<String>()
        for (row in list) {
            val ticketId = row.str("ticket_id", "id")?.lowercase() ?: continue
            seen += ticketId
            val matches = CardStore.cards.value.filter { it.details.ticketId?.lowercase() == ticketId }
            matches.drop(1).forEach { CardStore.purge(it.id) }
            val existing = matches.firstOrNull()
            if (existing != null && existing.deletedAt != null) continue
            if (existing == null && Dismissed.contains(ticketId)) continue
            val base = existing ?: Card(kindRaw = CardKind.TICKET.raw, formatRaw = BarcodeFormat.QR.raw, colorHex = "#6A5CFF")
            val next = applyTicket(row, base)
            if (next != existing) { CardStore.upsert(next); changed += next }
        }
        CardStore.cards.value.filter { it.details.isEventTicket && it.details.ticketId?.lowercase() !in seen }.forEach {
            GoogleWallet.removeIfSaved(it)
            CardStore.purge(it.id)
        }
        return changed
    }

    private suspend fun applyTicket(row: JSONObject, card: Card): Card {
        val d = card.details.copy(
            issuer = "event",
            ticketId = row.str("ticket_id", "id")?.lowercase(),
            eventId = (row.str("event_id") ?: row.str("group_key"))?.lowercase(),
            ticketStatus = row.str("status")?.lowercase(),
            holderName = row.str("holder_name"),
            ticketTypeName = row.str("ticket_type", "ticket_type_name"),
            eventDate = date(row.opt("starts_at")),
            eventEnd = date(row.opt("ends_at")),
            doorsAt = date(row.opt("doors_at")),
            address = row.str("address"),
            latitude = number(row.opt("lat")),
            longitude = number(row.opt("lng")),
            headerURL = row.str("header_url")?.takeIf { it.startsWith("https://") },
            businessName = row.str("business_name"),
        )
        var c = card.copy(
            kindRaw = CardKind.TICKET.raw,
            storeName = row.str("event_name", "name") ?: "Ticket",
            number = row.str("code") ?: "",
            formatRaw = BarcodeFormat.QR.raw,
            colorHex = hex(row.str("color")) ?: card.colorHex,
            details = d,
        )
        c = withLogo(c, row.str("business_logo", "logo"))
        return c
    }

    suspend fun refreshMemberCards(): List<Card> {
        val list = rows(runCatching { Api.rpc("pasr_my_member_cards", JSONObject()) }.getOrNull() ?: return emptyList(), "cards")
            ?: return emptyList()
        val changed = mutableListOf<Card>()
        val seen = mutableSetOf<String>()
        for (row in list) {
            val memberId = row.str("member_id")?.lowercase() ?: continue
            seen += memberId
            val matches = CardStore.cards.value.filter { it.details.memberId?.lowercase() == memberId }
            matches.drop(1).forEach { CardStore.purge(it.id) }
            val existing = matches.firstOrNull()
            if (existing != null && existing.deletedAt != null) continue
            if (existing == null && Dismissed.contains(memberId)) continue
            val base = existing ?: Card(kindRaw = CardKind.LOYALTY.raw, colorHex = "#6A5CFF")
            val next = applyMember(row, base)
            if (next != existing) { CardStore.upsert(next); changed += next }
        }
        CardStore.cards.value.filter { it.details.isMemberCard && it.details.memberId?.lowercase() !in seen }.forEach {
            GoogleWallet.removeIfSaved(it)
            CardStore.purge(it.id)
        }
        return changed
    }

    private suspend fun applyMember(row: JSONObject, card: Card): Card {
        val saving = row.optJSONObject("saving")
        val notify = row.opt("notify") as? Boolean ?: row.opt("notify_discounts") as? Boolean
        val d = card.details.copy(
            issuer = "member",
            memberId = row.str("member_id")?.lowercase(),
            memberCardId = row.str("card_id")?.lowercase(),
            businessName = row.str("business_name"),
            discountNow = discount(row.optJSONObject("discount_now")),
            nextDiscount = discount(row.optJSONObject("next_discount")),
            savingCount = saving?.int("count"),
            savingTarget = saving?.int("target"),
            savingReward = saving?.str("reward"),
            savingCanRedeem = saving?.opt("can_redeem") as? Boolean,
            memberNotify = notify ?: card.details.memberNotify,
        )
        val number = row.str("number") ?: ""
        var c = card.copy(
            kindRaw = CardKind.LOYALTY.raw,
            storeName = row.str("name", "card_name") ?: d.businessName ?: "Klantenkaart",
            number = number,
            formatRaw = barcodeFormat(row.str("barcode_type"), number).raw,
            colorHex = hex(row.str("color")) ?: card.colorHex,
            details = d,
        )
        c = withLogo(c, row.str("logo", "business_logo"))
        return c
    }

    /** QR, Code 128 of EAN-13 (alleen een geldig EAN-13-nummer; anders Code 128 met hetzelfde nummer). */
    fun barcodeFormat(raw: String?, number: String): BarcodeFormat = when (raw?.lowercase()?.replace("-", "")?.replace("_", "")) {
        "qr" -> BarcodeFormat.QR
        "ean13" -> if (number.length == 13 && number.all { it.isDigit() } && BarcodeFormat.gs1Check(number.take(12)) == number.last() - '0')
            BarcodeFormat.EAN13 else BarcodeFormat.CODE128
        else -> BarcodeFormat.CODE128
    }

    private suspend fun withLogo(card: Card, source: String?): Card {
        if (source.isNullOrBlank() || (card.details.logoSource == source && card.logo != null)) return card
        val logo = Business.logoBase64(source) ?: return card
        return card.copy(logo = logo, logoFromWebsite = false, details = card.details.copy(logoSource = source))
    }

    // ---- events ----

    data class TicketType(val id: String, val name: String, val available: Int?)

    data class EventInfo(
        val id: String, val name: String, val description: String?, val start: Long?, val end: Long?, val doors: Long?,
        val address: String?, val latitude: Double?, val longitude: Double?, val color: String, val header: String?,
        val business: String?, val logo: String?, val types: List<TicketType>, val spotsLeft: Int?, val maxPerPerson: Int,
        val signupOpen: Boolean, val waitlist: Boolean, val status: String?,
    ) {
        val isCancelled get() = status == "cancelled"
        val isFull get() = (spotsLeft ?: 1) <= 0

        /** "za 19 dec 2026 · 16:00 – 19:00" */
        val whenText: String?
            get() {
                val s = start?.let { Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()) } ?: return null
                var t = DateTimeFormatter.ofPattern("EEE d MMM yyyy · HH:mm", NL).format(s)
                val e = end?.let { Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()) }
                if (e != null && e.isAfter(s) && e.toLocalDate() == s.toLocalDate()) t += " – " + DateTimeFormatter.ofPattern("HH:mm", NL).format(e)
                return t
            }

        companion object {
            fun from(json: Any?, id: String): EventInfo? {
                val d = (json as? JSONObject) ?: (json as? JSONArray)?.optJSONObject(0) ?: return null
                if (!d.has("name") && !d.has("id")) return null
                return EventInfo(
                    id = d.str("id") ?: id, name = d.str("name") ?: "Event", description = d.str("description"),
                    start = date(d.opt("starts_at")), end = date(d.opt("ends_at")), doors = date(d.opt("doors_at")),
                    address = d.str("address"), latitude = number(d.opt("lat")), longitude = number(d.opt("lng")),
                    color = hex(d.str("color")) ?: "#6A5CFF", header = d.str("header_url")?.takeIf { it.startsWith("https://") },
                    business = d.str("business_name"), logo = d.str("business_logo", "logo"),
                    types = d.optJSONArray("ticket_types")?.objects()?.mapNotNull { t ->
                        TicketType(t.str("id") ?: return@mapNotNull null, t.str("name") ?: "Toegang", t.int("available"))
                    } ?: emptyList(),
                    spotsLeft = d.int("spots_left"), maxPerPerson = (d.int("max_per_person") ?: 4).coerceAtLeast(1),
                    signupOpen = d.opt("signup_open") as? Boolean ?: true, waitlist = d.opt("waitlist") as? Boolean ?: false,
                    status = d.str("status")?.lowercase(),
                )
            }
        }
    }

    suspend fun event(id: String): EventInfo =
        EventInfo.from(Api.publicRpc("pasr_event_public", JSONObject().put("p_event", id)), id)
            ?: throw PasrError("Dit event is niet (meer) gevonden.")

    data class Registration(val waitlist: Boolean, val ticketIds: List<String>)

    /** Aanmelden (ingelogd): de tickets komen meteen in je Pasr. */
    suspend fun register(event: String, firstName: String, lastName: String, email: String, birthDate: LocalDate,
                         ticketType: String?, count: Int): Registration {
        val body = JSONObject().put("p_event", event).put("p_first_name", firstName.trim()).put("p_last_name", lastName.trim())
            .put("p_email", email.trim().lowercase()).put("p_birth_date", birthDate.toString())
            .put("p_ticket_type", ticketType ?: JSONObject.NULL).put("p_count", count)
        val json = Api.rpc("pasr_event_register", body)
        val d = (json as? JSONObject) ?: (json as? JSONArray)?.optJSONObject(0) ?: JSONObject()
        val ids = d.optJSONArray("tickets")?.objects()?.mapNotNull { it.str("ticket_id")?.lowercase() } ?: emptyList()
        ids.forEach { Dismissed.remove(it) }
        refreshTickets()
        return Registration(d.str("status")?.lowercase() == "waitlist", ids)
    }

    /** /add/t/<ticket>?c=<code>: een ticket (aangemeld zonder account) aan je account koppelen. */
    suspend fun claim(ticket: String, code: String): String {
        val json = Api.rpc("pasr_event_ticket_claim", JSONObject().put("p_ticket", ticket).put("p_code", code))
        val id = ((json as? JSONObject)?.str("ticket_id") ?: ticket).lowercase()
        Dismissed.remove(id)
        refreshTickets()
        return id
    }

    // ---- klantenkaarten ----

    data class MemberCardInfo(val id: String, val name: String, val color: String, val logo: String?, val business: String?,
                              val summary: String?, val discountNow: MemberDiscount?, val nextDiscount: MemberDiscount?)

    suspend fun memberCard(id: String): MemberCardInfo {
        val json = Api.publicRpc("pasr_member_card_public", JSONObject().put("p_card", id))
        val d = (json as? JSONObject) ?: (json as? JSONArray)?.optJSONObject(0)
        if (d == null || (!d.has("name") && !d.has("id"))) throw PasrError("Deze klantenkaart is niet (meer) gevonden.")
        val summary = when (val s = d.opt("goals_summary")) {
            is String -> s.ifBlank { null }
            is JSONArray -> (0 until s.length()).mapNotNull { s.optString(it).ifBlank { null } }.joinToString(" · ").ifBlank { null }
            else -> null
        }
        return MemberCardInfo(d.str("id") ?: id, d.str("name") ?: "Klantenkaart", hex(d.str("color")) ?: "#6A5CFF",
            d.str("logo", "business_logo"), d.str("business_name"), summary,
            discount(d.optJSONObject("discount_now")), discount(d.optJSONObject("next_discount")))
    }

    /** Aansluiten; al lid: gewoon de bestaande kaart. */
    suspend fun join(cardId: String, shareName: Boolean): Card {
        val id = cardId.lowercase()
        var failure: Exception? = null
        try {
            val json = Api.rpc("pasr_member_card_join", JSONObject().put("p_card", id).put("p_share_name", shareName))
            (json as? JSONObject)?.str("member_id")?.let { Dismissed.remove(it.lowercase()) }
        } catch (e: PasrError) {
            failure = e
        }
        CardStore.cards.value.filter { it.details.memberCardId == id && it.deletedAt != null }.forEach { c ->
            c.details.memberId?.let { Dismissed.remove(it) }
            CardStore.purge(c.id)
        }
        refreshMemberCards()
        return memberCardFor(id) ?: throw (failure ?: PasrError("Toevoegen lukte niet. Probeer het later opnieuw."))
    }

    suspend fun setNotify(card: Card, on: Boolean): Card {
        val member = card.details.memberId ?: return card
        Api.rpc("pasr_member_card_notify", JSONObject().put("p_member", member).put("p_on", on))
        val c = card.copy(details = card.details.copy(memberNotify = on))
        CardStore.upsert(c, touch = false)
        return c
    }

    /** Kaart of ticket verwijderd: een klantenkaart ook bij de zaak opzeggen; niet opnieuw ophalen. */
    suspend fun didDelete(card: Card) {
        val d = card.details
        if (d.isEventTicket) d.ticketId?.let { Dismissed.insert(it) }
        if (d.isMemberCard) d.memberId?.let { member ->
            Dismissed.insert(member)
            runCatching { Api.rpc("pasr_member_card_leave", JSONObject().put("p_member", member)) }
        }
        if (d.isServerItem) GoogleWallet.removeIfSaved(card)
    }

    // ---- zoeken ----

    fun ticketCard(event: String?, ticket: String?): Card? {
        val live = CardStore.visible.filter { it.details.isEventTicket }
        ticket?.lowercase()?.let { t -> live.firstOrNull { it.details.ticketId == t }?.let { return it } }
        val e = event?.lowercase() ?: return null
        return live.filter { it.details.eventId == e }.alphabetical().firstOrNull()
    }

    fun memberCardFor(cardId: String?): Card? {
        val id = cardId?.lowercase() ?: return null
        return CardStore.visible.firstOrNull { it.details.memberCardId == id }
    }

    // ---- hulpjes ----

    fun discount(o: JSONObject?): MemberDiscount? {
        o ?: return null
        val percent = number(o.opt("percent"))
        val label = o.str("label")?.take(80)
        if (percent == null && label == null) return null
        return MemberDiscount(percent, label, date(o.opt("until") ?: o.opt("ends_on")), date(o.opt("starts_at") ?: o.opt("starts_on")))
    }

    fun number(v: Any?): Double? = when (v) {
        is Number -> v.toDouble()
        is String -> v.toDoubleOrNull()
        else -> null
    }

    fun hex(v: String?): String? {
        val raw = v?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val c = if (raw.startsWith("#")) raw else "#$raw"
        return c.takeIf { Regex("^#[0-9A-Fa-f]{6}$").matches(it) }?.uppercase()
    }

    /** ISO 8601 / Postgres ("2026-12-19T16:00:00Z", "2026-12-19 16:00:00.123+00") of "YYYY-MM-DD" (12:00 NL). */
    fun date(v: Any?): Long? {
        val s = (v as? String)?.trim()?.takeIf { it.length >= 10 } ?: return null
        if (s.length == 10) return runCatching {
            LocalDate.parse(s).atTime(12, 0).atZone(ZoneId.of("Europe/Amsterdam")).toInstant().toEpochMilli()
        }.getOrNull()
        var t = s.replace(' ', 'T')
        if (Regex("[+-]\\d{2}$").containsMatchIn(t)) t += ":00"
        return runCatching { OffsetDateTime.parse(t).toInstant().toEpochMilli() }.getOrNull()
            ?: runCatching { Instant.parse(t).toEpochMilli() }.getOrNull()
            ?: runCatching { LocalDateTime.parse(t).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli() }.getOrNull()
    }

    /** Tickets en klantenkaarten die je zelf weghaalde (niet opnieuw toevoegen). */
    object Dismissed {
        private const val KEY = "bizpasses.dismissed"
        private fun all(): Set<String> = Prefs.string(KEY)?.split(',')?.filter { it.isNotBlank() }?.toSet() ?: emptySet()
        fun contains(id: String) = id.lowercase() in all()
        fun insert(id: String) = Prefs.setString(KEY, (all() + id.lowercase()).joinToString(","))
        fun remove(id: String) = Prefs.setString(KEY, (all() - id.lowercase()).joinToString(","))
    }
}
