package app.lrvdlinden.pasrzakelijk.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.R
import app.lrvdlinden.pasrzakelijk.core.L

/** Kaart met achtergrond en rand. */
@Composable
fun CardBox(modifier: Modifier = Modifier, padding: Dp = 16.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Pz.card)
            .border(1.dp, Pz.line, RoundedCornerShape(18.dp))
            .padding(padding),
        content = content,
    )
}

/** Grote knop in de stijl van Pasr. */
@Composable
fun BigButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    color: Color = Pz.accent,
    foreground: Color = Color.White,
    enabled: Boolean = true,
    busy: Boolean = false,
) {
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(color)
            .alpha(if (enabled) 1f else 0.55f)
            .clickable(enabled = enabled && !busy, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (busy) {
            CircularProgressIndicator(Modifier.size(22.dp), color = foreground, strokeWidth = 2.5.dp)
        } else {
            if (icon != null) {
                Icon(icon, null, tint = foreground, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
            }
            Text(text, color = foreground, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, textAlign = TextAlign.Center)
        }
    }
}

/** Kleine tekstknop (links in formulieren). */
@Composable
fun LinkButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, color: Color = Pz.accent, enabled: Boolean = true) {
    Text(
        text,
        color = color,
        fontWeight = FontWeight.SemiBold,
        fontSize = 15.sp,
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .alpha(if (enabled) 1f else 0.5f)
            .padding(horizontal = 4.dp, vertical = 8.dp),
    )
}

/** Woordmerk "pasr ZAKELIJK" met het icoon. */
@Composable
fun ZakelijkLogo(size: Float = 24f, modifier: Modifier = Modifier) {
    Row(
        modifier.semantics(mergeDescendants = true) { contentDescription = "Pasr Zakelijk" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy((size * 0.4f).dp),
    ) {
        Image(
            painterResource(R.drawable.app_icon_display), null,
            Modifier.size((size * 1.5f).dp).clip(RoundedCornerShape((size * 0.36f).dp)),
        )
        Text("pasr", fontSize = size.sp, fontWeight = FontWeight.Black, letterSpacing = (-size * 0.03f).sp, color = Pz.text)
        Text(
            L("ZAKELIJK"),
            fontSize = maxOf(9f, size * 0.42f).sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp, color = Pz.mint,
            modifier = Modifier
                .border(1.dp, Pz.mint.copy(alpha = 0.6f), CircleShape)
                .padding(horizontal = 7.dp, vertical = 2.dp),
        )
    }
}

/** Invoerveld in de stijl van Pasr. */
@Composable
fun PzField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    keyboardType: KeyboardType = KeyboardType.Text,
    capitalization: androidx.compose.ui.text.input.KeyboardCapitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Sentences,
    imeAction: androidx.compose.ui.text.input.ImeAction = androidx.compose.ui.text.input.ImeAction.Next,
    onIme: (() -> Unit)? = null,
    password: Boolean = false,
    singleLine: Boolean = true,
    minLines: Int = 1,
    monospace: Boolean = false,
    autoCorrect: Boolean = true,
) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder, color = Pz.muted) },
        modifier = modifier.fillMaxWidth().defaultMinSize(minHeight = 50.dp),
        singleLine = singleLine,
        minLines = minLines,
        textStyle = TextStyle(
            fontSize = 17.sp, color = Pz.text,
            fontFamily = if (monospace) androidx.compose.ui.text.font.FontFamily.Monospace else null,
        ),
        visualTransformation = if (password) androidx.compose.ui.text.input.PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(capitalization = capitalization, keyboardType = keyboardType, imeAction = imeAction, autoCorrectEnabled = autoCorrect),
        keyboardActions = KeyboardActions(onAny = { onIme?.invoke() }),
        shape = RoundedCornerShape(12.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Pz.card2, unfocusedContainerColor = Pz.card2, disabledContainerColor = Pz.card2,
            focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent, cursorColor = Pz.accent,
        ),
    )
}

@Composable
fun ErrorLine(text: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Filled.Warning, null, tint = Pz.coral, modifier = Modifier.size(18.dp).padding(top = 1.dp))
        Text(text, color = Pz.coral, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
    }
}

@Composable
fun SuccessLine(text: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Filled.CheckCircle, null, tint = Pz.mint, modifier = Modifier.size(18.dp).padding(top = 1.dp))
        Text(text, color = Pz.mint, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
    }
}

/** Kop boven een groep (zoals een sectiekop in een iOS-lijst). */
@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(), color = Pz.muted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp,
        modifier = modifier.padding(start = 6.dp, top = 18.dp, bottom = 6.dp),
    )
}

@Composable
fun SectionFooter(text: String, modifier: Modifier = Modifier) {
    Text(text, color = Pz.muted, fontSize = 13.sp, modifier = modifier.padding(start = 6.dp, end = 6.dp, top = 6.dp))
}

/** Groep met regels, afgerond, met scheidingslijnen. */
@Composable
fun Group(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Pz.card),
        content = content,
    )
}

@Composable
fun GroupDivider() = HorizontalDivider(Modifier.padding(start = 16.dp), color = Pz.line, thickness = 0.7.dp)

/** Regel in een groep met een gekleurd icoon (zelfde stijl als Instellingen in Pasr). */
@Composable
fun SettingsRow(
    title: String,
    icon: ImageVector? = null,
    color: Color = Pz.iris,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    titleColor: Color = Pz.text,
    external: Boolean = false,
    enabled: Boolean = true,
    onClick: (() -> Unit)? = null,
    trailing: @Composable (RowScope.() -> Unit)? = null,
) {
    Row(
        modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(enabled = enabled, onClick = onClick) else Modifier)
            .alpha(if (enabled) 1f else 0.5f)
            .heightIn(min = 52.dp)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (icon != null) {
            Box(
                Modifier.size(29.dp).clip(RoundedCornerShape(7.dp))
                    .background(Brush.verticalGradient(listOf(color, color.copy(alpha = 0.82f)))),
                contentAlignment = Alignment.Center,
            ) { Icon(icon, null, tint = Color.White, modifier = Modifier.size(17.dp)) }
        }
        Column(Modifier.weight(1f)) {
            Text(title, color = titleColor, fontSize = 17.sp)
            if (subtitle != null) Text(subtitle, color = Pz.muted, fontSize = 13.sp)
        }
        trailing?.invoke(this)
        if (external) Icon(Icons.AutoMirrored.Filled.OpenInNew, null, tint = Pz.muted.copy(alpha = 0.6f), modifier = Modifier.size(16.dp))
    }
}

/** Lege staat of foutmelding midden in een scherm. */
@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    text: String? = null,
    modifier: Modifier = Modifier,
    actions: @Composable (ColumnScope.() -> Unit)? = null,
) {
    Column(
        modifier.fillMaxWidth().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(icon, null, tint = Pz.muted, modifier = Modifier.size(44.dp))
        Text(title, fontWeight = FontWeight.Bold, fontSize = 20.sp, color = Pz.text, textAlign = TextAlign.Center)
        if (text != null) Text(text, color = Pz.muted, textAlign = TextAlign.Center, fontSize = 15.sp)
        if (actions != null) {
            Spacer(Modifier.size(6.dp))
            actions()
        }
    }
}

@Composable
fun CenteredProgress(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Pz.accent) }
}

/** Pil-segmenten zoals Homey Insights. */
@Composable
fun <T> PillSegments(items: List<Pair<T, String>>, selection: T, onSelect: (T) -> Unit, spoken: Map<T, String> = emptyMap()) {
    val haptics = rememberHaptics()
    Row(
        Modifier.fillMaxWidth().clip(CircleShape).background(Pz.insightsPill).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for ((value, label) in items) {
            val on = value == selection
            Box(
                Modifier
                    .weight(1f)
                    .clip(CircleShape)
                    .background(if (on) Pz.text.copy(alpha = 0.15f) else Color.Transparent)
                    .clickable { if (!on) { haptics.tick(); onSelect(value) } }
                    .semantics { spoken[value]?.let { contentDescription = it } }
                    .padding(vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(label, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = if (on) Pz.text else Pz.muted)
            }
        }
    }
}

/** Scherm-achtergrond met ruimte rond de inhoud. */
val ScreenPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp)

/** Trillen bij succes, fout en keuze (zoals sensoryFeedback op iOS). */
class Haptics(private val view: View) {
    fun success() = view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY)
    fun error() = view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS)
    fun tick() = view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
}

@Composable
fun rememberHaptics(): Haptics = Haptics(LocalView.current)

fun Context.openUrl(url: String) {
    try {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
    }
}

/** Deelvenster met tekst (link), zoals ShareLink op iOS. */
fun Context.shareText(text: String, subject: String? = null) {
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, text)
        if (subject != null) putExtra(Intent.EXTRA_SUBJECT, subject)
    }
    runCatching { startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

@Composable
fun rememberOpenUrl(): (String) -> Unit {
    val context = LocalContext.current
    return { context.openUrl(it) }
}

/** Voorbeeldweergave (Android Studio of de schermafbeeldingen in CI): geen camera, biometrie of vensters. */
@Composable
fun isPreview(): Boolean = androidx.compose.ui.platform.LocalInspectionMode.current || app.lrvdlinden.pasrzakelijk.data.Demo.enabled
