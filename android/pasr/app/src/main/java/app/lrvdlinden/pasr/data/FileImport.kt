package app.lrvdlinden.pasr.data

import android.content.Context
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.zip.ZipInputStream

internal fun InputStream.readBounded(limit: Int): ByteArray {
    val data = readNBytesCompat(limit + 1)
    require(data.size <= limit)
    return data
}

private fun InputStream.readNBytesCompat(limit: Int): ByteArray {
    val output = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(8192)
    while (output.size() < limit) {
        val count = read(buffer, 0, minOf(buffer.size, limit - output.size()))
        if (count <= 0) break
        output.write(buffer, 0, count)
    }
    return output.toByteArray()
}

internal fun readImportedCards(context: Context, uri: Uri): List<Card> {
    val data = requireNotNull(context.contentResolver.openInputStream(uri)).use { it.readBounded(30_000_000) }
    if (data.size >= 4 && data[0] == 0x50.toByte() && data[1] == 0x4B.toByte()) {
        return ZipInputStream(ByteArrayInputStream(data)).use { zip ->
            val entry = requireNotNull(zip.nextEntry)
            // Limit expansion even while skipping entries from untrusted archives.
            var remaining = 30_000_000
            var name: String? = entry.name
            while (name != null) {
                val bytes = zip.readBounded(remaining)
                if (name == "pass.json") {
                    val pass = JSONObject(bytes.decodeToString())
                    val barcode = pass.optJSONArray("barcodes")?.optJSONObject(0) ?: pass.getJSONObject("barcode")
                    val row = mapOf(
                        "name" to pass.optString("organizationName").ifBlank { pass.optString("description") },
                        "number" to barcode.getString("message"),
                        "format" to barcode.optString("format").removePrefix("PKBarcodeFormat"),
                        "kind" to when {
                            pass.has("boardingPass") || pass.has("eventTicket") -> "ticket"
                            pass.has("coupon") -> "coupon"
                            else -> "loyalty"
                        },
                        "expires" to pass.optString("expirationDate"),
                    )
                    return@use listOfNotNull(importedCard(row))
                }
                remaining -= bytes.size
                name = zip.nextEntry?.name
            }
            error("Wallet-bestand zonder pass.json")
        }
    }

    val text = data.decodeToString().removePrefix("\uFEFF").trim()
    val rows = when (text.firstOrNull()) {
        '[' -> jsonRows(JSONArray(text))
        '{' -> {
            val obj = JSONObject(text)
            val list = listOf("cards", "kaarten", "items", "data").firstNotNullOfOrNull(obj::optJSONArray)
            if (list != null) jsonRows(list) else listOf(jsonRow(obj))
        }
        else -> csvRows(text)
    }
    return rows.mapNotNull(::importedCard)
}

private fun key(s: String): String = s.lowercase(Locale.ROOT).filter(Char::isLetterOrDigit)

private fun jsonRows(array: JSONArray): List<Map<String, String>> =
    (0 until array.length()).mapNotNull { array.optJSONObject(it)?.let(::jsonRow) }

private fun jsonRow(obj: JSONObject): Map<String, String> = buildMap {
    for (name in obj.keys()) {
        val value = obj.opt(name)
        when (value) {
            is String, is Number -> put(key(name), value.toString())
            is JSONObject -> for (field in listOf("message", "value", "number", "format")) {
                val fieldValue = value.opt(field)
                if (fieldValue is String || fieldValue is Number) {
                    putIfAbsent(if (field == "format") "format" else key(name), fieldValue.toString())
                }
            }
        }
    }
}

private fun csvRows(text: String): List<Map<String, String>> {
    val header = text.lineSequence().first()
    val separator = listOf(';', '\t', ',').maxBy { delimiter -> csvFields(header, delimiter).size }
    val columns = csvFields(header, separator).map(::key)
    return text.lineSequence().drop(1).filter { it.isNotBlank() }
        .map { columns.zip(csvFields(it, separator)).toMap() }.toList()
}

private fun csvFields(line: String, separator: Char): List<String> {
    val fields = mutableListOf<String>()
    val field = StringBuilder()
    var quoted = false
    var index = 0
    while (index < line.length) {
        val char = line[index++]
        when {
            char == '"' && quoted && line.getOrNull(index) == '"' -> { field.append('"'); index++ }
            char == '"' -> quoted = !quoted
            char == separator && !quoted -> { fields.add(field.toString()); field.clear() }
            else -> field.append(char)
        }
    }
    fields.add(field.toString())
    return fields
}

private fun importedCard(row: Map<String, String>): Card? {
    fun value(vararg aliases: String): String? =
        aliases.firstNotNullOfOrNull { row[it]?.trim()?.takeIf(String::isNotEmpty) }

    val number = value("nummer", "number", "kaartnummer", "cardnumber", "code", "barcode", "barcodevalue", "value", "klantnummer", "membernumber")
        ?: return null
    val name = value("naam", "name", "winkel", "store", "storename", "merchant", "brand", "title")
    val rawFormat = value("formaat", "format", "barcodeformat", "symbology")?.let(::key)
    val format = when (rawFormat) {
        "qrcode" -> BarcodeFormat.QR
        "upc" -> BarcodeFormat.UPCA
        else -> BarcodeFormat.entries.firstOrNull { key(it.raw) == rawFormat }
    }
    val balance = value("saldo", "balance", "tegoed", "amount", "bedrag")?.let {
        val cleaned = it.filter { c -> c.isDigit() || c in ",.-" }
        (if (',' in cleaned) cleaned.replace(".", "").replace(',', '.') else cleaned)
            .toDoubleOrNull()?.takeIf(Double::isFinite)
    }
    val type = value("soort", "kind", "kindraw", "type", "cardtype").orEmpty().lowercase(Locale.ROOT)
    val kind = when {
        listOf("cadeau", "voucher", "gift").any(type::contains) -> CardKind.VOUCHER
        listOf("coupon", "code", "korting", "discount", "promo").any(type::contains) || rawFormat in listOf("text", "tekst") -> CardKind.CODE
        listOf("ticket", "event", "boarding").any(type::contains) -> CardKind.TICKET
        listOf("abonnement", "subscription", "membership").any(type::contains) -> CardKind.SUBSCRIPTION
        balance != null -> CardKind.VOUCHER
        else -> CardKind.LOYALTY
    }
    val date = value("vervaldatum", "expires", "expiresat", "expiry", "expirationdate", "validuntil")?.let { date ->
        runCatching { Instant.parse(date).toEpochMilli() }.getOrNull()
            ?: listOf("uuuu-MM-dd", "d-M-uuuu", "d/M/uuuu", "d.M.uuuu").firstNotNullOfOrNull { pattern ->
                runCatching {
                    LocalDate.parse(date, DateTimeFormatter.ofPattern(pattern))
                        .atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
                }.getOrNull()
            }
    }
    val color = value("kleur", "color", "colorhex")?.removePrefix("#")?.takeIf { it.matches(Regex("[0-9a-fA-F]{6}")) }
    val template = name?.let { Catalog.search(it, kind).firstOrNull { entry -> Catalog.fold(entry.name) == Catalog.fold(it) } }
    return Card(
        storeName = name.orEmpty().take(60),
        number = number.take(200),
        templateID = template?.id,
        kindRaw = kind.raw,
        formatRaw = (format ?: BarcodeFormat.guess(number)).raw,
        colorHex = color?.let { "#$it" } ?: "#2B2F3A",
        note = value("notitie", "note", "notes", "opmerking", "description").orEmpty().take(500),
        balance = balance,
        expiresAt = date,
        details = CardDetails(codeAsBarcode = true.takeIf { kind == CardKind.CODE && format != null }),
    )
}
