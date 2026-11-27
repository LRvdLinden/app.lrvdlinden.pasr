package app.lrvdlinden.pasr.data

import java.text.Normalizer
import java.time.Instant
import java.time.ZoneId

/*
 * Tickets groeperen (zoals Apple Wallet), gelijk aan iOS (Shared/Model/TicketGroups.swift).
 *
 * Tickets voor hetzelfde evenement op dezelfde dag staan in de portemonnee als één item ("3 tickets"). Open je het,
 * dan veeg je horizontaal van ticket naar ticket, elk met een eigen code.
 *
 * Sleutel: genormaliseerde eventnaam + dag van CardDetails.eventDate (tijdzone van het toestel). De eventnaam is de
 * naam van het ticket tot het eerste streepje: "Drakenboot – Regular", "Drakenboot – KIDS Early Bird" en een zelf
 * toegevoegd "Drakenboot" horen bij elkaar. Geen nieuw veld nodig: eventDate wordt al gesynchroniseerd.
 */

private val ticketTypeSeparators = listOf(" – ", " — ", " - ", " | ", ": ")

/** "Drakenboot – KIDS Early Bird" → "Drakenboot". */
fun ticketEventTitle(name: String): String {
    var title = name.trim()
    for (separator in ticketTypeSeparators) {
        val i = title.indexOf(separator)
        if (i > 0) title = title.substring(0, i).trim().ifEmpty { title }
    }
    return title
}

/** Kleine letters, zonder accenten en leestekens: "Drakenboot 2027!" → "drakenboot2027". */
fun normalizedEventKey(name: String): String =
    Normalizer.normalize(ticketEventTitle(name), Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "")
        .lowercase(java.util.Locale.ROOT)
        .filter { it.isLetterOrDigit() }

/** Groepeersleutel van een ticket met datum; null voor andere kaarten (die staan altijd los). */
val Card.ticketGroupKey: String?
    get() {
        if (kind != CardKind.TICKET || deletedAt != null) return null
        val date = details.eventDate ?: return null
        val event = normalizedEventKey(storeName).ifEmpty { return null }
        val day = Instant.ofEpochMilli(date).atZone(ZoneId.systemDefault()).toLocalDate()
        return "$event|${day.year}-${day.monthValue}-${day.dayOfMonth}"
    }

/** Eén item in de portemonnee: een losse kaart, of een groep tickets (A tot Z op naam). Nooit leeg. */
data class CardStackItem(val cards: List<Card>) {
    val first: Card get() = cards.first()
    val id: String get() = first.id
    val isGroup: Boolean get() = cards.size > 1
    fun contains(id: String) = cards.any { it.id.equals(id, true) }
    /** Naam van het evenement bij een groep ("Drakenboot"), anders de naam van de kaart. */
    val title: String get() = if (isGroup) ticketEventTitle(first.storeName) else first.storeName
    val countText: String get() = "${cards.size} tickets"
}

/**
 * Groepeert tickets voor hetzelfde evenement op dezelfde dag; de volgorde blijft (een groep staat waar zijn eerste
 * ticket stond). Al het andere blijft een los item.
 */
fun List<Card>.stackItems(): List<CardStackItem> {
    val buckets = LinkedHashMap<String, MutableList<Card>>()
    for (card in this) buckets.getOrPut(card.ticketGroupKey ?: "card:${card.id}") { mutableListOf() }.add(card)
    return buckets.values.map { CardStackItem(if (it.size > 1) it.alphabetical() else it) }
}

/** De groep tickets waar [id] bij hoort (bij een losse kaart alleen die kaart; leeg als de kaart weg is). */
fun List<Card>.ticketGroupOf(id: String): List<Card> =
    filter { it.deletedAt == null }.alphabetical().stackItems().firstOrNull { it.contains(id) }?.cards ?: emptyList()
