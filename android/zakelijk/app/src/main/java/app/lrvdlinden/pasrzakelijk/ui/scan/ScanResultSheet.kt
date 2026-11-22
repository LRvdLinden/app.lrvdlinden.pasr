package app.lrvdlinden.pasrzakelijk.ui.scan

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.data.Business
import app.lrvdlinden.pasrzakelijk.data.BusinessApi
import app.lrvdlinden.pasrzakelijk.data.ScanResult
import app.lrvdlinden.pasrzakelijk.ui.BigButton
import app.lrvdlinden.pasrzakelijk.ui.ConfirmDialog
import app.lrvdlinden.pasrzakelijk.ui.ErrorLine
import app.lrvdlinden.pasrzakelijk.ui.Fmt
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.StampCardView
import app.lrvdlinden.pasrzakelijk.ui.SuccessLine
import app.lrvdlinden.pasrzakelijk.ui.rememberHaptics
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Resultaat van een scan als blad onderin: kaart, stand in vakjes, aantal stempels, inwisselen, ongedaan maken. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScanResultSheet(business: Business, initial: ScanResult, onDismiss: () -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = Pz.bg) {
        ScanResultContent(business, initial, onDismiss)
    }
}

@Composable
fun ScanResultContent(business: Business, initial: ScanResult, onDismiss: () -> Unit) {
    var result by remember { mutableStateOf(initial) }
    var amount by remember { mutableIntStateOf(1) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var done by remember { mutableStateOf<String?>(null) }
    // Tot wanneer "Ongedaan maken" zichtbaar is (2 minuten na de actie).
    var undoUntil by remember {
        val last = initial.lastStampAt
        mutableLongStateOf(if (initial.undoEventID != null && last != null && System.currentTimeMillis() - last.time < 120_000) last.time + 120_000 else 0L)
    }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var confirmRedeem by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val maxAmount = (result.maxPerScan ?: business.maxPerScan).coerceIn(1, 30)

    LaunchedEffect(Unit) { while (true) { now = System.currentTimeMillis(); delay(1000) } }

    fun reload(quiet: Boolean = false) {
        scope.launch {
            try { result = BusinessApi.scan(result.code) } catch (e: Exception) { if (!quiet) error = e.message }
        }
    }

    fun run(message: String, undoable: Boolean, action: suspend () -> ScanResult?, after: () -> Unit = {}) {
        busy = true; error = null; done = null
        scope.launch {
            try {
                val new = action()
                if (new != null) result = new
                done = message
                undoUntil = if (undoable) System.currentTimeMillis() + 120_000 else 0L
                if (new == null) reload(quiet = true)
                haptics.success()
                after()
            } catch (e: Exception) {
                error = e.message
                haptics.error()
            } finally {
                busy = false
            }
        }
    }

    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // kop: verversen · …ABCD · Klaar
        Row(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { reload() }, enabled = !busy) { Icon(Icons.Filled.Refresh, L("Verversen"), tint = Pz.accent) }
            Text("…" + result.suffix, Modifier.weight(1f), textAlign = TextAlign.Center, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = Pz.text)
            TextButton(onClick = onDismiss) { Text(L("Klaar"), color = Pz.accent, fontWeight = FontWeight.Bold, fontSize = 17.sp) }
        }
        Column(
            Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            StampCardView(result.cardName, result.business, result.color, result.logo, result.stampsTotal, result.stamps, result.reward, textColor = result.textColor)
            // stand
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                AnimatedContent(result.stamps, label = "status") { stamps ->
                    Text(
                        if (stamps >= result.stampsTotal) L("%lld van %lld, beloning klaar", stamps, result.stampsTotal)
                        else L("%lld van %lld stempels", stamps, result.stampsTotal),
                        fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Pz.text, textAlign = TextAlign.Center,
                    )
                }
                val parts = mutableListOf(result.lastStampAt?.let { L("Laatste stempel %@ geleden", Fmt.ago(it)) } ?: L("Nog geen stempels"))
                if (result.rewardsRedeemed > 0) parts += L("%lldx beloning gehad", result.rewardsRedeemed)
                Text(parts.joinToString(" · "), color = Pz.muted, fontSize = 13.sp, textAlign = TextAlign.Center)
            }
            result.cooldownUntil?.takeIf { it.time > now }?.let { until ->
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Pz.amber.copy(alpha = 0.12f)).padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Timer, null, tint = Pz.amber, modifier = Modifier.size(18.dp))
                    Text(L("Net al gestempeld. Weer mogelijk %@.", Fmt.until(until)), color = Pz.amber, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                }
            }
            error?.let { ErrorLine(it) }
            done?.let { SuccessLine(it) }
            // aantal + stempels toevoegen
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Pz.card).border(1.dp, Pz.line, RoundedCornerShape(18.dp)).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(
                    Modifier.fillMaxWidth().semantics(mergeDescendants = false) { contentDescription = L("Aantal stempels") + ": $amount" },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(L("Aantal stempels"), fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = Pz.text, modifier = Modifier.weight(1f))
                    FilledTonalIconButton(
                        onClick = { amount = maxOf(1, amount - 1); haptics.tick() }, enabled = amount > 1, modifier = Modifier.size(44.dp),
                        colors = IconButtonDefaults.filledTonalIconButtonColors(containerColor = Pz.card2, contentColor = Pz.accent),
                    ) { Icon(Icons.Filled.Remove, L("Minder")) }
                    AnimatedContent(amount, label = "amount") { n ->
                        Text("$n", fontSize = 30.sp, fontWeight = FontWeight.Black, color = Pz.text, textAlign = TextAlign.Center, modifier = Modifier.widthIn(min = 52.dp))
                    }
                    FilledTonalIconButton(
                        onClick = { amount = minOf(maxAmount, amount + 1); haptics.tick() }, enabled = amount < maxAmount, modifier = Modifier.size(44.dp),
                        colors = IconButtonDefaults.filledTonalIconButtonColors(containerColor = Pz.card2, contentColor = Pz.accent),
                    ) { Icon(Icons.Filled.Add, L("Meer")) }
                }
                BigButton(
                    if (amount == 1) L("Stempel toevoegen") else L("%lld stempels toevoegen", amount),
                    {
                        val n = amount
                        run(if (n == 1) L("Stempel gezet") else L("%lld stempels gezet", n), undoable = true,
                            action = { BusinessApi.stamp(result.code, n) }, after = { amount = 1 })
                    },
                    icon = Icons.Filled.AddCircle, color = Pz.mint, foreground = Color.Black, busy = busy,
                )
            }
            if (result.isFull) {
                BigButton(L("Beloning inwisselen"), { confirmRedeem = true }, icon = Icons.Filled.CardGiftcard, color = Pz.coral, enabled = !busy)
            }
            val undoID = result.undoEventID
            if (undoID != null && undoUntil > now) {
                OutlinedButton(
                    onClick = { run(L("Ongedaan gemaakt"), undoable = false, action = { BusinessApi.undo(undoID, result.code) }) },
                    enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp), shape = RoundedCornerShape(14.dp),
                ) {
                    Icon(Icons.AutoMirrored.Filled.Undo, null, tint = Pz.accent, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.size(8.dp))
                    Text(L("Ongedaan maken (%@)", Fmt.clock((undoUntil - now + 999) / 1000)), color = Pz.accent, fontWeight = FontWeight.SemiBold)
                }
            }
            Spacer(Modifier.size(12.dp))
        }
    }
    if (confirmRedeem) {
        ConfirmDialog(
            L("Beloning inwisselen?"), L("Er gaan %lld stempels af.", result.stampsTotal), L("Inwisselen: %@", result.reward),
            onConfirm = { run(L("Beloning ingewisseld"), undoable = true, action = { BusinessApi.redeem(result.code) }) },
            onDismiss = { confirmRedeem = false },
        )
    }
}

