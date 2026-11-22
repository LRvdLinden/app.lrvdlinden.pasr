package app.lrvdlinden.pasrzakelijk.data

import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Losse JSON-lezer (zelfde als JSONObject.swift in de iOS-app): elk veld optioneel, meerdere namen voor hetzelfde veld,
 * zodat een kleine naamswijziging op de server de app niet breekt.
 */
class J(val raw: JSONObject) {
    companion object {
        fun of(any: Any?): J? = when (any) {
            is JSONObject -> J(any)
            is JSONArray -> (if (any.length() > 0) any.opt(0) as? JSONObject else null)?.let { J(it) }
            else -> null
        }
    }

    private fun value(key: String): Any? = raw.opt(key)?.takeUnless { it == JSONObject.NULL }

    fun string(vararg keys: String): String? {
        for (k in keys) {
            when (val v = value(k)) {
                is String -> if (v.isNotBlank()) return v
                is Number -> return if (v is Double && v % 1.0 == 0.0) v.toLong().toString() else v.toString()
                is Boolean -> return v.toString()
            }
        }
        return null
    }

    fun int(vararg keys: String): Int? {
        for (k in keys) {
            when (val v = value(k)) {
                is Number -> return v.toInt()
                is String -> v.trim().toIntOrNull()?.let { return it }
            }
        }
        return null
    }

    fun double(vararg keys: String): Double? {
        for (k in keys) {
            when (val v = value(k)) {
                is Number -> return v.toDouble()
                is String -> v.trim().toDoubleOrNull()?.let { return it }
            }
        }
        return null
    }

    fun bool(vararg keys: String): Boolean? {
        for (k in keys) {
            when (val v = value(k)) {
                is Boolean -> return v
                is Number -> return v.toInt() != 0
                is String -> return v.lowercase() in setOf("true", "t", "1", "yes")
            }
        }
        return null
    }

    fun date(vararg keys: String): Date? {
        for (k in keys) (value(k) as? String)?.let { s -> JsonDates.parse(s)?.let { return it } }
        return null
    }

    fun obj(vararg keys: String): J? {
        for (k in keys) (value(k) as? JSONObject)?.let { return J(it) }
        return null
    }

    fun array(vararg keys: String): List<J> {
        for (k in keys) {
            val a = value(k) as? JSONArray ?: continue
            return (0 until a.length()).mapNotNull { (a.opt(it) as? JSONObject)?.let(::J) }
        }
        return emptyList()
    }

    fun has(key: String): Boolean = value(key) != null
}

fun JSONArray.objects(): List<J> = (0 until length()).mapNotNull { (opt(it) as? JSONObject)?.let(::J) }

object JsonDates {
    private val amsterdam = TimeZone.getTimeZone("Europe/Amsterdam")

    private fun fmt(pattern: String, tz: TimeZone = TimeZone.getTimeZone("UTC")) =
        SimpleDateFormat(pattern, Locale.US).apply { timeZone = tz; isLenient = false }

    /** "2026-11-22T10:11:12.123456+00:00", "2026-11-22 10:11:12+00", "2026-11-22". */
    fun parse(value: String): Date? {
        var s = value.trim()
        if (s.length == 10) return runCatching { fmt("yyyy-MM-dd", amsterdam).parse(s) }.getOrNull()
        s = s.replace(' ', 'T')
        // fracties inkorten tot milliseconden
        s = s.replace(Regex("\\.(\\d{1,3})\\d*")) { m -> "." + m.groupValues[1].padEnd(3, '0') }
        if (s.endsWith("Z")) s = s.dropLast(1) + "+00:00"
        if (Regex("[+-]\\d{2}$").containsMatchIn(s)) s += ":00"
        val hasFraction = s.contains('.')
        val pattern = if (hasFraction) "yyyy-MM-dd'T'HH:mm:ss.SSSXXX" else "yyyy-MM-dd'T'HH:mm:ssXXX"
        return runCatching { fmt(pattern).parse(s) }.getOrNull()
    }

    fun day(date: Date): String = fmt("yyyy-MM-dd", amsterdam).format(date)
}
