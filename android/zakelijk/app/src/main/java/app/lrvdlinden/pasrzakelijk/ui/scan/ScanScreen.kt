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

    fun look(code: String) {
        val normalized = code.trim().uppercase()
        if (normalized.matches(Regex("PC[A-HJ-NP-Z2-9]{22}"))) {
            couponCode = normalized
            manual = ""
            return
        }
        if (busy || result != null || couponCode != null) return
        busy = true
        scope.launch {
            try {
                val r = BusinessApi.scan(code)
                error = null
                manual = ""
                result = r
            } catch (e: Exception) {
                error = e.message
                haptics.error()
            } finally {
                busy = false
            }
        }
    }

    fun lookManual() {
        val code = manual.trim().uppercase().takeIf { it.matches(Regex("PC[A-HJ-NP-Z2-9]{22}")) }
            ?: MemberCode.extract(manual)
        if (code == null) {
            error = L("Een code begint met PZ. Typ hem over zoals hij onder de QR-code staat.")
            haptics.error()
            return
        }
        focus.clearFocus()
        look(code)
    }

    ScreenScaffold(L("Scannen"), actions = {
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
                            paused = result != null || busy || typing, torch = torch,
                            onTorchAvailable = { torchAvailable = it }, onCode = { raw ->
                                val code = raw.trim().uppercase().takeIf { it.matches(Regex("PC[A-HJ-NP-Z2-9]{22}")) }
                                    ?: MemberCode.extract(raw)
                                if (code != null) look(code) else { error = L("Deze QR-code is geen klantkaart van Pasr."); haptics.error() }
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
                        L("Richt de camera op de QR-code van je klant"), color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 15.sp,
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
    couponCode?.let { code ->
        app.lrvdlinden.pasrzakelijk.ui.cards.CouponBusinessDialog(business.id, initialCode = code) {
            couponCode = null
        }
    }
}
