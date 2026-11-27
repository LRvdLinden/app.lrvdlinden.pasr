package app.lrvdlinden.pasr.data

import org.json.JSONObject
import java.text.Normalizer
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Wat een ticket laat zien (zelfde als TicketInfo.swift op iOS): uit het sjabloon in de catalogus (de gids met
 * evenementgegevens, zie TicketEvent in supabase/functions/admin/stores.ts) en aangevuld met wat de gebruiker bij de
 * kaart invulde (datum, locatie, plaats).
 */
data class TicketInfo(
    /** Naam naast het logo, bijv. "Drakenboot". */
    val brand: String,
    /** Titel, bijv. "Drakenboot 2027". */
    val title: String,
    val type: String? = null,
    val note: String? = null,
    val dateText: String? = null,
    val timeText: String? = null,
    val venue: String? = null,
    val city: String? = null,
    val address: String? = null,
    val seat: String? = null,
    val info: String? = null,
    val textHex: String? = null,
    val labelHex: String? = null,
    /** Zelfde sleutel = zelfde evenement (groeperen; ook de groupingIdentifier van de Wallet-pas). */
    val groupKey: String,
    /** Eerste dag, voor sorteren. */
    val start: LocalDate? = null,
    /** Ticket van een zaak (Pasr Zakelijk): houder, status, deuren, plek op de kaart en headerafbeelding. */
    val holder: String? = null,
    val status: String? = null,
    val doorsText: String? = null,
    val isBusiness: Boolean = false,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val header: String? = null,
) {
    /** "Zwitsalpark, Apeldoorn" */
    val place: String? get() = listOfNotNull(venue, city).filter { it.isNotBlank() }.joinToString(", ").ifBlank { null }

    /** Waar de route naartoe gaat: het adres, anders locatie en plaats. */
    val routeTarget: String? get() = address?.takeIf { it.isNotBlank() } ?: place

    companion object {
        private val NL = Locale("nl", "NL")
        private val DAY = DateTimeFormatter.ofPattern("d MMMM yyyy", NL)
        private val DAY_MONTH = DateTimeFormatter.ofPattern("d MMMM", NL)

        /** Titel en soort uit een naam als "Drakenboot – Early Bird". */
        fun split(name: String): Pair<String, String?> {
            for (sep in listOf(" – ", " - ", " — ")) {
                val i = name.indexOf(sep)
                if (i >= 0) return name.substring(0, i).trim() to name.substring(i + sep.length).trim().ifBlank { null }
            }
            return name.trim() to null
        }

        fun groupKey(text: String): String {
            val folded = Normalizer.normalize(text.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")
            val slug = folded.replace(Regex("[^a-z0-9]+"), "-").trim('-')
            return "pasr-event-" + slug.ifBlank { "ticket" }
        }

        private fun JSONObject.text(key: String, max: Int = 120): String? =
            optString(key, "").trim().take(max).ifBlank { null }

        private fun day(text: String?): LocalDate? = text?.let { runCatching { LocalDate.parse(it) }.getOrNull() }

        /** "18 juni 2027", of "15 – 18 juli 2027" / "30 juni – 2 juli 2027". */
        fun dates(first: LocalDate, last: LocalDate?): String = when {
            last == null || !last.isAfter(first) -> DAY.format(first)
            first.year == last.year && first.month == last.month -> "${first.dayOfMonth} – ${DAY.format(last)}"
            first.year == last.year -> "${DAY_MONTH.format(first)} – ${DAY.format(last)}"
            else -> "${DAY.format(first)} – ${DAY.format(last)}"
        }

        private val WHEN = DateTimeFormatter.ofPattern("EEE d MMM yyyy", NL)
        private val TIME = DateTimeFormatter.ofPattern("HH:mm", NL)

        /** Ticket van een zaak (pasr_my_event_tickets): alles van de server, niets uit de catalogus. */
        fun business(card: Card): TicketInfo {
            val d = card.details
            val zone = ZoneId.systemDefault()
            val start = d.eventDate?.let { Instant.ofEpochMilli(it).atZone(zone) }
            val end = d.eventEnd?.let { Instant.ofEpochMilli(it).atZone(zone) }
            var time = start?.let { TIME.format(it) }
            if (start != null && end != null && end.isAfter(start)) {
                time += " – " + if (end.toLocalDate() == start.toLocalDate()) TIME.format(end) else DateTimeFormatter.ofPattern("d MMM HH:mm", NL).format(end)
            }
            return TicketInfo(
                brand = d.businessName ?: card.storeName,
                title = card.storeName.ifBlank { "Ticket" },
                type = d.ticketTypeName,
                dateText = start?.let { WHEN.format(it) },
                timeText = time,
                venue = d.address,
                address = d.address,
                groupKey = "pasr-event-" + (d.eventId ?: d.ticketId ?: "ticket"),
                start = start?.toLocalDate(),
                holder = d.holderName,
                status = d.ticketStatus,
                doorsText = d.doorsAt?.let { TIME.format(Instant.ofEpochMilli(it).atZone(zone)) },
                isBusiness = true,
                latitude = d.latitude,
                longitude = d.longitude,
                header = d.headerURL,
            )
        }

        /** Het ticket van een kaart, met de gids van het sjabloon (null = geen sjabloon of geen evenementgegevens). */
        fun resolve(card: Card, guide: JSONObject?): TicketInfo {
            if (card.details.isEventTicket) return business(card)
            val (nameTitle, nameType) = split(card.storeName.ifBlank { "Ticket" })
            val event = guide?.text("event", 60)
            val title = event ?: nameTitle
            val own = card.details
            val ownVenue = own.venue?.trim()?.ifBlank { null }
            var dateText: String? = null
            var timeText: String? = null
            var start: LocalDate? = null
            if (own.eventDate != null) {
                val at = Instant.ofEpochMilli(own.eventDate).atZone(ZoneId.systemDefault())
                dateText = DAY.format(at)
                if (at.hour != 0 || at.minute != 0) timeText = DateTimeFormatter.ofPattern("HH:mm", NL).format(at)
                start = at.toLocalDate()
            } else {
                day(guide?.text("date", 10))?.let { first ->
                    dateText = dates(first, day(guide?.text("end_date", 10)))
                    start = first
                }
            }
            val doors = guide?.text("doors", 5)
            if (timeText == null && doors != null) timeText = guide?.text("ends", 5)?.let { "$doors – $it" } ?: "vanaf $doors"
            val site = guide?.text("info_url", 300)?.takeIf { it.startsWith("https://") }
                ?: card.website?.trim()?.ifBlank { null }?.let { if (it.startsWith("http")) it else "https://$it" }
                    ?.takeIf { it.startsWith("https://") }
            return TicketInfo(
                brand = guide?.text("brand", 30) ?: split(title).first,
                title = title,
                type = guide?.text("ticket_type", 30) ?: nameType,
                note = guide?.text("ticket_note", 40),
                dateText = dateText,
                timeText = timeText,
                venue = ownVenue ?: guide?.text("venue", 60),
                city = if (ownVenue != null) null else guide?.text("city", 40),
                address = guide?.text("address"),
                seat = own.seat?.trim()?.ifBlank { null },
                info = site,
                textHex = guide?.text("text_hex", 7),
                labelHex = guide?.text("label_hex", 7),
                groupKey = groupKey(event ?: nameTitle),
                start = start,
            )
        }
    }
}

/** Het ticket zoals Pasr het toont, met de evenementgegevens uit de catalogus. */
fun Card.ticketInfo(): TicketInfo = TicketInfo.resolve(this, Catalog.template(templateID)?.guide)
