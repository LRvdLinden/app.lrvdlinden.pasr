package app.lrvdlinden.pasrzakelijk.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import app.lrvdlinden.pasrzakelijk.core.Prefs
import kotlin.math.pow

/** Huisstijl van Pasr (zelfde kleuren als de app Pasr, de iOS-app Pasr Zakelijk en pasr.nl), mint als Zakelijk-accent. */
object Pz {
    val iris = Color(0xFF6A5CFF)
    val coral = Color(0xFFFF6B57)
    val mint = Color(0xFF2ED3A6)
    val amber = Color(0xFFFFB547)
    val sky = Color(0xFF4FB3FF)
    val ink = Color(0xFF17162A)
    val night = Color(0xFF0A0B10)
    /** Accentkleur van de app (knoppen). */
    val accent = iris
    val gradient = Brush.linearGradient(listOf(iris, coral))

    /** Kleuren voor stempelkaarten (zelfde als het dashboard op pasr.nl en de iOS-app). */
    val swatches = listOf("#6A5CFF", "#17162A", "#E30613", "#FF6B57", "#E2683C", "#F2B705",
        "#2ED3A6", "#12A77E", "#0A84FF", "#7B4B2A", "#AF52DE", "#FF375F")

    val bg: Color @Composable @ReadOnlyComposable get() = if (LocalDark.current) Color(0xFF0A0B10) else Color(0xFFF4F3FF)
    val card: Color @Composable @ReadOnlyComposable get() = if (LocalDark.current) Color(0xFF15171F) else Color.White
    val card2: Color @Composable @ReadOnlyComposable get() = if (LocalDark.current) Color(0xFF1C1F29) else Color(0xFFECEBFA)
    val line: Color @Composable @ReadOnlyComposable get() = if (LocalDark.current) Color(0xFF262A37) else Color(0xFFE1DFF2)
    val muted: Color @Composable @ReadOnlyComposable get() = if (LocalDark.current) Color(0xFF9A98B3) else Color(0xFF5F5D78)
    val text: Color @Composable @ReadOnlyComposable get() = if (LocalDark.current) Color(0xFFF2F1FA) else Color(0xFF17162A)

    /** Grafiekkaart in de stijl van Homey Insights: kaart, pillen en raster (licht/donker). */
    val insightsCard: Color @Composable @ReadOnlyComposable get() = if (LocalDark.current) Color(0xFF1C1D26) else Color.White
    val insightsPill: Color @Composable @ReadOnlyComposable get() = if (LocalDark.current) Color(0xFF2A2B36) else Color(0xFFF1F2F6)
    val insightsGrid: Color @Composable @ReadOnlyComposable get() = if (LocalDark.current) Color(0xFF3A3C4A) else Color(0xFFE3E5EC)
}

val LocalDark = staticCompositionLocalOf { false }

fun hexColor(hex: String?): Color {
    var s = hex?.trim() ?: return Pz.iris
    if (s.startsWith("#")) s = s.drop(1)
    val v = s.takeIf { it.length == 6 }?.toLongOrNull(16) ?: return Pz.iris
    return Color(0xFF000000 or v)
}

fun Color.toHex(): String = String.format("#%06X", 0xFFFFFF and toArgb())

/** Wit of bijna-zwart, wat het best leest op een kaart van deze kleur. */
fun onCard(hex: String): Color {
    val c = hexColor(hex)
    fun lin(v: Float): Double = if (v <= 0.03928) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
    val l = 0.2126 * lin(c.red) + 0.7152 * lin(c.green) + 0.0722 * lin(c.blue)
    return if (l > 0.45) Color(0xFF111216) else Color.White
}

@Composable
fun PasrTheme(dark: Boolean = when (Prefs.appearance) { "light" -> false; "dark" -> true; else -> isSystemInDarkTheme() },
              content: @Composable () -> Unit) {
    val scheme = if (dark) darkColorScheme(
        primary = Pz.iris, onPrimary = Color.White, secondary = Pz.mint, onSecondary = Color.Black, tertiary = Pz.coral,
        background = Color(0xFF0A0B10), surface = Color(0xFF15171F), surfaceVariant = Color(0xFF1C1F29),
        surfaceContainer = Color(0xFF15171F), surfaceContainerHigh = Color(0xFF1C1F29), surfaceContainerLow = Color(0xFF111319),
        onBackground = Color(0xFFF2F1FA), onSurface = Color(0xFFF2F1FA), onSurfaceVariant = Color(0xFF9A98B3),
        outline = Color(0xFF3A3C4A), outlineVariant = Color(0xFF262A37), error = Pz.coral,
        secondaryContainer = Color(0xFF2A2B48), onSecondaryContainer = Color.White,
    ) else lightColorScheme(
        primary = Pz.iris, onPrimary = Color.White, secondary = Pz.mint, onSecondary = Color.Black, tertiary = Pz.coral,
        background = Color(0xFFF4F3FF), surface = Color.White, surfaceVariant = Color(0xFFECEBFA),
        surfaceContainer = Color.White, surfaceContainerHigh = Color(0xFFECEBFA), surfaceContainerLow = Color(0xFFF8F7FF),
        onBackground = Color(0xFF17162A), onSurface = Color(0xFF17162A), onSurfaceVariant = Color(0xFF5F5D78),
        outline = Color(0xFFCFCDE6), outlineVariant = Color(0xFFE1DFF2), error = Color(0xFFE0442F),
        secondaryContainer = Color(0xFFE4E0FF), onSecondaryContainer = Color(0xFF17162A),
    )
    CompositionLocalProvider(LocalDark provides dark) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
