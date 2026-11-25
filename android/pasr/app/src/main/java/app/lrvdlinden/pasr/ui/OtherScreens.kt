package app.lrvdlinden.pasr.ui

import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import app.lrvdlinden.pasr.notify.NearbyStoresAndroid
import app.lrvdlinden.pasr.notify.Reminders
import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.material.icons.outlined.Restore
import androidx.compose.material.icons.outlined.Storefront
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import app.lrvdlinden.pasr.Incoming
import app.lrvdlinden.pasr.data.Account
import app.lrvdlinden.pasr.data.Business
import app.lrvdlinden.pasr.data.BusinessInfo
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.CardDetails
import app.lrvdlinden.pasr.data.CardKind
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.PasrError
import app.lrvdlinden.pasr.data.Prefs
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SimpleScaffold(title: String, content: @Composable () -> Unit) {
    val nav = LocalNav.current
    val snack = LocalSnack.current
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        snackbarHost = { SnackbarHost(snack) },
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = { IconButton({ nav.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Terug") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) { content() }
    }
}

/** Voorbeeld van een zakelijke stempelkaart en aansluiten (of een lidcode uit de browser overnemen). */
@Composable
fun StampJoinScreen(cardId: String, code: String?, referralToken: String? = null) {
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    var info by remember { mutableStateOf<BusinessInfo?>(null) }
    var loading by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val already = CardStore.visible.firstOrNull { it.details.businessCardId.equals(cardId, true) }
    LaunchedEffect(cardId) { info = Business.preview(cardId); loading = false }
    SimpleScaffold("Stempelkaart") {
        val i = info
        val preview = Card(
            storeName = i?.displayName ?: "Stempelkaart", kindRaw = CardKind.STAMPS.raw, colorHex = i?.color ?: "#6A5CFF", number = "PZ",
            formatRaw = "qr", logo = i?.logo?.takeIf { !it.startsWith("http") }?.substringAfter(","),
            details = CardDetails(issuer = "business", businessCardId = cardId, stampsTotal = i?.stampsTotal ?: 10, stampsCount = 0, reward = i?.reward),
        )
        Gap(8.dp)
        CardFace(preview, Modifier.fillMaxWidth())
        Gap(16.dp)
        if (loading) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        else {
            if (i == null || !i.active) Text("Deze stempelkaart is niet (meer) beschikbaar of nog niet gepubliceerd.", color = MaterialTheme.colorScheme.error)
            else {
                Text(i.displayName, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                i.name?.takeIf { it != i.displayName }?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                Gap(10.dp)
                Text("${i.stampsTotal ?: 10} stempels${i.reward?.let { ": $it" } ?: ""}", fontWeight = FontWeight.SemiBold)
                Gap(8.dp)
                Text("Je krijgt een eigen QR-code. Laat die scannen bij de kassa; de zaak zet de stempels. Er hangt niets persoonlijks aan.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            error?.let { Gap(10.dp); Text(it, color = MaterialTheme.colorScheme.error) }
            Gap(24.dp)
            if (already != null) BrandButton("Open je stempelkaart") { nav.replace(Screen.Detail(already.id)) }
            else if (i != null && i.active) BrandButton(if (busy) "Even geduld…" else "Toevoegen aan Pasr", enabled = !busy) {
                busy = true; error = null
                scope.launch {
                    try {
                        val card = code?.let { Business.claim(it, cardId, i) } ?: Business.join(cardId, i, referralToken)
                        nav.replace(Screen.Detail(card.id))
                    } catch (e: PasrError) { error = e.message } catch (e: Exception) { error = "Er ging iets mis. Probeer het opnieuw." }
                    busy = false
                }
            }
        }
    }
}

/** Een gedeelde kaart (link) toevoegen. */
@Composable
fun ImportScreen(card: Card) {
    val nav = LocalNav.current
    SimpleScaffold("Gedeelde kaart") {
        Gap(8.dp)
        CardFace(card, Modifier.fillMaxWidth())
        Gap(16.dp)
        Text(card.storeName, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text(card.kind.title, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (card.kind != CardKind.STAMPS) { Gap(16.dp); BarcodeImage(card.number, card.format) }
        Gap(24.dp)
        BrandButton("Toevoegen aan mijn kaarten") {
            val c = if (card.kind == CardKind.STAMPS && !card.details.isBusiness) card.copy(kindRaw = CardKind.LOYALTY.raw,
                note = "Stempelkaart: ${card.details.stampsCountValue} van ${card.details.stampsTotalValue}") else card
            CardStore.upsert(c)
            nav.replace(Screen.Detail(c.id))
        }
        TextButton({ nav.pop() }, Modifier.fillMaxWidth()) { Text("Niet nu") }
    }
}

@Composable
fun SettingsScreen(onAppearance: (String) -> Unit) {
    val nav = LocalNav.current
    val context = LocalContext.current
    val session by Account.session.collectAsState()
    var lock by remember { mutableStateOf(Prefs.lockEnabled) }
    var screenshotBlock by remember { mutableStateOf(Prefs.bool("screen.block")) }
    var reminders by remember { mutableStateOf(Prefs.remindersEnabled) }
    var brightness by remember { mutableStateOf(Prefs.brightness) }
    var appearance by remember { mutableStateOf(Prefs.appearance) }
    var news by remember { mutableStateOf(Prefs.bool("push.news")) }
    val scope = rememberCoroutineScope()
    var nearby by remember { mutableStateOf(NearbyStoresAndroid.enabled()) }
    var nearbyHint by remember { mutableStateOf("") }
    val backgroundPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()) { granted ->
        if (granted && NearbyStoresAndroid.ready(context)) {
            NearbyStoresAndroid.setEnabled(context, true)
            nearby = NearbyStoresAndroid.enabled()
        } else nearbyHint = "Geef toegang Altijd bij de locatie-instellingen en zet de schakelaar opnieuw aan."
    }
    val foregroundPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()) { grants ->
        if (grants[Manifest.permission.ACCESS_FINE_LOCATION] != true) {
            nearbyHint = "Precieze locatie is vereist om bij de winkel te kunnen controleren."
        } else if (Build.VERSION.SDK_INT >= 30) {
            nearbyHint = "Kies bij Android-instellingen voor locatietoegang Altijd, daarna kan je winkelmeldingen activeren."
            Incoming.leavingOnPurpose = true
            context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                android.net.Uri.parse("package:${context.packageName}")))
        } else if (Build.VERSION.SDK_INT == 29) {
            backgroundPermission.launch(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        } else if (NearbyStoresAndroid.ready(context)) {
            NearbyStoresAndroid.setEnabled(context, true)
            nearby = NearbyStoresAndroid.enabled()
        }
    }
    val notificationPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()) { granted ->
        nearbyHint = if (granted) "Zet 'Kaart tonen bij de winkel' opnieuw aan." else "Sta meldingen toe in Android-instellingen."
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        nearby = NearbyStoresAndroid.enabled()
        if (nearby && !NearbyStoresAndroid.ready(context)) {
            NearbyStoresAndroid.setEnabled(context, false)
            nearby = false
        }
    }
    SimpleScaffold("Instellingen") {
        SectionHeader("Account")
        Group {
            RowItem(Icons.Outlined.AccountCircle, session?.let { it.firstName ?: it.email } ?: "Pasr-account",
                session?.email ?: "Bewaar je kaarten versleuteld en zet ze over naar een nieuwe telefoon") { nav.push(Screen.AccountScreen) }
        }
        SectionHeader("Beveiliging")
        Group {
            Toggle("App-slot", lock, "Vingerafdruk, gezicht of pincode bij openen") { on ->
                val a = context as? FragmentActivity
                if (a == null || !AppLock.isAvailable(context)) return@Toggle
                AppLock.authenticate(a, if (on) "Zet het slot aan" else "Zet het slot uit") { ok ->
                    if (ok) { Prefs.lockEnabled = on; lock = on; (a as? app.lrvdlinden.pasr.MainActivity)?.applyScreenProtection() }
                }
            }
            Toggle("Screenshots blokkeren", screenshotBlock, "Blokkeer screenshots en schermopnames onafhankelijk van het app-slot") { on ->
                screenshotBlock = on; Prefs.setBool("screen.block", on)
                (context as? app.lrvdlinden.pasr.MainActivity)?.applyScreenProtection()
            }
            Toggle("Volle helderheid bij een kaart", brightness, "Makkelijker scannen bij de kassa") { brightness = it; Prefs.brightness = it }
        }
        UseSettings()
        SectionHeader("Meldingen")
        Group {
            Toggle("Herinneringen", reminders, "Cadeaukaarten en codes die verlopen, abonnementen die verlengen") { reminders = it; Prefs.remindersEnabled = it }
            RowItem(Icons.Outlined.Notifications, "Herinneringsvoorkeuren", "Vervaldatums, tegoed en e-mail") { nav.push(Screen.ReminderPreferences) }
            if (app.lrvdlinden.pasr.notify.Push.available(context)) {
                Toggle("Nieuws over mijn kaarten", news, "Af en toe een bericht over winkels waarvan je een kaart hebt. Stempels van zaken krijg je altijd.") {
                    news = it; Prefs.setBool("push.news", it)
                    scope.launch { app.lrvdlinden.pasr.data.DeviceRegistry.registerIfNeeded(context, force = true) }
                }
            }
            Toggle("Kaart tonen bij de winkel", nearby,
                "Automatische melding bij een bewaarde winkelspeld, alleen met toestemming Altijd en precieze locatie.") { on ->
                if (!on) {
                    NearbyStoresAndroid.setEnabled(context, false)
                    nearby = false
                    nearbyHint = ""
                } else if (Build.VERSION.SDK_INT >= 33 && !Reminders.canNotify(context)) {
                    nearbyHint = "Sta eerst meldingen toe."
                    notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
                    != PackageManager.PERMISSION_GRANTED) {
                    foregroundPermission.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION))
                } else if (Build.VERSION.SDK_INT >= 29 &&
                    ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                    != PackageManager.PERMISSION_GRANTED) {
                    if (Build.VERSION.SDK_INT >= 30) {
                        nearbyHint = "Kies in Android-instellingen Locatie > Altijd voor Pasr, en zet de schakelaar daarna aan."
                        Incoming.leavingOnPurpose = true
                        context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            android.net.Uri.parse("package:${context.packageName}")))
                    } else {
                        backgroundPermission.launch(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                    }
                } else if (!NearbyStoresAndroid.available(context)) {
                    nearbyHint = "Google Play-services is nodig voor automatische winkelmeldingen."
                } else {
                    NearbyStoresAndroid.setEnabled(context, true)
                    nearby = NearbyStoresAndroid.enabled()
                    nearbyHint = if (NearbyStoresAndroid.monitoredCount(context) == 0)
                        "Bewaar eerst een winkelspeld bij een kaart. Alleen opgeslagen locaties kunnen worden bewaakt."
                        else "Winkelmeldingen zijn actief."
                }
            }
            if (nearbyHint.isNotBlank()) {
                Text(nearbyHint, Modifier.padding(12.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            RowItem(Icons.Outlined.Notifications, "Meldingen in Android-instellingen") {
                val i = if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:${context.packageName}"))
                Incoming.leavingOnPurpose = true
                runCatching { context.startActivity(i) }
            }
        }
        SectionHeader("Weergave")
        Group {
            Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Palette, null, tint = MaterialTheme.colorScheme.primary)
                listOf("auto" to "Automatisch", "light" to "Licht", "dark" to "Donker").forEach { (k, t) ->
                    FilterChip(appearance == k, { appearance = k; Prefs.appearance = k; onAppearance(k) }, { Text(t) })
                }
            }
        }
        SectionHeader("Kaarten")
        Group {
            RowItem(Icons.Outlined.Restore, "Recent verwijderd", "${CardStore.recentlyDeleted.size} kaart(en), 30 dagen terug te zetten") { nav.push(Screen.Deleted) }
            RowItem(Icons.Outlined.Storefront, "Winkel aanvragen", "Staat jouw winkel er niet bij? Laat het ons weten") {
                Incoming.leavingOnPurpose = true; openUrl(context, "https://pasr.nl/support/#winkel")
            }
        }
        SectionHeader("Delen")
        Group {
            RowItem(null, "Gedeelde Pasr", "Deel kaarten met je gezin of huisgenoten") { nav.push(Screen.Groups()) }
            RowItem(null, "Tijdelijk gedeeld", "Bekijk en beheer tijdelijke kaarten") { nav.push(Screen.TemporaryShares) }
        }
        SectionHeader("Verjaardagsvoordeel")
        Group {
            RowItem(null, "Verjaardag", "Krijg een seintje over verjaardagsvoordeel") { nav.push(Screen.Birthday) }
        }
        SectionHeader("Back-up")
        Group {
            RowItem(Icons.Outlined.Restore, "Versleutelde back-up", "Kaarten, foto’s en bonnetjes bewaren of terugzetten") { nav.push(Screen.Backup) }
        }
        SectionHeader("Over Pasr")
        Group {
            RowItem(Icons.AutoMirrored.Outlined.HelpOutline, "Welkomstscherm opnieuw bekijken") { nav.push(Screen.Welcome) }
            RowItem(Icons.Outlined.PrivacyTip, "Privacy") { Incoming.leavingOnPurpose = true; openUrl(context, "https://pasr.nl/privacy/") }
            RowItem(Icons.AutoMirrored.Outlined.HelpOutline, "Support") { Incoming.leavingOnPurpose = true; openUrl(context, "https://pasr.nl/support/") }
        }
        MoreAppsCard()
        AppInfoFooter()
    }
}

@Composable
fun DeletedScreen() {
    val all by CardStore.cards.collectAsState()
    val deleted = all.filter { it.deletedAt != null }
    var purge by remember { mutableStateOf<Card?>(null) }
    SimpleScaffold("Recent verwijderd") {
        if (deleted.isEmpty()) Text("Niets verwijderd.", Modifier.fillMaxWidth().padding(32.dp), textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        deleted.forEach { c ->
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(0.35f)) { CardFace(c, Modifier.fillMaxWidth(), compact = true) }
                Column(Modifier.weight(0.65f).padding(start = 12.dp)) {
                    Text(c.storeName, fontWeight = FontWeight.SemiBold)
                    Row {
                        TextButton({ CardStore.restore(c.id) }) { Text("Terugzetten") }
                        TextButton({ purge = c }) { Text("Wissen", color = MaterialTheme.colorScheme.error) }
                    }
                }
            }
        }
    }
    purge?.let { c ->
        AlertDialog({ purge = null }, title = { Text("Definitief wissen?") }, text = { Text("${c.storeName} is daarna niet meer terug te halen.") },
            confirmButton = { TextButton({ CardStore.purge(c.id); purge = null }) { Text("Wissen", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton({ purge = null }) { Text("Annuleren") } })
    }
}

@Composable
fun DeleteIcon() = Icon(Icons.Outlined.DeleteOutline, null)
