package app.lrvdlinden.pasr.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.CardEvent
import app.lrvdlinden.pasr.data.CardKind
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.Catalog
import app.lrvdlinden.pasr.data.GoogleWallet
import kotlinx.coroutines.launch
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters
import java.util.Locale

/** Teksten voor "Laatst gebruikt" (zelfde als UseFormat op iOS). */
object UseFormat {
    private val nl = Locale("nl", "NL")
    private val zone get() = ZoneId.systemDefault()

    fun title(e: CardEvent, card: Card): String = e.place ?: card.storeName.ifBlank { "Getoond" }

    fun area(e: CardEvent): String? =
        listOfNotNull(e.city?.trim(), e.region?.trim()).filter { it.isNotEmpty() }.joinToString(", ").ifEmpty { null }

    private fun cap(s: String) = s.replaceFirstChar { it.titlecase(nl) }
    private fun day(ms: Long): LocalDate = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()
    private fun fmt(pattern: String, ms: Long) = DateTimeFormatter.ofPattern(pattern, nl).format(Instant.ofEpochMilli(ms).atZone(zone))

    private fun dayMonth(ms: Long): String =
        if (day(ms).year == LocalDate.now(zone).year) fmt("d MMMM", ms) else fmt("d MMMM yyyy", ms)

    /** "Zojuist", "2 uur geleden", "Gisteren", "Woensdag", "9 november". */
    fun whenShort(ms: Long, now: Long = System.currentTimeMillis()): String {
        val diff = now - ms
        val today = LocalDate.now(zone)
        val d = day(ms)
        return when {
            diff < 60_000 -> "Zojuist"
            d == today -> {
                val min = diff / 60_000
                if (min < 60) "$min ${if (min == 1L) "minuut" else "minuten"} geleden" else "${min / 60} uur geleden"
            }
            d == today.minusDays(1) -> "Gisteren"
            d.isAfter(today.minusDays(7)) -> cap(fmt("EEEE", ms))
            else -> dayMonth(ms)
        }
    }

    /** "Vandaag 16:05", "Woensdag 18:22", "9 november 14:03". */
    fun whenWithTime(ms: Long): String {
        val today = LocalDate.now(zone)
        val d = day(ms)
        val label = when {
            d == today -> "Vandaag"
            d == today.minusDays(1) -> "Gisteren"
            d.isAfter(today.minusDays(7)) -> cap(fmt("EEEE", ms))
            else -> dayMonth(ms)
        }
        return "$label ${fmt("HH:mm", ms)}"
    }

    /** "Deze week", "Eerder in november", "Oktober", "September 2025". */
    fun group(ms: Long): String {
        val today = LocalDate.now(zone)
        val d = day(ms)
        val monday = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        return when {
            !d.isBefore(monday) -> "Deze week"
            d.year == today.year && d.month == today.month -> "Eerder in ${fmt("MMMM", ms)}"
            d.year == today.year -> cap(fmt("MMMM", ms))
            else -> cap(fmt("MMMM yyyy", ms))
        }
    }

    fun monthName(): String = cap(DateTimeFormatter.ofPattern("MMMM", nl).format(LocalDate.now(zone)))

    fun isThisMonth(ms: Long): Boolean { val d = day(ms); val t = LocalDate.now(zone); return d.year == t.year && d.month == t.month }

    fun spoken(e: CardEvent, card: Card, withTime: Boolean): String = listOfNotNull(
        title(e, card), area(e), if (withTime) whenWithTime(e.date) else whenShort(e.date),
        e.amount?.let { "uitgegeven ${euro(it, card.currencyCode)}" } ?: "geen bedrag ingevuld",
    ).joinToString(", ")

    /** "6,48", "1.234,50" of "6.48". */
    fun parse(text: String): Double? {
        var t = text.filter { it.isDigit() || it == ',' || it == '.' }
        if (t.contains(',')) t = t.replace(".", "").replace(',', '.')
        return t.toDoubleOrNull()?.takeIf { it >= 0 && it < 1_000_000 }
    }
}

/** Paars voor links: lichter in donker. */
@Composable
private fun irisText(): Color = if (LocalDark.current) Color(0xFF9C90FF) else Color(0xFF5A4BEF)

/** Klein, afgerond logo van de winkel in de kleur van de kaart. */
@Composable
fun UseLogoTile(card: Card) {
    val logo = remember(card.id, card.logo, card.templateID, card.website) { Catalog.logo(card) }
    val style = remember(card.id, card.templateID, card.logo) { Catalog.styleFor(card) }
    val shape = RoundedCornerShape(11.dp)
    Box(
        Modifier.size(42.dp).clip(shape).background(hexColor(card.colorHex))
            .border(0.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f), shape),
        contentAlignment = Alignment.Center,
    ) {
        if (logo != null) {
            Image(logo.asImageBitmap(), null, Modifier.padding(6.dp).fillMaxSize(), contentScale = ContentScale.Fit,
                colorFilter = style?.tint?.let { ColorFilter.tint(hexColor(it)) })
        } else {
            Text(card.storeName.take(2).uppercase(), color = onCard(card.colorHex), fontWeight = FontWeight.ExtraBold, fontSize = 13.sp)
        }
    }
}

/** Eén regel: logo, filiaal, plaats en provincie, wanneer, en rechts het bedrag of de knop Toevoegen. */
@Composable
fun UseRow(card: Card, e: CardEvent, withTime: Boolean, onAmount: () -> Unit) {
    val hint = if (withTime) "bedrag aanpassen of regel verwijderen" else if (e.amount == null) "bedrag toevoegen" else "bedrag aanpassen"
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(onClick = onAmount).padding(vertical = 12.dp)
            .clearAndSetSemantics {
                contentDescription = UseFormat.spoken(e, card, withTime)
                role = Role.Button
                onClick(label = hint) { onAmount(); true }
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        UseLogoTile(card)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(UseFormat.title(e, card), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Bold,
                maxLines = 2, overflow = TextOverflow.Ellipsis)
            val sub = MaterialTheme.colorScheme.onSurfaceVariant
            UseFormat.area(e)?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = sub) }
            Text(if (withTime) UseFormat.whenWithTime(e.date) else UseFormat.whenShort(e.date), style = MaterialTheme.typography.bodySmall, color = sub)
        }
        Spacer(Modifier.width(8.dp))
        val amount = e.amount
        if (amount != null) {
            Text(euro(amount, card.currencyCode), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
        } else {
            FilledTonalButton(onAmount, colors = ButtonDefaults.filledTonalButtonColors(
                containerColor = Brand.iris.copy(alpha = 0.16f), contentColor = irisText())) {
                Text("Toevoegen", fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/** Eigen, niet-doorzichtig vlak (licht wit, donker bijna zwart), afgerond als in Wallet. */
@Composable
fun UsesPanel(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(MaterialTheme.colorScheme.surfaceContainer)
        .padding(horizontal = 14.dp)) { content() }
}

/** In het kaartdetail: kop "Laatst gebruikt" met "Alles", en de laatste drie keer. */
@Composable
fun RecentUsesSection(card: Card, onAll: () -> Unit, onAmount: (CardEvent) -> Unit) {
    val uses = card.uses.take(3)
    if (uses.isEmpty()) return
    Column(Modifier.fillMaxWidth().padding(top = 22.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 0.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Laatst gebruikt", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold,
                modifier = Modifier.weight(1f).semantics { heading() })
            TextButton(onAll) { Text("Alles", color = irisText(), fontWeight = FontWeight.SemiBold) }
        }
        UsesPanel {
            uses.forEachIndexed { i, e ->
                UseRow(card, e, withTime = false) { onAmount(e) }
                if (i < uses.size - 1) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            }
        }
    }
}

/** "Alles": deze maand in twee tegels, en alle keren per periode. Tik op een regel: bedrag aanpassen of verwijderen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecentUsesScreen(id: String) {
    val nav = LocalNav.current
    val all by CardStore.cards.collectAsState()
    val card = all.firstOrNull { it.id.equals(id, true) }
    if (card == null) { LaunchedEffect(Unit) { nav.pop() }; return }
    var editing by remember { mutableStateOf<String?>(null) }
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(rememberTopAppBarState())

    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            LargeTopAppBar(
                title = { Text("Laatst gebruikt", fontWeight = FontWeight.ExtraBold) },
                navigationIcon = { IconButton({ nav.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Terug naar ${card.storeName}") } },
                colors = TopAppBarDefaults.largeTopAppBarColors(containerColor = MaterialTheme.colorScheme.background,
                    scrolledContainerColor = MaterialTheme.colorScheme.background),
                scrollBehavior = scroll,
            )
        },
    ) { pad ->
        val uses = card.uses
        val month = uses.filter { UseFormat.isThisMonth(it.date) }
        val total = month.mapNotNull { it.amount }.sum()
        Column(Modifier.padding(pad).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Tile(UseFormat.monthName(), "${month.size}× gebruikt", "In ${UseFormat.monthName()} ${month.size} keer gebruikt", Modifier.weight(1f))
                Tile("Ingevuld", euro(total, card.currencyCode), "Ingevuld in ${UseFormat.monthName()}: ${euro(total, card.currencyCode)}", Modifier.weight(1f))
            }
            if (uses.isEmpty()) {
                Column(Modifier.fillMaxWidth().padding(vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Outlined.Schedule, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(36.dp))
                    Gap(10.dp)
                    Text("Nog niet gebruikt", fontWeight = FontWeight.Bold)
                    Text("Als je de kaart laat zien, zie je hier wanneer. Dan kun je ook invullen wat je uitgaf.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center, style = MaterialTheme.typography.bodySmall)
                }
            }
            val groups = uses.groupBy { UseFormat.group(it.date) }   // groupBy houdt de volgorde (nieuwste eerst)
            groups.forEach { (title, events) ->
                Text(title.uppercase(), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 4.dp, top = 20.dp, bottom = 6.dp).semantics { heading(); contentDescription = title })
                UsesPanel {
                    events.forEachIndexed { i, e ->
                        UseRow(card, e, withTime = true) { editing = e.id }
                        if (i < events.size - 1) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    }
                }
            }
            Gap(16.dp)
            Text("Filiaal en plaats komen van je locatie bij het tonen. Een bedrag vul je zelf in; tik op een regel om het aan te passen of de regel te verwijderen.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 4.dp))
            if (card.kind == CardKind.VOUCHER) {
                Gap(6.dp)
                Text("Bij een cadeaukaart wordt een ingevuld bedrag ook van je tegoed afgeboekt.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 4.dp))
            }
            Gap(40.dp)
        }
    }
    editing?.let { useId -> UseAmountDialog(card, useId, allowsDelete = true) { editing = null } }
}

@Composable
private fun Tile(label: String, value: String, spoken: String, modifier: Modifier) {
    Column(modifier.clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.surfaceContainer)
        .padding(horizontal = 14.dp, vertical = 10.dp).clearAndSetSemantics { contentDescription = spoken }) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold, maxLines = 1)
    }
}

/** "Wat gaf je uit?" bij één gebruiksmoment: invullen, aanpassen of weghalen; vanuit de lijst ook de regel verwijderen. */
@Composable
fun UseAmountDialog(card: Card, useId: String, allowsDelete: Boolean = false, onDismiss: () -> Unit) {
    val e = card.history.firstOrNull { it.id == useId }
    if (e == null) { LaunchedEffect(useId) { onDismiss() }; return }
    val scope = rememberCoroutineScope()
    var text by remember(useId) { mutableStateOf(e.amount?.let { "%.2f".format(Locale("nl", "NL"), it) } ?: "") }
    var confirmDelete by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val value = UseFormat.parse(text)
    fun done(updated: Card) {
        CardStore.upsert(updated)
        if (card.kind == CardKind.VOUCHER) scope.launch { GoogleWallet.updateIfSaved(updated) }
        onDismiss()
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Deze regel verwijderen?") },
            text = { Text(if (card.kind == CardKind.VOUCHER && e.spentID != null) "Het bedrag gaat terug naar je tegoed." else "Deze keer verdwijnt uit Laatst gebruikt.") },
            confirmButton = { TextButton({ done(card.removingEvent(e)) }) { Text("Verwijder", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton({ confirmDelete = false }) { Text("Annuleren") } },
        )
        return
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Wat gaf je uit?") },
        text = {
            Column {
                Text(listOfNotNull(UseFormat.title(e, card), UseFormat.area(e), UseFormat.whenWithTime(e.date)).joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Gap(10.dp)
                OutlinedTextField(text, { text = it.filter { c -> c.isDigit() || c == ',' || c == '.' } }, label = { Text("Bedrag in euro") },
                    prefix = { Text("€ ") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true,
                    modifier = Modifier.focusRequester(focus))
                Gap(8.dp)
                Text(if (card.kind == CardKind.VOUCHER) "Wordt afgeboekt van je tegoed (nu ${euro(card.balance ?: 0.0, card.currencyCode)})."
                     else "Optioneel. Alleen voor jezelf, om bij te houden wat je bij deze winkel uitgeeft.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (e.amount != null || allowsDelete) Gap(6.dp)
                if (e.amount != null) TextButton({ done(card.withAmount(null, useId)) }) { Text("Bedrag weghalen", color = MaterialTheme.colorScheme.error) }
                if (allowsDelete) TextButton({ confirmDelete = true }) { Text("Regel verwijderen", color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            TextButton({ done(card.withAmount(if (text.isBlank()) null else value, useId)) }, enabled = text.isBlank() || value != null) { Text("Bewaar") }
        },
        dismissButton = { TextButton(onDismiss) { Text("Annuleren") } },
    )
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
}
