package app.lrvdlinden.pasr.data

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.location.Location
import android.location.LocationManager
import android.os.Build
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.Normalizer
import java.time.LocalDate
import java.time.ZoneId
import java.util.Calendar
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.math.abs

/**
 * Een bewaard kassabonnetje (zelfde velden als Receipt op iOS), los of bij een gebruiksmoment. Datums in milliseconden.
 * De pagina's staan als losse versleutelde bestanden op het toestel (zoals de foto's van een kaart), niet in dit object.
 */
@Serializable
data class Receipt(
    val id: String = newId(),
    val cardID: String? = null,
    val useID: String? = null,
    val storeName: String = "",
    val date: Long = nowMs(),
    val total: Double? = null,
    val currencyCode: String? = null,
    val title: String = "",
    val note: String = "",
    val warrantyUntil: Long? = null,
    val pages: Int = 0,
    val createdAt: Long = nowMs(),
    val updatedAt: Long = nowMs(),
) {
    val warrantyActive: Boolean get() = warrantyUntil?.let { it >= startOfToday() } ?: false

    /** Winkel, wat je kocht, notitie, bedrag ("12,50" en "12.50") en datum, om op te zoeken. */
    val searchText: String
        get() {
            val nl = Locale("nl", "NL")
            val parts = mutableListOf(storeName, title, note)
            total?.let { parts += String.format(nl, "%.2f", it); parts += String.format(Locale.US, "%.2f", it) }
            val d = java.time.Instant.ofEpochMilli(date).atZone(ZoneId.systemDefault())
            parts += java.time.format.DateTimeFormatter.ofPattern("d MMMM yyyy", nl).format(d)
            parts += java.time.format.DateTimeFormatter.ofPattern("dd-MM-yyyy", nl).format(d)
            return parts.joinToString(" ")
        }

    fun matches(query: String): Boolean {
        val q = Catalog.fold(query.trim())
        if (q.isEmpty()) return true
        val hay = Catalog.fold(searchText)
        return q.split(' ').filter { it.isNotBlank() }.all { hay.contains(it) }
    }

    companion object {
        const val MAX_PAGES = 4
        fun defaultWarranty(from: Long): Long = Calendar.getInstance().apply { timeInMillis = from; add(Calendar.YEAR, 2) }.timeInMillis
        fun startOfToday(): Long = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
    }
}

/** Alle bonnetjes, versleuteld (AES-GCM, sleutel in de Android Keystore), net als de kaarten en hun foto's. */
object ReceiptStore {
    private lateinit var file: File
    private lateinit var dir: File
    private val _receipts = MutableStateFlow<List<Receipt>>(emptyList())
    val receipts: StateFlow<List<Receipt>> = _receipts.asStateFlow()

    fun init(context: Context) {
        file = File(context.filesDir, "receipts.enc")
        dir = File(context.filesDir, "receipts").apply { mkdirs() }
        _receipts.value = runCatching {
            if (!file.exists()) emptyList()
            else PasrJson.decodeFromString<List<Receipt>>(String(Crypto.decrypt(file.readBytes())))
        }.getOrElse { emptyList() }
    }

    @Synchronized
    private fun persist(list: List<Receipt>) {
        _receipts.value = list.sortedByDescending { it.date }
        val tmp = File(file.parentFile, "receipts.enc.tmp")
        tmp.writeBytes(Crypto.encrypt(PasrJson.encodeToString(list).toByteArray()))
        tmp.renameTo(file)
    }

    fun get(id: String) = _receipts.value.firstOrNull { it.id == id }

    @Synchronized
    fun save(r: Receipt, pages: List<ByteArray>? = null) {
        pages?.let { list ->
            (0 until Receipt.MAX_PAGES).forEach { page(r.id, it).delete() }
            list.take(Receipt.MAX_PAGES).forEachIndexed { i, jpeg -> page(r.id, i).writeBytes(Crypto.encrypt(jpeg)) }
        }
        val saved = r.copy(pages = pages?.size?.coerceAtMost(Receipt.MAX_PAGES) ?: r.pages, updatedAt = nowMs())
        persist(_receipts.value.filter { it.id != r.id } + saved)
    }

    @Synchronized
    fun delete(id: String) {
        (0 until Receipt.MAX_PAGES).forEach { page(id, it).delete() }
        persist(_receipts.value.filter { it.id != id })
    }

    private fun page(id: String, i: Int) = File(dir, "${id.lowercase()}-$i.enc")
    fun pageBytes(id: String, i: Int): ByteArray? = runCatching { Crypto.decrypt(page(id, i).readBytes()) }.getOrNull()
    fun pageBitmap(id: String, i: Int, maxSide: Int = 2000): Bitmap? = pageBytes(id, i)?.let { decode(it, maxSide) }

    fun wipe() {
        dir.listFiles()?.forEach { it.delete() }
        persist(emptyList())
    }

    fun decode(bytes: ByteArray, maxSide: Int): Bitmap? {
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, o)
        var sample = 1
        while (maxOf(o.outWidth, o.outHeight) / sample > maxSide * 2) sample *= 2
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
    }

    /** JPEG van hoogstens 2000 pixels (zoals iOS). */
    fun jpeg(bmp: Bitmap, maxSide: Int = 2000): ByteArray {
        val scale = minOf(1f, maxSide.toFloat() / maxOf(bmp.width, bmp.height))
        val b = if (scale < 1f) Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true) else bmp
        return ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
    }
}

/** Zelfde gedrag als ReceiptUseLinker op iOS: een bon krijgt een gebruiksmoment.
 * Eerst datum+bedrag matchen; ontbreekt dat moment, maak het aan op de datum van de bon.
 * Bij cadeaukaarten registreert dit enkel de winkelbetaling, nooit een saldoafboeking. */
object ReceiptUseLinker {
    fun attach(receipt: Receipt, card: Card, preferredUse: String? = null): Pair<Receipt, Card> {
        if (receipt.cardID != card.id) return receipt to card
        card.uses.firstOrNull { it.receiptID == receipt.id }?.let {
            return receipt.copy(useID = it.id) to card
        }
        val available = card.uses.filter {
            it.receiptID == null && java.time.Instant.ofEpochMilli(it.date)
                .atZone(java.time.ZoneId.systemDefault()).toLocalDate() ==
                java.time.Instant.ofEpochMilli(receipt.date)
                .atZone(java.time.ZoneId.systemDefault()).toLocalDate()
        }
        val exact = available.filter { event ->
            receipt.total?.takeIf { it > 0 }?.let { value ->
                listOfNotNull(event.amount, event.pendingAmount).any { abs(it - value) <= 0.02 }
            } ?: false
        }.minByOrNull { abs(it.date - receipt.date) }
        val unknown = available.filter { it.amount == null && it.pendingAmount == null }
        val event = preferredUse?.let { id -> available.firstOrNull { it.id == id } }
            ?: exact ?: unknown.singleOrNull()
        val eventId: String
        val updatedCard: Card
        if (event != null) {
            eventId = event.id
            updatedCard = card
        } else {
            val created = CardEvent(date = receipt.date, kind = "shown", source = "receipt")
            // Gebruik niet Card.used(): die voegt transacties binnen 15 minuten samen,
            // ook wanneer het om verschillende kassabonnen gaat.
            eventId = created.id
            updatedCard = card.copy(history = (listOf(created) + card.history)
                .filter { it.date >= nowMs() - 90L * 86_400_000 }
                .sortedByDescending { it.date }.take(150), updatedAt = nowMs())
            if (updatedCard.uses.none { it.id == eventId }) return receipt to card
        }
        val linked = updatedCard.updatingUse(eventId) { old ->
            old.copy(
                receiptID = receipt.id,
                amount = old.amount ?: receipt.total?.takeIf { it > 0 },
                pendingAmount = if (old.amount == null && receipt.total != null) null else old.pendingAmount
            )
        }
        return receipt.copy(useID = eventId) to linked
    }

    /** Eenmalig herstel van bonnen uit oude builds. Herhaald uitvoeren geeft geen extra regels. */
    fun reconcile() {
        ReceiptStore.receipts.value.forEach { receipt ->
            val card = receipt.cardID?.let(CardStore::get) ?: run {
                if (receipt.total == null) return@forEach
                // Geen expliciete kaart geselecteerd? Alleen bij één exact gelijknamige
                // winkel (zoals Action) mag een oud bonnetje worden gerepareerd.
                val matches = CardStore.visible.filter {
                    it.deletedAt == null && Catalog.fold(it.storeName) ==
                        Catalog.fold(receipt.storeName)
                }
                matches.singleOrNull()
            } ?: return@forEach
            if (card.deletedAt != null) return@forEach
            val selected = if (receipt.cardID == null) receipt.copy(cardID = card.id) else receipt
            val good = card.uses.any { it.id == receipt.useID && it.receiptID == receipt.id }
            if (good) return@forEach
            val (fixedReceipt, fixedCard) = attach(selected, card)
            if (fixedReceipt.useID != null) {
                if (fixedCard != card) CardStore.upsert(fixedCard)
                if (fixedReceipt != receipt) ReceiptStore.save(fixedReceipt)
            }
        }
    }
}

/** Totaal en datum uit de tekst van een kassabon (zelfde regels als ReceiptReader op iOS). */
object ReceiptParser {
    data class Result(val total: Double?, val date: Long?, val lines: List<String> = emptyList())

    private val amount = Regex("""(?<![\d,.])(\d{1,3}(?:[.\s]\d{3})*|\d+)[,.](\d{2})(?!\d)""")
    private val totalWords = listOf("te betalen", "totaal", "total", "tot.", "eindtotaal", "betaald", "bedrag", "pin", "amount", "to pay")
    private val weakWords = listOf("subtotaal", "subtotal", "btw", "vat", "korting", "wisselgeld", "retour", "statiegeld", "excl")
    private val months = mapOf("jan" to 1, "feb" to 2, "mrt" to 3, "maa" to 3, "mar" to 3, "apr" to 4, "mei" to 5, "may" to 5,
        "jun" to 6, "jul" to 7, "aug" to 8, "sep" to 9, "okt" to 10, "oct" to 10, "nov" to 11, "dec" to 12)

    fun amounts(line: String): List<Double> = amount.findAll(line).mapNotNull { m ->
        val whole = m.groupValues[1].filter { it.isDigit() }
        "$whole.${m.groupValues[2]}".toDoubleOrNull()?.takeIf { it > 0 && it < 100_000 }
    }.toList()

    fun parse(lines: List<String>, now: Long = nowMs()): Result {
        val lower = lines.map { it.lowercase() }
        val candidates = mutableListOf<Double>()
        lower.forEachIndexed { i, line ->
            if (totalWords.none { line.contains(it) } || weakWords.any { line.contains(it) }) return@forEachIndexed
            amounts(lines[i]).lastOrNull()?.let { candidates += it }
                ?: lines.getOrNull(i + 1)?.let { amounts(it).lastOrNull() }?.let { candidates += it }
        }
        val total = candidates.maxOrNull() ?: lines.flatMap { amounts(it) }.maxOrNull()
        return Result(total, date(lines, now), lines)
    }

    fun date(lines: List<String>, now: Long = nowMs()): Long? {
        val zone = ZoneId.systemDefault()
        val earliest = LocalDate.now(zone).minusYears(10)
        val latest = java.time.Instant.ofEpochMilli(now).atZone(zone).toLocalDate().plusDays(1)
        fun ok(y: Int, m: Int, d: Int): Long? {
            val year = if (y < 100) y + 2000 else y
            val date = runCatching { LocalDate.of(year, m, d) }.getOrNull() ?: return null
            if (date.isBefore(earliest) || date.isAfter(latest)) return null
            return date.atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
        }
        val iso = Regex("""(?<!\d)(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)""")
        val dmy = Regex("""(?<!\d)(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})(?!\d)""")
        val text = Regex("""(?i)(?<!\d)(\d{1,2})\s*([a-z]{3})[a-z]*\.?\s*(\d{2,4})(?!\d)""")
        for (line in lines) {
            iso.findAll(line).forEach { m -> ok(m.groupValues[1].toInt(), m.groupValues[2].toInt(), m.groupValues[3].toInt())?.let { return it } }
            dmy.findAll(line).forEach { m -> ok(m.groupValues[3].toInt(), m.groupValues[2].toInt(), m.groupValues[1].toInt())?.let { return it } }
            text.findAll(line).forEach { m ->
                val month = months[m.groupValues[2].lowercase()] ?: return@forEach
                ok(m.groupValues[3].toInt(), month, m.groupValues[1].toInt())?.let { return it }
            }
        }
        return null
    }

    /** "€ 1.234,56", "12,34 €", "EUR 12.34" → 1234.56 / 12.34. */
    fun parseAmount(text: String): Double? {
        var t = text.filter { it.isDigit() || it == ',' || it == '.' }
        if (t.isEmpty()) return null
        val c = t.lastIndexOf(','); val d = t.lastIndexOf('.')
        t = when {
            c >= 0 && d >= 0 -> if (c > d) t.replace(".", "").replace(',', '.') else t.replace(",", "")
            c >= 0 -> t.replace(',', '.')
            t.count { it == '.' } > 1 -> t.replace(".", "")
            else -> t
        }
        return t.toDoubleOrNull()?.takeIf { it >= 0 && it < 1_000_000 }?.let { Math.round(it * 100) / 100.0 }
    }
}

/**
 * Zoekt de kaart die het best past bij een winkelnaam uit een betaling ("ALBERT HEIJN 1234", "Jumbo Twello", "BOL.COM").
 * Naam op de kaart, naam, aliassen en website uit de catalogus; korte namen (AH) alleen vooraan. Zelfde als iOS.
 */
object PurchaseMatcher {
    fun fold(s: String): String = Normalizer.normalize(s.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")
        .replace("&", " and ").replace("'", "").map { if (it.isLetterOrDigit()) it else ' ' }.joinToString("")
        .split(' ').filter { it.isNotEmpty() }.joinToString(" ")

    fun stem(domain: String): String {
        var d = domain.lowercase().removePrefix("https://").removePrefix("http://").removePrefix("www.")
        d = d.substringBefore('/')
        val parts = d.split('.')
        return fold((if (parts.size > 1) parts.dropLast(1) else parts).joinToString(" "))
    }

    fun terms(card: Card): List<String> {
        val list = mutableListOf(card.storeName)
        Catalog.template(card.templateID)?.let { t -> list += t.name; list += t.aliases; list += stem(t.domain) }
        card.website?.let { list += stem(it) }
        return list.map { fold(it) }.filter { it.length >= 2 }.distinct()
    }

    fun score(merchant: String, term: String): Int? {
        val m = fold(merchant).split(' ').filter { it.isNotEmpty() }
        val t = term.split(' ').filter { it.isNotEmpty() }
        if (m.isEmpty() || t.isEmpty()) return null
        val joined = t.joinToString("")
        for (start in 0..(m.size - t.size).coerceAtLeast(-1)) {
            if (start < 0 || m.subList(start, start + t.size) != t) continue
            if (joined.length < 3 && start != 0) continue
            return joined.length * 10 + if (start == 0) 5 else 0
        }
        if (joined.length >= 5 && m.joinToString("").contains(joined)) return joined.length * 8
        return null
    }

    fun best(merchant: String, cards: List<Card>): Card? = cards
        .filter { it.deletedAt == null && it.kind != CardKind.TICKET }
        .mapNotNull { c -> terms(c).mapNotNull { score(merchant, it) }.maxOrNull()?.let { it to c } }
        .maxWithOrNull(compareBy<Pair<Int, Card>> { it.first }.thenBy { Card.score(it.second) })?.second
}

/** Wanneer een kaart als gebruikt telt (zelfde als UseCapture op iOS). */
object UseCapture {
    const val MIN_VISIBLE_MS = 5_000L
    const val PROMPT_MS = 8_000L

    var asks: Boolean
        get() = Prefs.p.getBoolean("uses.ask", true)
        set(v) = Prefs.p.edit().putBoolean("uses.ask", v).apply()
    var onlyAtStore: Boolean
        get() = Prefs.p.getBoolean("uses.onlyAtStore", true)
        set(v) = Prefs.p.edit().putBoolean("uses.onlyAtStore", v).apply()
    /** Betaalmeldingen lezen (opt-in, standaard uit). */
    var payCapture: Boolean
        get() = Prefs.p.getBoolean("uses.payCapture", false)
        set(v) = Prefs.p.edit().putBoolean("uses.payCapture", v).apply()

    fun applies(card: Card) = card.kind != CardKind.TICKET && card.deletedAt == null

    sealed interface Check {
        data class AtStore(val name: String) : Check
        data object Elsewhere : Check
        data object Unknown : Check
    }

    fun hasLocation(context: Context) =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /**
     * Op Android kent Pasr geen filialen uit een kaartdienst: alleen de eigen locaties van een kaart ("Ik sta hier",
     * ook die van je iPhone via je account). Binnen 300 m van één ervan: vragen met die naam. Heeft de kaart locaties en
     * ben je bij geen ervan: niets vragen. Geen locaties, geen toestemming of geen goede plek: gewoon vragen.
     * De plek wordt één keer opgevraagd (fused provider) en nergens bewaard of verstuurd.
     */
    suspend fun check(context: Context, card: Card): Check {
        if (card.places.isEmpty() || !hasLocation(context)) return Check.Unknown
        val here = currentLocation(context) ?: return Check.Unknown
        if (here.accuracy > 150f) return Check.Unknown
        val near = card.places.map { p ->
            val r = FloatArray(1)
            Location.distanceBetween(here.latitude, here.longitude, p.latitude, p.longitude, r)
            p to r[0]
        }.minByOrNull { it.second } ?: return Check.Unknown
        return if (near.second < 300f) Check.AtStore(near.first.name.substringBefore(" · ").ifBlank { card.storeName }) else Check.Elsewhere
    }

    @SuppressLint("MissingPermission")
    suspend fun currentLocation(context: Context): Location? = withContext(Dispatchers.Main) {
        if (!hasLocation(context)) return@withContext null
        val lm = context.getSystemService(LocationManager::class.java) ?: return@withContext null
        val provider = when {
            Build.VERSION.SDK_INT >= 31 && lm.isProviderEnabled(LocationManager.FUSED_PROVIDER) -> LocationManager.FUSED_PROVIDER
            lm.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> return@withContext null
        }
        lm.getLastKnownLocation(provider)?.takeIf { nowMs() - it.time < 120_000 }?.let { return@withContext it }
        withTimeoutOrNull(8_000) {
            suspendCancellableCoroutine<Location?> { cont ->
                if (Build.VERSION.SDK_INT >= 30) {
                    val signal = android.os.CancellationSignal()
                    cont.invokeOnCancellation { signal.cancel() }
                    lm.getCurrentLocation(provider, signal, ContextCompat.getMainExecutor(context)) { loc ->
                        if (cont.isActive) cont.resume(loc)
                    }
                } else {
                    val listener = object : android.location.LocationListener {
                        override fun onLocationChanged(location: Location) { if (cont.isActive) cont.resume(location) }
                        @Deprecated("Deprecated in Java")
                        override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
                        override fun onProviderEnabled(provider: String) {}
                        override fun onProviderDisabled(provider: String) {}
                    }
                    cont.invokeOnCancellation { lm.removeUpdates(listener) }
                    @Suppress("DEPRECATION")
                    lm.requestSingleUpdate(provider, listener, android.os.Looper.getMainLooper())
                }
            }
        }
    }

    /** Dichtbij een eigen locatie (voor "Ik sta hier"): dezelfde plek niet twee keer. */
    fun isNew(card: Card, loc: Location) = card.places.none { p ->
        val r = FloatArray(1); Location.distanceBetween(loc.latitude, loc.longitude, p.latitude, p.longitude, r); r[0] < 60f
    }
}

/**
 * Een betaling verwerken (uit een betaalmelding, alleen op het toestel): passende kaart zoeken en een moment met het
 * bedrag zetten. Cadeaukaart: het bedrag wacht op "Afboeken" in de melding. Geen kaart: niets bewaard.
 * De winkelnaam uit de melding wordt nergens bewaard of verstuurd.
 */
object PurchaseCapture {
    data class Outcome(val card: Card?, val useId: String?, val pending: Double?)

    fun record(merchant: String, amount: Double?, at: Long = nowMs()): Outcome {
        val card = PurchaseMatcher.best(merchant, CardStore.visible) ?: return Outcome(null, null, null)
        var (updated, useId) = card.used(source = "pay", at = at)
        val use = updated.history.first { it.id == useId }
        var pending: Double? = null
        if (amount != null && amount > 0 && use.amount == null) {
            if (card.kind == CardKind.VOUCHER) {
                updated = updated.updatingUse(useId) { it.copy(pendingAmount = amount) }
                pending = amount
            } else {
                updated = updated.withAmount(amount, useId)
            }
        }
        CardStore.upsert(updated)
        return Outcome(updated, useId, pending)
    }

    fun book(cardId: String, useId: String) {
        val card = CardStore.get(cardId) ?: return
        val pending = card.history.firstOrNull { it.id == useId }?.pendingAmount ?: return
        CardStore.upsert(card.withAmount(pending, useId))
    }

    fun skip(cardId: String, useId: String) {
        val card = CardStore.get(cardId) ?: return
        CardStore.upsert(card.updatingUse(useId) { it.copy(pendingAmount = null) })
    }

    /** Merchant en €-bedrag uit een betaalmelding; null als het geen betaalmelding met een €-bedrag is. */
    data class Payment(val merchant: String, val amount: Double)

    private val euro = Regex("""(?:€|EUR)\s?-?\s?(\d{1,3}(?:[.\s]\d{3})*(?:[,.]\d{2})|\d+(?:[,.]\d{2})?)|(\d{1,3}(?:[.\s]\d{3})*[,.]\d{2})\s?(?:€|EUR)""",
        RegexOption.IGNORE_CASE)
    private val payWords = listOf("betaald", "betaling", "betaal", "paid", "payment", "transactie", "transaction", "aankoop",
        "purchase", "pinbetaling", "contactloos", "afgeschreven", "uitgegeven")
    private val generic = listOf("google wallet", "google pay", "betaling", "betaald", "payment", "transactie", "aankoop",
        "ing", "rabobank", "abn amro", "bunq", "asn bank", "sns", "regiobank", "knab", "revolut", "n26", "triodos")
    private val merchantAfter = Regex("""(?i)\b(?:bij|aan|at|to|in)\s+([A-Za-z0-9][\w'&.\- ]{1,40}?)(?:\s+(?:met|with|via|voor|for|op|on)\b|[.,:;]|$)""")

    /**
     * Google Wallet zet de winkel in de titel en het bedrag in de tekst ("€ 12,34 met Visa ••1234"); bank-apps meestal
     * "Je hebt € 12,34 betaald bij ALBERT HEIJN". Alleen meldingen met een €-bedrag; andere apps dan Google Wallet ook
     * alleen met een betaalwoord.
     */
    fun parse(packageName: String, title: String?, text: String?, knownPayApp: Boolean): Payment? {
        val all = listOfNotNull(title, text).joinToString(" \n ")
        val m = euro.find(all) ?: return null
        val amount = ReceiptParser.parseAmount(m.value) ?: return null
        if (!knownPayApp && payWords.none { all.lowercase().contains(it) }) return null
        val t = title?.trim().orEmpty()
        val titleIsMerchant = t.isNotEmpty() && euro.find(t) == null && generic.none { t.lowercase().startsWith(it) } &&
            payWords.none { t.lowercase().contains(it) }
        val merchant = when {
            titleIsMerchant -> t
            else -> merchantAfter.find(text.orEmpty())?.groupValues?.get(1)?.trim()
        } ?: return null
        if (merchant.length < 2) return null
        return Payment(merchant, amount)
    }

    /** Google Wallet en bekende bank-apps in Nederland; andere apps alleen met een betaalwoord en een €-bedrag. */
    val knownPayApps = setOf(
        "com.google.android.apps.walletnfcrel", "com.google.android.apps.nbu.paisa.user",
        "com.ing.mobile", "nl.rabomobiel", "com.abnamro.nl.mobile.payments", "com.bunq.android", "nl.asnbank.mobiel",
        "nl.snsbank.mobiel", "nl.regiobank.mobiel", "com.knab.app", "com.revolut.revolut", "de.number26.android",
        "nl.triodos.mobiel",
    )

    /** Hoe ver twee momenten uit elkaar liggen in minuten (voor previews en tests). */
    fun minutesApart(a: Long, b: Long) = abs(a - b) / 60_000
}
