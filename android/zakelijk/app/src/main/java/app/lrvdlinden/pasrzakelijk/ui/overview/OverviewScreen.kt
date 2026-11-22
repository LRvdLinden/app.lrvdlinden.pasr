package app.lrvdlinden.pasrzakelijk.ui.overview

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.outlined.CardGiftcard
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.ListAlt
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.data.Business
import app.lrvdlinden.pasrzakelijk.data.BusinessApi
import app.lrvdlinden.pasrzakelijk.data.BusinessCard
import app.lrvdlinden.pasrzakelijk.data.DayStat
import app.lrvdlinden.pasrzakelijk.data.LogEvent
import app.lrvdlinden.pasrzakelijk.data.MemberRow
import app.lrvdlinden.pasrzakelijk.ui.EmptyState
import app.lrvdlinden.pasrzakelijk.ui.ErrorLine
import app.lrvdlinden.pasrzakelijk.ui.Fmt
import app.lrvdlinden.pasrzakelijk.ui.Group
import app.lrvdlinden.pasrzakelijk.ui.GroupDivider
import app.lrvdlinden.pasrzakelijk.ui.PillSegments
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.PzField
import app.lrvdlinden.pasrzakelijk.ui.ScreenScaffold
import app.lrvdlinden.pasrzakelijk.ui.SectionFooter
import app.lrvdlinden.pasrzakelijk.ui.SectionHeader
import app.lrvdlinden.pasrzakelijk.ui.SettingsRow
import app.lrvdlinden.pasrzakelijk.ui.hexColor
import kotlinx.coroutines.launch
import java.util.Calendar
import java.util.Date
import java.util.TimeZone

enum class Metric(val title: String, val unit: String, val icon: ImageVector, val color: Color) {
    Stamps("Stempels", "stempels", Icons.Filled.Verified, Pz.mint),
    Rewards("Beloningen", "beloningen", Icons.Filled.CardGiftcard, Pz.coral),
    Joins("Nieuwe leden", "leden", Icons.Filled.PersonAdd, Pz.iris);

    fun value(d: DayStat) = when (this) { Stamps -> d.stamps; Rewards -> d.rewards; Joins -> d.joins }
}

private sealed interface Sub {
    data class Members(val card: BusinessCard) : Sub
    data object Log : Sub
}

/** Overzicht (eigenaar): cijfers per dag in Homey Insights-stijl, leden per kaart en het logboek. */
@Composable
fun OverviewScreen(business: Business) {
    val demoStats = if (app.lrvdlinden.pasrzakelijk.data.Demo.enabled) app.lrvdlinden.pasrzakelijk.data.Demo.stats else null
    var sub by remember { mutableStateOf<Sub?>(null) }
    BackHandler(sub != null) { sub = null }
    when (val s = sub) {
        is Sub.Members -> MembersScreen(s.card) { sub = null }
        Sub.Log -> LogScreen(business) { sub = null }
        null -> OverviewMain(business, demoStats, onMembers = { sub = Sub.Members(it) }, onLog = { sub = Sub.Log })
    }
}

@Composable
private fun OverviewMain(business: Business, demoStats: List<DayStat>?, onMembers: (BusinessCard) -> Unit, onLog: () -> Unit) {
    var days by remember { mutableIntStateOf(30) }
    var metric by remember { mutableStateOf(Metric.Stamps) }
    var stats by remember { mutableStateOf(demoStats?.takeLast(30) ?: emptyList()) }
    var previous by remember { mutableStateOf(demoStats?.dropLast(30)?.takeLast(30) ?: emptyList()) }
    var members by remember { mutableStateOf<Int?>(null) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<MetricPoint?>(null) }
    var showPrevious by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    // De server geeft hoogstens 366 dagen terug: bij een jaar is er geen vorige periode.
    val hasPrevious = days * 2 <= 366

    fun load() {
        if (demoStats != null) return
        loading = true
        scope.launch {
            try {
                // twee periodes ophalen: deze en de vorige (om te vergelijken)
                val span = if (hasPrevious) days * 2 else minOf(days, 366)
                val (list, total) = BusinessApi.stats(business.id, span)
                val filled = fill(list, span)
                previous = if (hasPrevious) filled.take(days) else emptyList()
                stats = filled.takeLast(days)
                if (!hasPrevious) showPrevious = false
                members = total
                selected = null
                error = null
            } catch (e: Exception) {
                error = e.message
            } finally {
                loading = false
            }
        }
    }
    LaunchedEffect(days) { load() }

    val shown = if (showPrevious && hasPrevious) previous else stats
    val points = shown.map { MetricPoint(it.day, metric.value(it).toDouble()) }
    val total = shown.sumOf { metric.value(it) }
    val currentLabel = when (days) { 7 -> L("Deze week"); 30 -> L("Deze maand"); 90 -> L("Dit kwartaal"); else -> L("Dit jaar") }
    val previousLabel = when (days) { 7 -> L("Vorige week"); 30 -> L("Vorige maand"); 90 -> L("Vorig kwartaal"); else -> L("Vorig jaar") }

    ScreenScaffold(L("Overzicht"), actions = {
        IconButton(onClick = { load() }) { Icon(Icons.Filled.Refresh, L("Verversen"), tint = Pz.accent) }
    }) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Column(Modifier.widthIn(max = 680.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp)) {
                // Grafiekkaart zoals Homey Insights
                Column(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Pz.insightsCard).padding(18.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Text(business.name, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = Pz.text)
                    var menu by remember { mutableStateOf(false) }
                    Box {
                        Row(
                            Modifier.clip(CircleShape).background(Pz.insightsPill).clickable { menu = true }.padding(horizontal = 14.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Icon(metric.icon, null, tint = metric.color, modifier = Modifier.size(16.dp))
                            Text(L(metric.title), color = metric.color, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                            Icon(Icons.Filled.KeyboardArrowDown, null, tint = metric.color, modifier = Modifier.size(16.dp))
                        }
                        DropdownMenu(menu, { menu = false }) {
                            for (m in Metric.entries) DropdownMenuItem(
                                text = { Text(L(m.title)) }, leadingIcon = { Icon(m.icon, null, tint = m.color) },
                                onClick = { menu = false; metric = m; selected = null },
                            )
                        }
                    }
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                        Column(Modifier.weight(1f)) {
                            Text(if (showPrevious && hasPrevious) previousLabel else currentLabel, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Pz.text)
                            val sub = selected?.let { Fmt.weekdayDayMonth(it.date) }
                                ?: if (shown.isNotEmpty()) Fmt.dayMonth(shown.first().day) + " – " + Fmt.dayMonth(shown.last().day) else ""
                            Text(sub, fontSize = 12.sp, color = Pz.muted)
                        }
                        AnimatedContent(selected?.value?.toInt() ?: total, label = "total") { v ->
                            Text("$v", fontSize = 30.sp, fontWeight = FontWeight.Black, color = metric.color)
                        }
                        Text(" " + L(metric.unit), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = metric.color.copy(alpha = 0.6f),
                            modifier = Modifier.padding(bottom = 5.dp))
                    }
                    Box(contentAlignment = Alignment.Center) {
                        InsightsChart(
                            points, L(metric.unit), metric.color,
                            xLabel = { d -> if (days >= 365) Fmt.pattern("MMMMM", d) else Fmt.pattern("d", d) + " " + Fmt.pattern("MMMMM", d) },
                            selected = selected, onSelect = { selected = it },
                        )
                        if (loading && stats.isEmpty()) CircularProgressIndicator(color = Pz.accent)
                        if (!loading && points.all { it.value == 0.0 }) Text(L("Nog geen gegevens in deze periode"), fontSize = 13.sp, color = Pz.muted)
                    }
                    PillSegments(listOf(7 to "W", 30 to "M", 90 to "K", 365 to "J").map { it.first to L(it.second) }, days, { days = it },
                        spoken = mapOf(7 to L("Week"), 30 to L("Maand"), 90 to L("Kwartaal"), 365 to L("Jaar")))
                    PillSegments(
                        if (hasPrevious) listOf(false to currentLabel, true to previousLabel) else listOf(false to currentLabel),
                        showPrevious, { showPrevious = it; selected = null },
                    )
                }
                Spacer(Modifier.height(14.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Kpi(L("Stempels"), stats.sumOf { it.stamps }, Pz.mint, Modifier.weight(1f))
                    Kpi(L("Beloningen"), stats.sumOf { it.rewards }, Pz.coral, Modifier.weight(1f))
                    Kpi(L("Leden"), members ?: business.cards.sumOf { it.members }, Pz.iris, Modifier.weight(1f))
                }
                error?.let { Spacer(Modifier.height(12.dp)); ErrorLine(it) }
                SectionHeader(L("Leden per kaart"))
                Group {
                    if (business.cards.isEmpty()) SettingsRow(L("Nog geen kaarten."), titleColor = Pz.muted)
                    business.cards.forEachIndexed { i, card ->
                        if (i > 0) GroupDivider()
                        Row(
                            Modifier.fillMaxWidth().clickable { onMembers(card) }.padding(horizontal = 16.dp, vertical = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Box(Modifier.size(12.dp).clip(CircleShape).background(hexColor(card.color)))
                            Text(card.name, Modifier.weight(1f).padding(start = 12.dp), fontSize = 17.sp, color = Pz.text)
                            Text("${card.members}", color = Pz.muted, fontSize = 17.sp)
                            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Pz.muted)
                        }
                    }
                }
                Spacer(Modifier.height(18.dp))
                Group {
                    SettingsRow(L("Logboek"), Icons.Outlined.ListAlt, Pz.iris, onClick = onLog) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Pz.muted)
                    }
                }
                SectionFooter(L("Elke stempel, inwisseling en ongedaanmaking met wie, wat en wanneer. Het logboek kan niet worden gewist."))
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun Kpi(title: String, value: Int, color: Color, modifier: Modifier = Modifier) {
    Row(modifier.clip(RoundedCornerShape(16.dp)).background(Pz.card).height(72.dp)) {
        Box(Modifier.width(3.dp).fillMaxHeight().background(color))
        Column(Modifier.padding(start = 12.dp, top = 12.dp, bottom = 12.dp)) {
            Text(title, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Pz.muted, maxLines = 1)
            Text("$value", fontSize = 24.sp, fontWeight = FontWeight.Black, color = Pz.text)
        }
    }
}

/** Elke dag een waarde (ook 0), zodat de lijn klopt. */
fun fill(list: List<DayStat>, days: Int): List<DayStat> {
    val zone = TimeZone.getTimeZone("Europe/Amsterdam")
    fun startOfDay(d: Date): Long = Calendar.getInstance(zone).apply {
        time = d; set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }.timeInMillis
    val byDay = list.associateBy { startOfDay(it.day) }
    val today = Calendar.getInstance(zone).apply { timeInMillis = startOfDay(Date()) }
    return (days - 1 downTo 0).map { offset ->
        val c = (today.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, -offset) }
        byDay[c.timeInMillis] ?: DayStat(c.time)
    }
}

/** Leden van één kaart (alleen de laatste tekens van de code). */
@Composable
fun MembersScreen(card: BusinessCard, onBack: () -> Unit) {
    var rows by remember { mutableStateOf<List<MemberRow>>(emptyList()) }
    var total by remember { mutableIntStateOf(0) }
    var loaded by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var search by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    fun load() {
        scope.launch {
            try { val r = BusinessApi.members(card.id); total = r.first; rows = r.second; error = null } catch (e: Exception) { error = e.message }
            loaded = true
        }
    }
    LaunchedEffect(card.id) { load() }
    val filtered = if (search.isBlank()) rows else rows.filter { it.code.contains(search.trim(), ignoreCase = true) }
    ScreenScaffold(card.name, onBack = onBack, actions = { IconButton(onClick = { load() }) { Icon(Icons.Filled.Refresh, L("Verversen"), tint = Pz.accent) } }) {
        Column(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
            PzField(search, { search = it }, L("Zoek op code"), autoCorrect = false, monospace = true)
            Spacer(Modifier.height(10.dp))
            when {
                error != null -> EmptyState(Icons.Filled.WifiOff, L("Laden lukt niet"), error)
                !loaded -> Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Pz.accent) }
                rows.isEmpty() -> EmptyState(Icons.Outlined.Group, L("Nog geen leden"), L("Deel de QR-code of hang de flyer op."))
                else -> LazyColumn(Modifier.weight(1f).clip(RoundedCornerShape(16.dp)).background(Pz.card)) {
                    items(filtered, key = { it.id }) { m ->
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(m.code, fontFamily = FontFamily.Monospace, color = Pz.text, fontSize = 16.sp)
                                val sub = m.lastStampAt?.let { L("Laatste stempel %@ geleden", Fmt.ago(it)) }
                                    ?: m.createdAt?.let { L("Lid sinds %@", Fmt.dayMonthYear(it)) }
                                if (sub != null) Text(sub, fontSize = 12.sp, color = Pz.muted)
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text("${m.stamps}/${card.stampsTotal}", fontWeight = FontWeight.SemiBold, color = Pz.text, fontSize = 17.sp)
                                if (m.rewards > 0) Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Outlined.CardGiftcard, null, tint = Pz.muted, modifier = Modifier.size(12.dp))
                                    Text(" ${m.rewards}", fontSize = 12.sp, color = Pz.muted)
                                }
                            }
                            if (m.app) Icon(Icons.Outlined.PhoneAndroid, L("In de app"), tint = Pz.muted, modifier = Modifier.padding(start = 8.dp).size(18.dp))
                        }
                        GroupDivider()
                    }
                    item { Text(L("%lld leden", total), Modifier.padding(16.dp), color = Pz.muted, fontSize = 13.sp) }
                }
            }
        }
    }
}

/** Logboek van de zaak (eigenaar). Niet te wissen. */
@Composable
fun LogScreen(business: Business, onBack: () -> Unit) {
    val demo = if (app.lrvdlinden.pasrzakelijk.data.Demo.enabled) app.lrvdlinden.pasrzakelijk.data.Demo.log else null
    var events by remember { mutableStateOf(demo ?: emptyList()) }
    var loaded by remember { mutableStateOf(demo != null) }
    var error by remember { mutableStateOf<String?>(null) }
    var search by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    fun load() {
        if (demo != null) return
        scope.launch {
            try { events = BusinessApi.log(business.id, 500); error = null } catch (e: Exception) { error = e.message }
            loaded = true
        }
    }
    LaunchedEffect(business.id) { load() }
    val filtered = if (search.isBlank()) events else events.filter {
        "${it.who} ${it.card} ${it.member} ${it.device ?: ""}".contains(search.trim(), ignoreCase = true)
    }
    ScreenScaffold(L("Logboek"), onBack = onBack, actions = { IconButton(onClick = { load() }) { Icon(Icons.Filled.Refresh, L("Verversen"), tint = Pz.accent) } }) {
        Column(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
            PzField(search, { search = it }, L("Zoek op medewerker, kaart of code"), autoCorrect = false)
            Spacer(Modifier.height(10.dp))
            when {
                error != null -> EmptyState(Icons.Filled.WifiOff, L("Laden lukt niet"), error)
                !loaded -> Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Pz.accent) }
                events.isEmpty() -> EmptyState(Icons.Outlined.ListAlt, L("Nog niets gebeurd"), L("Hier komt elke stempel en inwisseling te staan."))
                else -> LazyColumn(Modifier.weight(1f).clip(RoundedCornerShape(16.dp)).background(Pz.card)) {
                    items(filtered, key = { it.id }) { e -> LogRow(e); GroupDivider() }
                }
            }
        }
    }
}

@Composable
private fun LogRow(e: LogEvent) {
    val (icon, color) = when (e.kind) {
        "stamp" -> Icons.Filled.Verified to Pz.mint
        "redeem" -> Icons.Filled.CardGiftcard to Pz.coral
        "undo" -> Icons.AutoMirrored.Filled.Undo to Pz.amber
        "join" -> Icons.Filled.PersonAdd to Pz.iris
        "claim" -> Icons.Filled.Download to Pz.iris
        else -> Icons.Outlined.ListAlt to Pz.iris
    }
    val title = when (e.kind) {
        "stamp" -> if (e.amount == 1) L("1 stempel") else L("%lld stempels", e.amount)
        "redeem" -> L("Beloning ingewisseld")
        "undo" -> L("Ongedaan gemaakt")
        "join" -> L("Nieuw lid")
        "claim" -> L("Kaart overgezet naar de app")
        else -> e.kind
    }
    val who = when (e.byRole) {
        "owner" -> if (e.who.isEmpty()) L("Eigenaar") else e.who + " (" + L("eigenaar") + ")"
        "staff" -> e.who.ifEmpty { L("Medewerker") }
        "customer" -> L("Klant")
        else -> e.who
    }
    val detail = listOfNotNull(e.card.ifEmpty { null }, e.member.takeIf { it.isNotEmpty() }?.let { "…" + it.takeLast(4) }).joinToString(" · ")
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = color, modifier = Modifier.padding(top = 2.dp).size(20.dp))
        Column(Modifier.weight(1f).padding(start = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, color = Pz.text,
                textDecoration = if (e.undone) TextDecoration.LineThrough else null)
            if (detail.isNotEmpty()) Text(detail, fontSize = 12.sp, color = Pz.muted)
            val line = listOf(who, e.device ?: "").filter { it.isNotEmpty() }.joinToString(" · ")
            if (line.isNotEmpty()) Text(line, fontSize = 12.sp, color = Pz.muted)
        }
        e.at?.let { Text(Fmt.dayMonthTime(it), fontSize = 12.sp, color = Pz.muted) }
    }
}
