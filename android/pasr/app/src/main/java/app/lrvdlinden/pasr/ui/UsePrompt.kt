package app.lrvdlinden.pasr.ui

import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.Receipt
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.UseCapture
import app.lrvdlinden.pasr.data.newId
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

/** De vraag "Gebruikt bij PLUS? Ja · Nee" die na het sluiten van een kaart even onderin staat. */
data class UsePromptData(val id: String = newId(), val cardId: String, val title: String, val place: String?)

object UsePrompts {
    val current = MutableStateFlow<UsePromptData?>(null)
    /** Na "Ja": het bedrag-venster voor dit moment (kaart-id, moment-id). */
    val amountFor = MutableStateFlow<Pair<String, String>?>(null)
    private val scope = MainScope()

    /**
     * De kaart is gesloten. Was de barcode minstens 5 seconden in beeld, dan vragen (met Alleen bij de winkel alleen bij
     * een eigen locatie, of als Pasr dat niet kan weten); elders niets.
     */
    fun cardClosed(context: Context, card: Card, visibleMs: Long) {
        if (!UseCapture.asks || !UseCapture.applies(card) || visibleMs < UseCapture.MIN_VISIBLE_MS) return
        scope.launch {
            val place = if (UseCapture.onlyAtStore) when (val c = UseCapture.check(context, card)) {
                is UseCapture.Check.AtStore -> c.name
                UseCapture.Check.Elsewhere -> return@launch
                UseCapture.Check.Unknown -> null
            } else null
            current.value = UsePromptData(cardId = card.id, title = place ?: card.storeName.ifBlank { "deze winkel" }, place = place)
        }
    }

    fun cardOpened() { current.value = null }

    fun yes(p: UsePromptData) {
        current.value = null
        val card = CardStore.get(p.cardId) ?: return
        val (updated, useId) = card.used(place = p.place, source = "ask")
        CardStore.upsert(updated)
        amountFor.value = p.cardId to useId
    }

    fun no() { current.value = null }
}

/** Onderin, boven alles: de vraag met Ja en Nee en een balkje dat leegloopt (geen reactie = niet tellen). */
@Composable
fun UsePromptHost() {
    val prompt by UsePrompts.current.collectAsState()
    val amount by UsePrompts.amountFor.collectAsState()
    val cards by CardStore.cards.collectAsState()
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
        AnimatedVisibility(prompt != null, enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut()) {
            prompt?.let { p ->
                val card = cards.firstOrNull { it.id == p.cardId }
                UsePromptBar(p, card, onYes = { UsePrompts.yes(p) }, onNo = { UsePrompts.no() })
                LaunchedEffect(p.id) {
                    delay(UseCapture.PROMPT_MS)
                    if (UsePrompts.current.value?.id == p.id) UsePrompts.current.value = null
                }
            }
        }
    }
    amount?.let { (cardId, useId) ->
        val card = cards.firstOrNull { it.id == cardId }
        if (card == null) UsePrompts.amountFor.value = null
        else UseAmountDialog(card, useId, offersReceipt = true) { UsePrompts.amountFor.value = null }
    }
}

@Composable
fun UsePromptBar(p: UsePromptData, card: Card?, onYes: () -> Unit, onNo: () -> Unit) {
    var progress by remember(p.id) { mutableFloatStateOf(1f) }
    LaunchedEffect(p.id) {
        val steps = 80
        repeat(steps) { delay(UseCapture.PROMPT_MS / steps); progress = 1f - (it + 1) / steps.toFloat() }
    }
    Surface(
        Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 16.dp, vertical = 12.dp)
            .semantics {
                liveRegion = LiveRegionMode.Polite
                customActions = listOf(CustomAccessibilityAction("Ja") { onYes(); true }, CustomAccessibilityAction("Nee") { onNo(); true })
            },
        shape = RoundedCornerShape(22.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, shadowElevation = 10.dp,
    ) {
        Column {
            Row(Modifier.padding(start = 14.dp, end = 10.dp, top = 12.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                if (card != null) { UseLogoTile(card); Spacer(Modifier.width(12.dp)) }
                Column(Modifier.weight(1f)) {
                    Text("Gebruikt bij ${p.title}?", fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis,
                        color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.bodyMedium)
                    Text("Alleen Ja telt mee in Laatst gebruikt", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                }
                val pad = androidx.compose.foundation.layout.PaddingValues(horizontal = 14.dp)
                OutlinedButton(onNo, contentPadding = pad) { Text("Nee") }
                Spacer(Modifier.width(6.dp))
                Button(onYes, contentPadding = pad, colors = ButtonDefaults.buttonColors(containerColor = Brand.iris, contentColor = Color.White)) { Text("Ja") }
            }
            LinearProgressIndicator(progress = { progress }, Modifier.fillMaxWidth().padding(horizontal = 18.dp).padding(bottom = 6.dp).height(3.dp)
                .clip(RoundedCornerShape(2.dp)), color = Brand.iris.copy(alpha = 0.6f), trackColor = Color.Transparent)
        }
    }
}

/** Naar links vegen om een regel te verwijderen (Laatst gebruikt). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SwipeToDelete(key: String, onDelete: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState(confirmValueChange = {
        if (it == SwipeToDismissBoxValue.EndToStart) { onDelete(); true } else false
    })
    SwipeToDismissBox(
        state, enableDismissFromStartToEnd = false,
        backgroundContent = {
            Row(Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.error).padding(horizontal = 20.dp),
                horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Delete, "Verwijder", tint = MaterialTheme.colorScheme.onError)
            }
        },
    ) {
        Box(Modifier.background(MaterialTheme.colorScheme.surfaceContainer)) { content() }
    }
    LaunchedEffect(key) { state.reset() }
}

/** Instellingen › Laatst gebruikt. */
@Composable
fun UseSettings() {
    val nav = LocalNav.current
    val context = androidx.compose.ui.platform.LocalContext.current
    var ask by remember { androidx.compose.runtime.mutableStateOf(UseCapture.asks) }
    var atStore by remember { androidx.compose.runtime.mutableStateOf(UseCapture.onlyAtStore) }
    var hasLocation by remember { androidx.compose.runtime.mutableStateOf(UseCapture.hasLocation(context)) }
    val askLocation = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions()) { hasLocation = UseCapture.hasLocation(context) }
    SectionHeader("Laatst gebruikt")
    Group {
        Toggle("Vraag na het tonen", ask, "Was de barcode 5 seconden in beeld, dan vraagt Pasr bij het sluiten of je de kaart gebruikte") {
            ask = it; UseCapture.asks = it
        }
        if (ask) Toggle("Alleen bij de winkel", atStore,
            if (!hasLocation) "Met je locatie (alleen op je telefoon): niet vragen als je niet bij een bewaard filiaal bent. Zonder locatie vraagt Pasr het altijd."
            else "Niet vragen als je niet bij een bewaard filiaal bent (Ik sta hier). Je plek blijft op je telefoon.") {
            atStore = it; UseCapture.onlyAtStore = it
            if (it && !hasLocation) {
                app.lrvdlinden.pasr.Incoming.leavingOnPurpose = true
                askLocation.launch(arrayOf(android.Manifest.permission.ACCESS_FINE_LOCATION, android.Manifest.permission.ACCESS_COARSE_LOCATION))
            }
        }
        RowItem(androidx.compose.material.icons.Icons.Outlined.Payments, "Aankopen vanzelf vastleggen",
            if (UseCapture.payCapture && app.lrvdlinden.pasr.notify.PaymentListener.isGranted(context)) "Aan: betaalmeldingen van Google Wallet en je bank" else "Uit") {
            nav.push(Screen.PayCapture)
        }
        RowItem(androidx.compose.material.icons.Icons.Outlined.Receipt, "Bonnetjes", "Alle bewaarde kassabonnen, met garantie") { nav.push(Screen.Receipts()) }
    }
}

/** Uitleg en aan/uit: betaalmeldingen lezen om aankopen vast te leggen (opt-in, altijd uit te zetten). */
@Composable
fun PayCaptureScreen() {
    val context = androidx.compose.ui.platform.LocalContext.current
    var on by remember { androidx.compose.runtime.mutableStateOf(UseCapture.payCapture) }
    var granted by remember { androidx.compose.runtime.mutableStateOf(app.lrvdlinden.pasr.notify.PaymentListener.isGranted(context)) }
    androidx.lifecycle.compose.LifecycleEventEffect(androidx.lifecycle.Lifecycle.Event.ON_RESUME) {
        granted = app.lrvdlinden.pasr.notify.PaymentListener.isGranted(context)
    }
    fun openSettings() {
        app.lrvdlinden.pasr.Incoming.leavingOnPurpose = true
        runCatching { context.startActivity(app.lrvdlinden.pasr.notify.PaymentListener.settingsIntent(context)) }
    }
    SimpleScaffold("Vanzelf vastleggen") {
        Text("Aankopen vanzelf vastleggen", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(top = 8.dp))
        Gap(8.dp)
        Text("Betaal je met Google Wallet of je bank-app, dan kan Pasr de betaalmelding lezen en de aankoop bij de juiste kaart in Laatst gebruikt zetten. Bij een cadeaukaart vraagt Pasr eerst in een melding of het bedrag van je tegoed af mag.",
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        SectionHeader("Wat Pasr leest")
        Group {
            Column(Modifier.padding(16.dp)) {
                listOf(
                    "Alleen betaalmeldingen met een €-bedrag: van Google Wallet en bekende bank-apps, en van andere apps alleen als er ook een woord als betaald of betaling in staat.",
                    "Daaruit alleen de winkel en het bedrag. De rest van de melding leest Pasr niet.",
                    "Alles gebeurt op je telefoon. Pasr bewaart de melding en de winkelnaam niet en stuurt ze nergens heen.",
                    "Past er geen kaart, dan gebeurt er niets. Heb je een Pasr-account, dan gaat alleen het moment mee (winkel van de kaart, tijd en bedrag), net als een bedrag dat je zelf invult.",
                ).forEachIndexed { i, t ->
                    Row(Modifier.padding(vertical = 6.dp)) {
                        Text("${i + 1}", Modifier.width(24.dp), fontWeight = FontWeight.ExtraBold, color = Brand.iris)
                        Text(t, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
        }
        SectionHeader("Aan of uit")
        Group {
            Toggle("Betaalmeldingen gebruiken", on && granted,
                if (on && !granted) "Geef Pasr nog toegang tot meldingen in Android-instellingen" else "Je kunt het altijd weer uitzetten") { v ->
                on = v; UseCapture.payCapture = v
                if (v && !granted) openSettings()
            }
            RowItem(androidx.compose.material.icons.Icons.Outlined.Settings, "Toegang tot meldingen",
                if (granted) "Pasr heeft toegang. Hier zet je het ook helemaal uit." else "Pasr heeft geen toegang") { openSettings() }
        }
        Text("Staat de schakelaar uit, dan negeert Pasr alle meldingen, ook als de toegang nog aan staat. Haal de toegang weg in Android-instellingen als je het helemaal niet meer wilt.",
            Modifier.padding(top = 8.dp, bottom = 40.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
