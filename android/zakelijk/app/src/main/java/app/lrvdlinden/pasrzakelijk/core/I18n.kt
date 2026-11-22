package app.lrvdlinden.pasrzakelijk.core

import java.util.Locale

/**
 * Teksten in het Nederlands (bron) en Engels, met dezelfde sleutels als de iOS-app (Localizable.xcstrings).
 * De Engelse tabel wordt gemaakt door tools/make_strings.py. Opmaak zoals iOS: %@, %lld, %d (op volgorde).
 */
object I18n {
    /** true = Nederlands, anders Engels (zoals de iOS-app: nl of en). */
    @Volatile var dutch: Boolean = Locale.getDefault().language == "nl"

    fun update(locale: Locale) { dutch = locale.language == "nl" }

    val languageCode: String get() = if (dutch) "nl" else "en"

    fun tr(key: String): String = if (dutch) key else (EnStrings.map[key] ?: key)

    fun format(template: String, vararg args: Any?): String {
        if (args.isEmpty()) return template
        val out = StringBuilder()
        var i = 0
        var next = 0
        val regex = Regex("%(?:(\\d+)\\$)?(@|lld|ld|d|s)")
        var last = 0
        for (m in regex.findAll(template)) {
            out.append(template, last, m.range.first)
            val pos = m.groupValues[1].toIntOrNull()?.minus(1) ?: next++
            out.append(args.getOrNull(pos)?.toString() ?: "")
            last = m.range.last + 1
            i++
        }
        out.append(template.substring(last))
        return out.toString().replace("%%", "%")
    }
}

/** Vertaalde tekst bij een Nederlandse sleutel, eventueel met waarden. */
fun L(key: String, vararg args: Any?): String = I18n.format(I18n.tr(key), *args)
