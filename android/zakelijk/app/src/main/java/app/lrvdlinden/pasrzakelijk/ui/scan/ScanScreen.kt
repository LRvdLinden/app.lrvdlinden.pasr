package app.lrvdlinden.pasrzakelijk.ui.scan

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FlashlightOff
import androidx.compose.material.icons.filled.FlashlightOn
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.NoPhotography
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.data.Business
import app.lrvdlinden.pasrzakelijk.data.BusinessApi
import app.lrvdlinden.pasrzakelijk.data.MemberCode
import app.lrvdlinden.pasrzakelijk.data.ScanResult
import app.lrvdlinden.pasrzakelijk.data.MemberScan
import app.lrvdlinden.pasrzakelijk.data.ScanCode
import app.lrvdlinden.pasrzakelijk.data.TicketEvent
import app.lrvdlinden.pasrzakelijk.data.TicketScan
import app.lrvdlinden.pasrzakelijk.data.TkApi
import app.lrvdlinden.pasrzakelijk.data.TkText
import app.lrvdlinden.pasrzakelijk.core.Prefs
import app.lrvdlinden.pasrzakelijk.ui.tickets.MemberScanSheet
import app.lrvdlinden.pasrzakelijk.ui.tickets.TicketScanSheet
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import app.lrvdlinden.pasrzakelijk.ui.BigButton
import app.lrvdlinden.pasrzakelijk.ui.EmptyState
import app.lrvdlinden.pasrzakelijk.ui.ErrorLine
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.isPreview
import app.lrvdlinden.pasrzakelijk.ui.PzField
import app.lrvdlinden.pasrzakelijk.ui.ScreenScaffold
import app.lrvdlinden.pasrzakelijk.ui.rememberHaptics
import kotlinx.coroutines.launch

/** Hoofdscherm: camera die de QR-code van de klant leest, of de code typen. Daarna het resultaat met de knoppen. */
@Composable
fun ScanScreen(business: Business, demoResult: ScanResult? = null) {
    val demoCamera = app.lrvdlinden.pasrzakelijk.data.Demo.enabled
    val context = LocalContext.current
    val inspection = isPreview()
    var manual by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var result by remember { mutableStateOf(demoResult) }
    var couponCode by remember { mutableStateOf<String?>(null) }
    var ticketScan by remember { mutableStateOf<TicketScan?>(null) }
    var memberScan by remember { mutableStateOf<MemberScan?>(null) }
    // Scannen voor één event (leeg = alle events van de zaak)
    var eventFilter by remember(business.id) { mutableStateOf(Prefs.string("scan.event." + business.id, "")) }
    var events by remember(business.id) { mutableStateOf<List<TicketEvent>>(emptyList()) }
    var savingUnits by remember(business.id) { mutableStateOf<Map<String, String>>(emptyMap()) }
    var eventMenu by remember { mutableStateOf(false) }
    var torch by remember { mutableStateOf(false) }
    var torchAvailable by remember { mutableStateOf(false) }
    var typing by remember { mutableStateOf(false) }
    var granted by remember {
        mutableStateOf(!inspection && ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
    }
    var asked by remember { mutableStateOf(false) }
    val hasCamera = remember { inspection || context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> granted = ok; asked = true }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val focus = LocalFocusManager.current

    LaunchedEffect(Unit) { if (!granted && hasCamera && !inspection) permission.launch(Manifest.permission.CAMERA) }
    // komende events (eventfilter) en spaar-eenheid per klantenkaart; mislukt het, dan geen filter
    LaunchedEffect(business.id) {
        if (inspection) return@LaunchedEffect
        val now = System.currentTimeMillis()
        events = runCatching { TkApi.events(business.id) }.getOrDefault(emptyList())
            .filter { it.isPublished && it.endsAt.time > now - 6 * 3600_000L }
        if (eventFilter.isNotEmpty() && events.none { it.id == eventFilter }) eventFilter = ""
        savingUnits = runCatching { TkApi.memberCards(business.id) }.getOrDefault(emptyList()).associate { it.id to it.goals.savingUnit }
    }

    /** Oudere klantcodes zonder PZ: toch nog als stempelkaart proberen. */
    suspend fun legacy(code: String): ScanResult? = MemberCode.extract(code)?.let { c -> runCatching { BusinessApi.scan(c) }.getOrNull() }

    fun look(raw: String) {
        val kind = ScanCode.classify(raw)
        if (kind == null) {
            error = L("Deze code is niet bekend. Laat de klant de kaart opnieuw tonen of typ de code over.")
            haptics.error()
            return
        }
        if (kind is ScanCode.Coupon) {
            couponCode = kind.code
            manual = ""
            return
        }
        if (busy || result != null || couponCode != null || ticketScan != null || memberScan != null) return
        busy = true
        scope.launch {
            try {
                when (kind) {
                    is ScanCode.StampCard -> result = BusinessApi.scan(kind.code)
                    is ScanCode.Ticket -> {
                        val t: TicketScan? = try {
                            TkApi.scanTicket(business.id, kind.code, eventFilter.ifEmpty { null })
                        } catch (e: Exception) {
                            result = legacy(kind.code) ?: throw e
                            null
                        }
                        if (t != null) {
                            val old = if (t.result == "invalid") legacy(kind.code) else null
                            if (old != null) result = old else ticketScan = t
                        }
                    }
                    is ScanCode.MemberCardCode -> {
                        val m: MemberScan? = try {
                            TkApi.scanMemberCard(business.id, kind.code)
                        } catch (e: Exception) {
                            result = legacy(kind.code) ?: throw e
                            null
                        }
                        if (m != null) {
                            val old = if (m.result == "invalid") legacy(kind.code) else null
                            if (old != null) result = old else memberScan = m
                        }
                    }
                    is ScanCode.Coupon -> Unit
                }
                error = null
                manual = ""
            } catch (e: Exception) {
                error = e.message
                haptics.error()
            } finally {
                busy = false
            }
        }
    }

    fun lookManual() {
        if (ScanCode.classify(manual) == null) {
            error = L("Een code begint met PZ. Typ hem over zoals hij onder de QR-code staat.")
            haptics.error()
            return
        }
        focus.clearFocus()
        look(manual)
    }

    ScreenScaffold(L("Scannen"), actions = {
        if (events.isNotEmpty()) {
            Box {
                IconButton(onClick = { eventMenu = true }) {
                    Icon(Icons.Filled.ConfirmationNumber, L("Scannen voor één event"), tint = if (eventFilter.isEmpty()) Pz.muted else Pz.accent)
                }
                DropdownMenu(eventMenu, onDismissRequest = { eventMenu = false }) {
                    DropdownMenuItem(text = { Text(L("Alle events")) }, onClick = {
                        eventFilter = ""; Prefs.putString("scan.event." + business.id, ""); eventMenu = false
                    })
                    events.forEach { e ->
                        DropdownMenuItem(text = { Text(e.name + " · " + TkText.dayMonth(e.startsAt)) }, onClick = {
                            eventFilter = e.id; Prefs.putString("scan.event." + business.id, e.id); eventMenu = false
                        })
                    }
                }
            }
        }
        if (torchAvailable && granted) {
            IconButton(onClick = { torch = !torch }) {
                Icon(if (torch) Icons.Filled.FlashlightOn else Icons.Filled.FlashlightOff, if (torch) L("Zaklamp uit") else L("Zaklamp aan"), tint = Pz.accent)
            }
        }
    }) {
        Column(Modifier.fillMaxSize().imePadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            val shape = RoundedCornerShape(24.dp)
            Box(
                Modifier.weight(1f).fillMaxWidth().clip(shape).background(if (granted || demoCamera) Color.Black else Pz.card).border(1.dp, Pz.line, shape),
                contentAlignment = Alignment.Center,
            ) {
                if ((granted && hasCamera) || demoCamera) {
                    if (!demoCamera) {
                        QrCamera(
                            paused = result != null || ticketScan != null || memberScan != null || busy || typing, torch = torch,
                            onTorchAvailable = { torchAvailable = it }, onCode = { raw ->
                                if (ScanCode.classify(raw) != null) look(raw) else { error = L("Deze QR-code is geen klantkaart van Pasr."); haptics.error() }
                            },
                            modifier = Modifier.fillMaxSize(),
                        )
                    } else {
                        Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Color(0xFF2A2C38), Color(0xFF14151C)))))
                    }
                    Box(
                        Modifier.size(230.dp).drawBehind {
                            drawRoundRect(
                                Color.White.copy(alpha = 0.9f), cornerRadius = CornerRadius(26.dp.toPx()),
                                style = Stroke(3.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(26.dp.toPx(), 14.dp.toPx()))),
                            )
                        },
                    )
                    if (busy) CircularProgressIndicator(color = Color.White)
                    Text(
                        events.firstOrNull { it.id == eventFilter }?.let { L("Scannen · %@", it.name) }
                            ?: L("Richt de camera op de QR-code, het ticket of de klantenkaart"), color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 15.sp,
                        modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 14.dp).clip(CircleShape)
                            .background(Color.Black.copy(alpha = 0.55f)).padding(horizontal = 14.dp, vertical = 8.dp),
                    )
                } else {
                    EmptyState(
                        Icons.Outlined.NoPhotography, L("Camera niet beschikbaar"),
                        if (hasCamera) L("Geef Pasr Zakelijk toegang tot de camera in Instellingen, of typ de code van de klant hieronder.")
                        else L("Dit apparaat kan hier geen QR-codes scannen. Typ de code van de klant hieronder."),
                    ) {
                        if (hasCamera) {
                            BigButton(if (asked) L("Open Instellingen") else L("Camera toestaan"), {
                                if (asked) {
                                    runCatching {
                                        context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + context.packageName)))
                                    }
                                } else permission.launch(Manifest.permission.CAMERA)
                            }, Modifier.padding(horizontal = 24.dp))
                        }
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                PzField(
                    manual, { manual = it }, L("Of typ de code (PZ…)"),
                    modifier = Modifier.weight(1f).onFocusChanged { typing = it.isFocused },
                    capitalization = KeyboardCapitalization.Characters, autoCorrect = false, monospace = true,
                    imeAction = ImeAction.Search, onIme = { lookManual() },
                )
                val enabled = manual.isNotBlank() && !busy
                Box(
                    Modifier.size(50.dp).clip(RoundedCornerShape(12.dp)).background(if (enabled) Pz.accent else Pz.accent.copy(alpha = 0.45f))
                        .clickable(enabled = enabled) { lookManual() },
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Filled.Search, L("Zoek code"), tint = Color.White) }
            }
            error?.let { ErrorLine(it) }
        }
    }

    result?.let { r ->
        ScanResultSheet(business, r, onDismiss = { result = null })
    }
    ticketScan?.let { t -> TicketScanSheet(t) { ticketScan = null } }
    memberScan?.let { m -> MemberScanSheet(business, m, m.cardId?.let { savingUnits[it] }) { memberScan = null } }
    couponCode?.let { code ->
        app.lrvdlinden.pasrzakelijk.ui.cards.CouponBusinessDialog(business.id, initialCode = code) {
            couponCode = null
        }
    }
}
