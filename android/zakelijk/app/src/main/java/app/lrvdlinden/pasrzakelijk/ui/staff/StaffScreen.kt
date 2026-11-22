package app.lrvdlinden.pasrzakelijk.ui.staff

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.PersonRemove
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.data.Business
import app.lrvdlinden.pasrzakelijk.data.BusinessApi
import app.lrvdlinden.pasrzakelijk.data.BusinessRole
import app.lrvdlinden.pasrzakelijk.data.StaffInvite
import app.lrvdlinden.pasrzakelijk.data.StaffMember
import app.lrvdlinden.pasrzakelijk.ui.BigButton
import app.lrvdlinden.pasrzakelijk.ui.ConfirmDialog
import app.lrvdlinden.pasrzakelijk.ui.ErrorLine
import app.lrvdlinden.pasrzakelijk.ui.FullSheet
import app.lrvdlinden.pasrzakelijk.ui.Group
import app.lrvdlinden.pasrzakelijk.ui.GroupDivider
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.PzField
import app.lrvdlinden.pasrzakelijk.ui.ScreenScaffold
import app.lrvdlinden.pasrzakelijk.ui.SectionFooter
import app.lrvdlinden.pasrzakelijk.ui.SectionHeader
import app.lrvdlinden.pasrzakelijk.ui.cards.QrCode
import app.lrvdlinden.pasrzakelijk.ui.rememberHaptics
import app.lrvdlinden.pasrzakelijk.ui.shareText
import kotlinx.coroutines.launch

/** Medewerkers (eigenaar): uitnodigen met een link, intrekken. Medewerkers zien alleen de scanner. */
@Composable
fun StaffScreen(business: Business) {
    val demo = if (app.lrvdlinden.pasrzakelijk.data.Demo.enabled) app.lrvdlinden.pasrzakelijk.data.Demo.staff else null
    var staff by remember { mutableStateOf(demo ?: emptyList()) }
    var loaded by remember { mutableStateOf(demo != null) }
    var error by remember { mutableStateOf<String?>(null) }
    var inviting by remember { mutableStateOf(false) }
    var revoking by remember { mutableStateOf<StaffMember?>(null) }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    fun load() {
        if (demo != null) return
        scope.launch {
            try { staff = BusinessApi.staff(business.id); error = null } catch (e: Exception) { error = e.message }
            loaded = true
        }
    }
    LaunchedEffect(business.id) { load() }
    val active = staff.filter { !it.revoked }
    val revoked = staff.filter { it.revoked }

    ScreenScaffold(L("Medewerkers"), actions = {
        IconButton(onClick = { inviting = true }) { Icon(Icons.Filled.PersonAdd, L("Uitnodigen"), tint = Pz.accent) }
    }) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Column(Modifier.widthIn(max = 620.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
                error?.let { Spacer(Modifier.height(8.dp)); ErrorLine(it) }
                SectionHeader(L("Team"))
                Group {
                    if (!loaded) Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Pz.accent) }
                    active.forEachIndexed { i, m ->
                        if (i > 0) GroupDivider()
                        StaffRow(m, onRevoke = if (m.role != BusinessRole.owner) ({ revoking = m }) else null)
                    }
                    if (loaded && active.none { it.role != BusinessRole.owner }) {
                        if (active.isNotEmpty()) GroupDivider()
                        Text(L("Nog geen medewerkers. Nodig iemand uit; die logt in met een eigen Pasr-account en ziet alleen de scanner."),
                            Modifier.padding(16.dp), color = Pz.muted, fontSize = 15.sp)
                    }
                }
                SectionFooter(L("Houd een medewerker ingedrukt of tik op ⋮ om in te trekken. Wie is ingetrokken, kan direct geen stempels meer zetten."))
                if (revoked.isNotEmpty()) {
                    SectionHeader(L("Ingetrokken"))
                    Group {
                        revoked.forEachIndexed { i, m -> if (i > 0) GroupDivider(); StaffRow(m, null, dim = true) }
                    }
                }
                Spacer(Modifier.height(16.dp))
                BigButton(L("Medewerker uitnodigen"), { inviting = true }, icon = Icons.Filled.PersonAdd)
                Spacer(Modifier.height(24.dp))
            }
        }
    }
    if (inviting) InviteStaffSheet(business) { inviting = false; load() }
    revoking?.let { m ->
        ConfirmDialog(
            L("Medewerker intrekken?"), L("%@ kan dan geen stempels meer zetten voor %@.", m.name.ifEmpty { m.email }, business.name),
            L("Intrekken"), destructive = true,
            onConfirm = {
                scope.launch {
                    try { BusinessApi.revoke(m.id); haptics.success(); load() } catch (e: Exception) { error = e.message }
                }
            },
            onDismiss = { revoking = null },
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun StaffRow(m: StaffMember, onRevoke: (() -> Unit)?, dim: Boolean = false) {
    var menu by remember { mutableStateOf(false) }
    val alpha = if (dim) 0.6f else 1f
    Row(
        Modifier.fillMaxWidth().combinedClickable(onClick = {}, onLongClick = { if (onRevoke != null) menu = true })
            .padding(start = 16.dp, end = 4.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            when { m.role == BusinessRole.owner -> Icons.Filled.WorkspacePremium; m.pending -> Icons.Outlined.Email; else -> Icons.Filled.Person }, null,
            tint = (if (m.role == BusinessRole.owner) Pz.amber else Pz.mint).copy(alpha = alpha), modifier = Modifier.size(22.dp),
        )
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Text(m.name.ifEmpty { m.email.ifEmpty { "–" } }, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = Pz.text.copy(alpha = alpha))
            if (m.email.isNotEmpty() && m.name.isNotEmpty()) Text(m.email, fontSize = 12.sp, color = Pz.muted)
        }
        Text(
            when {
                m.role == BusinessRole.owner -> L("Eigenaar"); m.revoked -> L("Ingetrokken"); m.expired -> L("Verlopen")
                m.pending -> L("Uitgenodigd"); else -> L("Medewerker")
            },
            fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Pz.muted, modifier = Modifier.padding(end = if (onRevoke == null) 12.dp else 0.dp),
        )
        if (onRevoke != null) {
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, L("Meer"), tint = Pz.muted) }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem(
                        text = { Text(L("Intrekken"), color = Pz.coral) },
                        leadingIcon = { Icon(Icons.Outlined.PersonRemove, null, tint = Pz.coral) },
                        onClick = { menu = false; onRevoke() },
                    )
                }
            }
        }
    }
}

/** Medewerker uitnodigen: naam (en e-mail), daarna de link delen. */
@Composable
fun InviteStaffSheet(business: Business, demoInvite: StaffInvite? = null, onDismiss: () -> Unit) {
    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var invite by remember { mutableStateOf(demoInvite) }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val context = LocalContext.current
    FullSheet(
        onDismiss, L("Medewerker uitnodigen"),
        cancelText = if (invite == null) L("Annuleer") else null,
        confirmText = if (invite == null) L("Maak link") else L("Klaar"),
        confirmEnabled = invite != null || name.isNotBlank(), busy = busy,
        onConfirm = {
            if (invite != null) { onDismiss(); return@FullSheet }
            busy = true; message = null
            scope.launch {
                try { invite = BusinessApi.invite(business.id, name.trim(), email.trim()); haptics.success() }
                catch (e: Exception) { message = e.message; haptics.error() } finally { busy = false }
            }
        },
    ) {
        Column(Modifier.imePadding().verticalScroll(rememberScrollState()).padding(20.dp)) {
            val inv = invite
            if (inv != null) {
                Column(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Pz.card).padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Icon(Icons.Filled.CheckCircle, null, tint = Pz.mint, modifier = Modifier.size(44.dp))
                    Text(L("Uitnodiging klaar"), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Pz.text)
                    Text(L("Stuur deze link naar je medewerker. De link werkt 14 dagen en maar één keer."), color = Pz.muted, textAlign = TextAlign.Center)
                    val qr = remember(inv.link) { QrCode.bitmap(inv.link, 540)?.asImageBitmap() }
                    if (qr != null) Image(qr, L("QR-code van de uitnodiging"), filterQuality = FilterQuality.None,
                        modifier = Modifier.width(180.dp).aspectRatio(1f).clip(RoundedCornerShape(14.dp)).background(Color.White).padding(10.dp))
                    BigButton(L("Link delen"), {
                        context.shareText(L("Je bent uitgenodigd om stempels te zetten voor %@ in de app Pasr Zakelijk.", business.name) + "\n" + inv.link,
                            L("Uitnodiging Pasr Zakelijk"))
                    }, icon = Icons.Filled.Share)
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    PzField(name, { name = it }, L("Naam"), capitalization = KeyboardCapitalization.Words)
                    PzField(email, { email = it.trim() }, L("E-mailadres (optioneel)"), keyboardType = KeyboardType.Email,
                        capitalization = KeyboardCapitalization.None, autoCorrect = false)
                }
                SectionFooter(L("Je medewerker maakt een gratis Pasr-account (of logt in) en accepteert de uitnodiging. Medewerkers kunnen alleen scannen."))
                message?.let { Spacer(Modifier.height(12.dp)); ErrorLine(it) }
            }
        }
    }
}
