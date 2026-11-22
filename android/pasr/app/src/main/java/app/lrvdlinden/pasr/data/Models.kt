package app.lrvdlinden.pasr.data

import kotlinx.serialization.Serializable
import java.text.Collator
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlin.math.pow

fun newId(): String = UUID.randomUUID().toString().uppercase()
fun nowMs(): Long = System.currentTimeMillis()

/** Soort pas. Bewaard als tekst; een onbekende waarde (van een nieuwere versie) telt als klantenkaart. */
enum class CardKind(val raw: String, val title: String, val codeLabel: String) {
    LOYALTY("loyalty", "Klantenkaart", "Kaartnummer"),
    VOUCHER("voucher", "Cadeaukaart", "Kaartnummer"),
    CODE("code", "Kortingscode", "Code"),
    TICKET("ticket", "Ticket", "Ticketcode"),
    SUBSCRIPTION("subscription", "Abonnement", "Lidnummer"),
    STAMPS("stamps", "Stempelkaart", "Kaartnummer");

    val hasExpiry get() = this == VOUCHER || this == CODE

    companion object {
        fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: LOYALTY
        /** Wat je zelf toevoegt (niet uit de winkellijst). Een stempelkaart komt alleen van een zaak. */
        val others = listOf(CODE, TICKET, SUBSCRIPTION)
        fun choosable(current: CardKind) = entries.filter { it != STAMPS || current == STAMPS }
    }
}

enum class BarcodeFormat(val raw: String, val title: String, val linear: Boolean) {
    EAN13("ean13", "EAN-13", true), EAN8("ean8", "EAN-8", true), UPCA("upcA", "UPC-A", true),
    CODE128("code128", "Code 128", true), CODE39("code39", "Code 39", true), ITF("itf", "ITF", true),
    QR("qr", "QR", false), PDF417("pdf417", "PDF417", false), AZTEC("aztec", "Aztec", false);

    companion object {
        fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: CODE128

        fun gs1Check(digits: String): Int {
            var sum = 0
            digits.reversed().forEachIndexed { i, c -> sum += (c - '0') * if (i % 2 == 0) 3 else 1 }
            return (10 - sum % 10) % 10
        }

        /** Beste soort voor een met de hand getypt nummer. */
        fun guess(value: String): BarcodeFormat {
            if (value.isNotEmpty() && value.all { it.isDigit() }) {
                if (value.length == 13 && gs1Check(value.take(12)) == value.last() - '0') return EAN13
                if (value.length == 8 && gs1Check(value.take(7)) == value.last() - '0') return EAN8
            }
            return CODE128
        }
    }
}

@Serializable
data class CardPlace(val id: String = newId(), val name: String = "", val latitude: Double, val longitude: Double)

/** Een regel in de geschiedenis: getoond, uitgegeven, opgewaardeerd of tegoed gezet. */
@Serializable
data class CardEvent(
    val id: String = newId(),
    val date: Long = nowMs(),
    val kind: String,
    val amount: Double? = null,
    val balance: Double? = null,
    val place: String? = null,
)

/** Extra gegevens per soort (zelfde velden als CardDetails op iOS). Datums in milliseconden. */
@Serializable
data class CardDetails(
    val eventDate: Long? = null,
    val venue: String? = null,
    val seat: String? = null,
    val renewsAt: Long? = null,
    val cost: Double? = null,
    val period: String? = null,
    val codeAsBarcode: Boolean? = null,
    val captions: List<String>? = null,
    val stampsTotal: Int? = null,
    val stampsCount: Int? = null,
    val reward: String? = null,
    val issuer: String? = null,
    val businessCardId: String? = null,
    val memberCode: String? = null,
) {
    val isEmpty get() = this == CardDetails()
    val isBusiness get() = issuer == "business" && businessCardId != null
    val stampsTotalValue get() = (stampsTotal ?: 10).coerceIn(2, 30)
    val stampsCountValue get() = (stampsCount ?: 0).coerceIn(0, stampsTotalValue)
    val stampsLeft get() = stampsTotalValue - stampsCountValue
    val stampsFull get() = stampsCountValue >= stampsTotalValue
    val stampsProgressText: String
        get() {
            if (stampsFull) return "Vol: wissel je beloning in"
            val r = reward?.trim()?.takeIf { it.isNotEmpty() }
            return if (r != null) "nog $stampsLeft tot $r" else "nog $stampsLeft tot je beloning"
        }
}

/** Een klantenkaart, cadeaukaart, kortingscode, ticket, abonnement of zakelijke stempelkaart. */
@Serializable
data class Card(
    val id: String = newId(),
    val kindRaw: String = CardKind.LOYALTY.raw,
    val storeName: String = "",
    val templateID: String? = null,
    val number: String = "",
    val formatRaw: String = BarcodeFormat.CODE128.raw,
    val colorHex: String = "#2B2F3A",
    val note: String = "",
    val isFavorite: Boolean = false,
    val useCount: Int = 0,
    val lastUsed: Long? = null,
    val createdAt: Long = nowMs(),
    val updatedAt: Long = nowMs(),
    val balance: Double? = null,
    val currencyCode: String? = null,
    val pin: String? = null,
    val expiresAt: Long? = null,
    val deletedAt: Long? = null,
    val website: String? = null,
    /** Eigen logo of logo van de zaak (PNG/JPEG, base64). Winkellogo's komen uit de catalogus. */
    val logo: String? = null,
    val logoFromWebsite: Boolean = false,
    val isLocked: Boolean = false,
    val places: List<CardPlace> = emptyList(),
    val history: List<CardEvent> = emptyList(),
    val balanceURL: String? = null,
    val details: CardDetails = CardDetails(),
    /** Eigen voorkant (JPEG, base64, hoogstens ~1000 px breed). */
    val cover: String? = null,
    /** Foto's op dit apparaat (versleutelde bestanden): "front", "back", "note1"…"note4". */
    val photos: List<String> = emptyList(),
) {
    val kind get() = CardKind.of(kindRaw)
    val format get() = BarcodeFormat.of(formatRaw)
    val changedAt get() = maxOf(updatedAt, deletedAt ?: 0L)
    val isExpired: Boolean
        get() {
            val e = expiresAt ?: return false
            val start = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.HOUR_OF_DAY, 0); set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 0); set(java.util.Calendar.MILLISECOND, 0)
            }.timeInMillis
            return e < start
        }
    val showsCodeAsText get() = kind == CardKind.CODE && details.codeAsBarcode != true
    val isBusinessStamps get() = kind == CardKind.STAMPS && details.isBusiness

    fun shown(place: String? = null): Card {
        val list = history.toMutableList()
        val last = list.firstOrNull { it.kind == "shown" }
        val now = nowMs()
        val events = if (last != null && now - last.date < 600_000) list else listOf(CardEvent(kind = "shown", place = place)) + list
        return copy(useCount = useCount + 1, lastUsed = now, history = trimHistory(events))
    }

    fun spent(amount: Double): Card {
        val b = (((balance ?: 0.0) - amount).coerceAtLeast(0.0) * 100).let { Math.round(it) / 100.0 }
        return copy(balance = b, history = trimHistory(listOf(CardEvent(kind = "spent", amount = amount, balance = b)) + history), updatedAt = nowMs())
    }

    fun toppedUp(amount: Double): Card {
        val b = Math.round(((balance ?: 0.0) + amount) * 100) / 100.0
        return copy(balance = b, history = trimHistory(listOf(CardEvent(kind = "topup", amount = amount, balance = b)) + history), updatedAt = nowMs())
    }

    companion object {
        fun trimHistory(list: List<CardEvent>): List<CardEvent> {
            val cutoff = nowMs() - 90L * 86_400_000
            return list.filter { it.date > cutoff }.sortedByDescending { it.date }.take(150)
        }

        /** Gebruik, afnemend met een halfwaardetijd van 30 dagen. */
        fun score(c: Card): Double {
            val used = c.lastUsed ?: return 0.0
            val days = ((nowMs() - used) / 86_400_000.0).coerceAtLeast(0.0)
            return c.useCount * 0.5.pow(days / 30)
        }
    }
}

enum class CardOrder(val raw: String, val title: String) {
    AZ("az", "A tot Z"), USED("used", "Meest gebruikt bovenaan");

    companion object { fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: AZ }
}

private val collator: Collator = Collator.getInstance(Locale("nl", "NL")).apply { strength = Collator.PRIMARY }

/** Altijd A tot Z op winkelnaam (overal in Pasr). */
fun List<Card>.alphabetical(): List<Card> = sortedWith { a, b ->
    val o = collator.compare(a.storeName, b.storeName)
    if (o != 0) o else a.number.compareTo(b.number)
}

fun List<Card>.ordered(order: CardOrder): List<Card> {
    val az = alphabetical()
    if (order == CardOrder.AZ) return az
    return az.withIndex().sortedWith { a, b ->
        val x = Card.score(a.value); val y = Card.score(b.value)
        if (abs(x - y) < 0.0001) a.index.compareTo(b.index) else y.compareTo(x)
    }.map { it.value }
}

fun String.nilIfBlank(): String? = trim().takeIf { it.isNotEmpty() }
