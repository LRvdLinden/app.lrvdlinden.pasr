package app.lrvdlinden.pasrzakelijk.ui.settings

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Contrast
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.automirrored.filled.Help
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.FragmentActivity
import app.lrvdlinden.pasrzakelijk.core.Biometrics
import app.lrvdlinden.pasrzakelijk.core.Geo
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.core.Prefs
import app.lrvdlinden.pasrzakelijk.data.Account
import app.lrvdlinden.pasrzakelijk.data.Business
import app.lrvdlinden.pasrzakelijk.data.BusinessApi
import app.lrvdlinden.pasrzakelijk.data.BusinessStore
import app.lrvdlinden.pasrzakelijk.ui.BigButton
import app.lrvdlinden.pasrzakelijk.ui.ConfirmDialog
import app.lrvdlinden.pasrzakelijk.ui.EditBusinessSheet
import app.lrvdlinden.pasrzakelijk.ui.ErrorLine
import app.lrvdlinden.pasrzakelijk.ui.Group
import app.lrvdlinden.pasrzakelijk.ui.GroupDivider
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.isPreview
import app.lrvdlinden.pasrzakelijk.ui.PzField
import app.lrvdlinden.pasrzakelijk.ui.ScreenScaffold
import app.lrvdlinden.pasrzakelijk.ui.SectionFooter
import app.lrvdlinden.pasrzakelijk.ui.SectionHeader
import app.lrvdlinden.pasrzakelijk.ui.SettingsRow
import app.lrvdlinden.pasrzakelijk.ui.SuccessLine
import app.lrvdlinden.pasrzakelijk.ui.cards.Stepper
import app.lrvdlinden.pasrzakelijk.ui.rememberHaptics
import app.lrvdlinden.pasrzakelijk.ui.rememberOpenUrl
import kotlinx.coroutines.launch

val cooldownOptions = listOf(0, 1, 2, 5, 10, 15, 30, 60, 120, 240, 480, 720, 1440)

fun cooldownLabel(minutes: Int): String = when {
    minutes == 0 -> L("Geen")
    minutes < 60 -> L("%lld min", minutes)
    minutes == 1440 -> L("1 dag")
    else -> L("%lld uur", minutes / 60)
}

/** Instellingen: zaak, scannen (afkoeltijd, max per scan), vindbaar in Pasr, account, vergrendeling, weergave, hulp, Ontdekken, app-info. */
@Composable
fun SettingsScreen(business: Business) {
    val context = LocalContext.current
    val open = rememberOpenUrl()
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    var cooldown by remember(business) { mutableIntStateOf(cooldownOptions.minByOrNull { kotlin.math.abs(it - business.cooldownMinutes) } ?: 5) }
    var maxPerScan by remember(business) { mutableIntStateOf(business.maxPerScan.coerceIn(1, 30)) }
    var listed by remember(business) { mutableStateOf(business.listed) }
    var address by remember(business) { mutableStateOf(business.address) }
    val dirty = cooldown != (cooldownOptions.minByOrNull { kotlin.math.abs(it - business.cooldownMinutes) } ?: 5) ||
        maxPerScan != business.maxPerScan.coerceIn(1, 30) || listed != business.listed || address.trim() != business.address
    var saving by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var savedOK by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf(false) }
    var whatsNew by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var confirmSignOut by remember { mutableStateOf(false) }
    var cooldownMenu by remember { mutableStateOf(false) }
    var appearanceMenu by remember { mutableStateOf(false) }
    val inspection = isPreview()
    val bioAvailable = remember { inspection || Biometrics.isAvailable(context) }
    var update by remember { mutableStateOf<app.lrvdlinden.pasrzakelijk.core.UpdateCheck.Update?>(null) }
    LaunchedEffect(Unit) { if (!inspection) update = app.lrvdlinden.pasrzakelijk.core.UpdateCheck.check() }

    fun save() {
        saving = true; message = null
        scope.launch {
            var lat = business.lat
            var lng = business.lng
            val trimmed = address.trim()
            if (trimmed.isEmpty()) { lat = null; lng = null }
            else if (trimmed != business.address || lat == null) {
                val c = Geo.locate(context, trimmed)
                lat = c?.first; lng = c?.second
            }
            try {
                BusinessApi.saveSettings(business.id, BusinessApi.Settings(cooldown, maxPerScan, listed, trimmed, lat, lng))
                haptics.success()
                BusinessStore.load()
                savedOK = true
                message = if (trimmed.isNotEmpty() && lat == null) L("Opgeslagen, maar het adres is niet gevonden op de kaart. Controleer het adres.") else L("Opgeslagen")
            } catch (e: Exception) {
                savedOK = false
                message = e.message
                haptics.error()
            } finally { saving = false }
        }
    }

    ScreenScaffold(L("Instellingen")) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Column(Modifier.widthIn(max = 620.dp).fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
                // Zaak
                SectionHeader(L("Zaak"))
                Group {
                    Column(Modifier.padding(16.dp)) {
                        Text(business.name, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = Pz.text)
                        if (business.city.isNotEmpty()) Text(business.city, color = Pz.muted)
                        Text(if (business.isOwner) L("Je bent eigenaar") else L("Je bent medewerker"), fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                            color = if (business.isOwner) Pz.iris else Pz.mint)
                    }
                    if (business.isOwner) {
                        GroupDivider()
                        SettingsRow(L("Gegevens van de zaak wijzigen"), Icons.Filled.Edit, Pz.iris, onClick = { editing = true })
                    }
                }
                if (business.isOwner) {
                    // Scannen
                    SectionHeader(L("Scannen"))
                    Group {
                        Box {
                            SettingsRow(L("Afkoeltijd"), Icons.Filled.Timer, Pz.amber, onClick = { cooldownMenu = true }) {
                                Text(cooldownLabel(cooldown), color = Pz.muted, fontSize = 17.sp)
                            }
                            DropdownMenu(cooldownMenu, { cooldownMenu = false }) {
                                for (m in cooldownOptions) DropdownMenuItem(text = { Text(cooldownLabel(m)) }, onClick = { cooldown = m; cooldownMenu = false })
                            }
                        }
                        GroupDivider()
                        SettingsRow(L("Max. stempels per scan"), Icons.Filled.Verified, Pz.mint) {
                            Stepper(maxPerScan, 1..30) { maxPerScan = it }
                        }
                    }
                    SectionFooter(L("Afkoeltijd: zo lang moet een klant wachten voor de volgende stempel. Bij scannen kies je zelf het aantal stempels, tot het maximum."))
                    // Vindbaar in Pasr
                    SectionHeader(L("Vindbaar in Pasr"))
                    Group {
                        SettingsRow(L("Vindbaar in Pasr"), Icons.Filled.Place, Pz.coral, onClick = { listed = !listed }) {
                            Switch(listed, { listed = it }, colors = SwitchDefaults.colors(checkedTrackColor = Pz.mint))
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    PzField(address, { address = it }, L("Adres (straat, huisnummer, plaats)"), singleLine = false, capitalization = KeyboardCapitalization.Words)
                    SectionFooter(L("Pasr-gebruikers zoeken stempelkaarten in een lijst in de app. Met een adres staat je zaak ook bij \"In de buurt\". Pasr zoekt de plek op via de kaartdienst van je telefoon."))
                    if (dirty || saving || message != null) {
                        Spacer(Modifier.height(14.dp))
                        BigButton(L("Instellingen opslaan"), { save() }, enabled = dirty, busy = saving)
                        message?.let { Spacer(Modifier.height(8.dp)); if (savedOK) SuccessLine(it) else ErrorLine(it) }
                    }
                }
                // Account
                SectionHeader(L("Account"))
                Group {
                    Account.session?.email?.let { email ->
                        SettingsRow(L("Ingelogd als")) { Text(email, color = Pz.muted, fontSize = 15.sp, maxLines = 1) }
                        GroupDivider()
                    }
                    SettingsRow(L("Uitloggen"), Icons.AutoMirrored.Filled.Logout, Pz.sky, onClick = { confirmSignOut = true })
                    GroupDivider()
                    SettingsRow(L("Account verwijderen"), Icons.Filled.Delete, Pz.coral, titleColor = Pz.coral, onClick = { confirmDelete = true })
                }
                // Privacy en beveiliging
                SectionHeader(L("Privacy en beveiliging"))
                Group {
                    SettingsRow(L("Vergrendelen met vingerafdruk of gezicht"), Icons.Filled.Fingerprint, Pz.mint, enabled = bioAvailable, onClick = {
                        val target = !Prefs.appLock
                        (context as? FragmentActivity)?.let { activity ->
                            Biometrics.authenticate(activity, L("Bevestig om de vergrendeling te wijzigen.")) { ok -> if (ok) Prefs.changeAppLock(target) }
                        }
                    }) {
                        Switch(Prefs.appLock, null, enabled = bioAvailable, colors = SwitchDefaults.colors(checkedTrackColor = Pz.mint))
                    }
                }
                SectionFooter(
                    if (bioAvailable) L("Bij openen en na terugkeer naar de app vraagt Pasr Zakelijk om je vingerafdruk, gezicht of schermvergrendeling. Handig als de telefoon of tablet aan de kassa ligt.")
                    else L("Stel eerst een schermvergrendeling of vingerafdruk in op dit toestel.")
                )
                // Weergave
                Spacer(Modifier.height(18.dp))
                Group {
                    Box {
                        SettingsRow(L("Weergave"), Icons.Filled.Contrast, Color(0xFF8E8E93), onClick = { appearanceMenu = true }) {
                            Text(appearanceLabel(Prefs.appearance), color = Pz.muted, fontSize = 17.sp)
                        }
                        DropdownMenu(appearanceMenu, { appearanceMenu = false }) {
                            for (a in listOf("system", "light", "dark")) DropdownMenuItem(text = { Text(appearanceLabel(a)) }, onClick = { Prefs.changeAppearance(a); appearanceMenu = false })
                        }
                    }
                    if (!inspection && app.lrvdlinden.pasrzakelijk.push.Push.isAvailable(context)) {
                        GroupDivider()
                        SettingsRow(L("Meldingen"), Icons.Filled.Notifications, Pz.coral, onClick = {
                            runCatching {
                                context.startActivity(android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName))
                            }
                        })
                    }
                    GroupDivider()
                    SettingsRow(L("Taal"), Icons.Filled.Translate, Pz.sky, onClick = { openLanguageSettings(context) }) {
                        Text(if (app.lrvdlinden.pasrzakelijk.core.I18n.dutch) "Nederlands" else "English", color = Pz.muted, fontSize = 17.sp)
                    }
                }
                SectionFooter(L("Automatisch volgt de instelling van je telefoon of tablet."))
                // Hulp
                SectionHeader(L("Hulp"))
                Group {
                    SettingsRow(L("Hulp en contact"), Icons.AutoMirrored.Filled.Help, Pz.iris, external = true, onClick = { open("https://pasr.nl/support/") })
                    GroupDivider()
                    SettingsRow(L("Privacyverklaring"), Icons.Filled.PanTool, Pz.iris, external = true, onClick = { open("https://pasr.nl/privacy/#stempelkaarten-van-ondernemers") })
                    GroupDivider()
                    SettingsRow(L("Wat is nieuw"), Icons.Filled.AutoAwesome, Pz.coral, onClick = { whatsNew = true })
                    GroupDivider()
                    // Geen Play Store: geen beoordelingsvraag en geen "Beoordeel"-link (afspraak Léon).
                    // Geen Play Store: updates staan op pasr.nl/zakelijk/download/
                    SettingsRow(
                        if (update != null) L("Nieuwe versie %@ downloaden", update!!.version) else L("Nieuwste versie downloaden"),
                        Icons.Filled.SystemUpdate, if (update != null) Pz.mint else Pz.sky, external = true,
                        titleColor = if (update != null) Pz.mint else Pz.text,
                        onClick = { open(app.lrvdlinden.pasrzakelijk.core.Links.DOWNLOADS) })
                    GroupDivider()
                    SettingsRow(L("Pasr Zakelijk op pasr.nl"), Icons.Filled.Language, Pz.mint, external = true, onClick = { open("https://pasr.nl/zakelijk/") })
                }
                // Ontdekken
                SectionHeader(moreAppsSection())
                MoreAppsCard()
                AppInfoFooter()
            }
        }
    }
    if (editing) EditBusinessSheet(business) { editing = false }
    if (whatsNew) WhatsNewSheet { whatsNew = false }
    if (confirmSignOut) ConfirmDialog(L("Uitloggen?"), null, L("Uitloggen"), destructive = true,
        onConfirm = { scope.launch { Account.signOut(); BusinessStore.reset() } }, onDismiss = { confirmSignOut = false })
    if (confirmDelete) ConfirmDialog(
        L("Account verwijderen?"),
        L("Je Pasr-account wordt verwijderd, ook in de app Pasr. Ben je eigenaar, dan verdwijnen je zaak, kaarten en leden ook. Dit kan niet ongedaan worden gemaakt."),
        L("Account verwijderen"), destructive = true,
        onConfirm = { scope.launch { try { Account.deleteAccount(); BusinessStore.reset() } catch (e: Exception) { message = e.message } } },
        onDismiss = { confirmDelete = false },
    )
    LaunchedEffect(business.id) { message = null }
}

fun appearanceLabel(value: String) = when (value) { "light" -> L("Licht"); "dark" -> L("Donker"); else -> L("Automatisch") }

/** Taal per app (Android 13+), anders de taalinstellingen van het toestel. */
private fun openLanguageSettings(context: android.content.Context) {
    val intent = if (android.os.Build.VERSION.SDK_INT >= 33)
        android.content.Intent(android.provider.Settings.ACTION_APP_LOCALE_SETTINGS, android.net.Uri.parse("package:" + context.packageName))
    else android.content.Intent(android.provider.Settings.ACTION_LOCALE_SETTINGS)
    runCatching { context.startActivity(intent) }
}
