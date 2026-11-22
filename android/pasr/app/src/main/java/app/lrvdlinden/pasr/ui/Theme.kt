package app.lrvdlinden.pasr.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import kotlin.math.pow

/** Huisstijl van Pasr (zelfde kleuren als Brand.swift). */
object Brand {
    val ink = Color(0xFFF4F3FF)
    val inkDark = Color(0xFF0A0B10)
    val raised = Color(0xFFFFFFFF)
    val raisedDark = Color(0xFF15171F)
    val night = Color(0xFF0A0B10)
    val iris = Color(0xFF6A5CFF)
    val coral = Color(0xFFFF6B57)
    val mint = Color(0xFF2ED3A6)
    val mintDeep = Color(0xFF0E8A62)
    val gradient = Brush.linearGradient(listOf(iris, coral))

    val palette = listOf(
        "#6A5CFF", "#FF6B57", "#2ED3A6", "#0A84FF", "#FF9F0A", "#FF375F",
        "#30B0C7", "#5E5CE6", "#34C759", "#AF52DE", "#1C1C1E", "#8E8E93",
    )
    const val CARD_ASPECT = 1.586f

    // lrvdlinden.app (Meer apps-kaart)
    val lrAccentLight = Color(0xFF2747E8)
    val lrAccentDark = Color(0xFF8A9DFF)
    val lrTile = Color(0xFF121726)
    val lrDot = Color(0xFF4C6BFF)
}

fun hexColor(hex: String?): Color {
    var s = hex?.trim()?.removePrefix("#") ?: return Color(0xFF2B2F3A)
    if (s.length != 6) return Color(0xFF2B2F3A)
    val v = s.toLongOrNull(16) ?: return Color(0xFF2B2F3A)
    return Color(0xFF000000 or v)
}

fun Color.toHex(): String {
    fun c(x: Float) = (x.coerceIn(0f, 1f) * 255 + 0.5f).toInt()
    return "#%02X%02X%02X".format(c(red), c(green), c(blue))
}

/** Wit of bijna-zwart, wat het best leest op een kaart van deze kleur. */
fun onCard(hex: String?): Color {
    val c = hexColor(hex)
    fun lin(x: Float): Double = if (x <= 0.03928f) x / 12.92 else ((x + 0.055) / 1.055).pow(2.4)
    val l = 0.2126 * lin(c.red) + 0.7152 * lin(c.green) + 0.0722 * lin(c.blue)
    return if (l > 0.45) Color(0xFF111216) else Color.White
}

fun shade(hex: String?, amount: Float): Color {
    val c = hexColor(hex)
    fun a(x: Float) = if (amount >= 0) x + (1 - x) * amount else x * (1 + amount)
    return Color(a(c.red), a(c.green), a(c.blue))
}

val LocalDark = compositionLocalOf { false }

@Composable
fun PasrTheme(appearance: String, content: @Composable () -> Unit) {
    val dark = when (appearance) { "light" -> false; "dark" -> true; else -> isSystemInDarkTheme() }
    val scheme = if (dark) darkColorScheme(
        primary = Brand.iris, onPrimary = Color.White, secondary = Brand.coral, tertiary = Brand.mint,
        background = Brand.inkDark, onBackground = Color(0xFFF2F2F7), surface = Brand.inkDark, onSurface = Color(0xFFF2F2F7),
        surfaceContainer = Brand.raisedDark, surfaceContainerHigh = Color(0xFF1E212B), surfaceContainerLow = Color(0xFF111319),
        surfaceVariant = Color(0xFF1E212B), onSurfaceVariant = Color(0xFF9EA3B5), outline = Color(0xFF2C303C),
        outlineVariant = Color(0xFF242733), error = Color(0xFFFF6B6F),
    ) else lightColorScheme(
        primary = Brand.iris, onPrimary = Color.White, secondary = Brand.coral, tertiary = Brand.mintDeep,
        background = Brand.ink, onBackground = Color(0xFF111216), surface = Brand.ink, onSurface = Color(0xFF111216),
        surfaceContainer = Brand.raised, surfaceContainerHigh = Color(0xFFEDEBFB), surfaceContainerLow = Color(0xFFF9F8FF),
        surfaceVariant = Color(0xFFEDEBFB), onSurfaceVariant = Color(0xFF5E6072), outline = Color(0xFFD9D6EE),
        outlineVariant = Color(0xFFE6E3F5), error = Color(0xFFC8372F),
    )
    androidx.compose.runtime.CompositionLocalProvider(LocalDark provides dark) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
