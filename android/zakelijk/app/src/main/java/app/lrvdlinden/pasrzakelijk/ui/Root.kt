package app.lrvdlinden.pasrzakelijk.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ExpandCircleDown
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.automirrored.outlined.ShowChart
import androidx.compose.material.icons.outlined.Style
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.core.Prefs
import app.lrvdlinden.pasrzakelijk.data.Account
import app.lrvdlinden.pasrzakelijk.data.Business
import app.lrvdlinden.pasrzakelijk.data.BusinessStore
import app.lrvdlinden.pasrzakelijk.data.DeviceRegistry
import app.lrvdlinden.pasrzakelijk.ui.cards.CardsScreen
import app.lrvdlinden.pasrzakelijk.ui.overview.OverviewScreen
import app.lrvdlinden.pasrzakelijk.ui.scan.ScanScreen
import app.lrvdlinden.pasrzakelijk.ui.settings.SettingsScreen
import app.lrvdlinden.pasrzakelijk.ui.staff.StaffScreen
import kotlinx.coroutines.launch

/** Inloggen → zaak registreren → wachten op goedkeuring → de app (tabbladen volgens je rol). */
@Composable
fun RootScreen() {
    val session = Account.session
    LaunchedEffect(session?.userID) {
        if (session != null) BusinessStore.load() else BusinessStore.reset()
        // platform en appversie melden (ook zonder account; opnieuw na inloggen of uitloggen)
        DeviceRegistry.register()
    }
    val current = BusinessStore.current
    when {
        session == null -> WelcomeScreen()
        !BusinessStore.loaded -> LoadingScreen()
        current != null -> if (current.isApproved) key(current.id) { MainTabs(current) } else PendingScreen(current)
        else -> RegisterBusinessScreen()
    }
    val invite = BusinessStore.pendingInvite
    if (invite != null && session != null && !ShellState.locked) {
        InviteAcceptSheet(invite) { BusinessStore.pendingInvite = null }
    }
}

@Composable
private fun LoadingScreen() {
    val scope = rememberCoroutineScope()
    Column(
        Modifier.fillMaxSize().background(Pz.bg).safeDrawingPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        ZakelijkLogo(26f)
        val error = BusinessStore.error
        if (error != null) {
            EmptyState(Icons.Filled.WifiOff, L("Laden lukt niet"), error) {
                BigButton(L("Opnieuw proberen"), { scope.launch { BusinessStore.load() } }, Modifier.width(260.dp))
                LinkButton(L("Uitloggen"), { scope.launch { Account.signOut() } }, color = Pz.coral)
            }
        } else {
            Spacer(Modifier.size(24.dp))
            androidx.compose.material3.CircularProgressIndicator(color = Pz.accent)
        }
    }
}

private enum class Tab(val key: String, val icon: ImageVector, val title: String, val ownerOnly: Boolean) {
    Scan("scan", Icons.Outlined.QrCodeScanner, "Scannen", false),
    Cards("cards", Icons.Outlined.Style, "Kaarten", true),
    Overview("overview", Icons.AutoMirrored.Outlined.ShowChart, "Overzicht", true),
    Staff("staff", Icons.Outlined.Group, "Medewerkers", true),
    Settings("settings", Icons.Outlined.Settings, "Instellingen", false),
}

/** Tabbladen: eigenaar ziet alles, een medewerker alleen Scannen (en Instellingen voor uitloggen). */
@Composable
fun MainTabs(business: Business, initialTab: String? = null) {
    val tabs = Tab.entries.filter { business.isOwner || !it.ownerOnly }
    var selected by remember {
        mutableStateOf((initialTab ?: Prefs.string("ui.tab", "scan")).let { k -> tabs.firstOrNull { it.key == k } ?: Tab.Scan })
    }
    NotificationPermissionAsk()
    Column(Modifier.fillMaxSize().background(Pz.bg)) {
        Box(Modifier.weight(1f)) {
            when (selected) {
                Tab.Scan -> ScanScreen(business)
                Tab.Cards -> CardsScreen(business)
                Tab.Overview -> OverviewScreen(business)
                Tab.Staff -> StaffScreen(business)
                Tab.Settings -> SettingsScreen(business)
            }
        }
        NavigationBar(containerColor = Pz.card, tonalElevation = 0.dp) {
            for (tab in tabs) {
                NavigationBarItem(
                    selected = tab == selected,
                    onClick = { selected = tab; Prefs.putString("ui.tab", tab.key) },
                    icon = { Icon(tab.icon, null) },
                    label = { Text(L(tab.title), fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = Pz.accent, selectedTextColor = Pz.accent,
                        indicatorColor = Pz.accent.copy(alpha = 0.14f),
                        unselectedIconColor = Pz.muted, unselectedTextColor = Pz.muted,
                    ),
                )
            }
        }
    }
}

/**
 * Schermopbouw met kop: zaakkiezer (bij meer dan één zaak) of titel, knoppen rechts en een terug-knop als dat kan.
 * Zelfde rol als de NavigationStack-toolbar op iOS.
 */
@Composable
fun ScreenScaffold(
    title: String,
    modifier: Modifier = Modifier,
    picker: Boolean = true,
    onBack: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier.fillMaxSize().background(Pz.bg)) {
        Row(
            Modifier.fillMaxWidth().statusBarsPadding().heightIn(min = 56.dp).padding(horizontal = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onBack != null) {
                IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("Terug"), tint = Pz.accent) }
            } else Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(title, fontSize = 26.sp, fontWeight = FontWeight.Bold, color = Pz.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (picker && onBack == null) BusinessPicker()
            }
            actions()
        }
        Column(Modifier.weight(1f).fillMaxWidth(), content = content)
    }
}

/** Zaakkiezer bovenin (alleen bij meer dan één zaak). */
@Composable
fun BusinessPicker() {
    val list = BusinessStore.businesses
    val current = BusinessStore.current ?: return
    if (list.size <= 1) return
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.clip(RoundedCornerShape(8.dp)).clickable { open = true }.padding(vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(current.name, fontWeight = FontWeight.SemiBold, color = Pz.muted, fontSize = 15.sp, maxLines = 1)
            Icon(Icons.Filled.ExpandCircleDown, L("Kies een zaak"), tint = Pz.muted, modifier = Modifier.size(16.dp))
        }
        DropdownMenu(open, onDismissRequest = { open = false }) {
            for (b in list) {
                DropdownMenuItem(
                    text = { Text(b.name) },
                    leadingIcon = { if (b.id == current.id) Icon(Icons.Filled.Check, null) else Spacer(Modifier.size(24.dp)) },
                    onClick = { open = false; BusinessStore.select(b.id) },
                )
            }
        }
    }
}


/** Eén keer om toestemming voor meldingen vragen (Android 13+), een paar seconden na het openen van de app. */
@Composable
private fun NotificationPermissionAsk() {
    val context = androidx.compose.ui.platform.LocalContext.current
    if (isPreview()) return
    val launcher = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission(),
    ) { }
    LaunchedEffect(Unit) {
        if (!app.lrvdlinden.pasrzakelijk.push.Push.isAvailable(context)) return@LaunchedEffect
        if (!app.lrvdlinden.pasrzakelijk.push.Push.needsPermission(context) || Prefs.string("push.asked") == "1") return@LaunchedEffect
        kotlinx.coroutines.delay(4000)
        Prefs.putString("push.asked", "1")
        launcher.launch(android.Manifest.permission.POST_NOTIFICATIONS)
    }
}
