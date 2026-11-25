package app.lrvdlinden.pasr.ui

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import app.lrvdlinden.pasr.Incoming
import app.lrvdlinden.pasr.data.Account
import app.lrvdlinden.pasr.data.Business
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.CardKind
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.Catalog
import app.lrvdlinden.pasr.data.DeviceRegistry
import app.lrvdlinden.pasr.data.GoogleWallet
import app.lrvdlinden.pasr.data.Prefs
import app.lrvdlinden.pasr.data.Share
import app.lrvdlinden.pasr.data.StoreTemplate
import app.lrvdlinden.pasr.data.Sync
import app.lrvdlinden.pasr.notify.Reminders
import kotlinx.coroutines.launch

sealed interface Screen {
    data object Wallet : Screen
    data class Detail(val id: String) : Screen
    /** "Laatst gebruikt", alles van één kaart. */
    data class Uses(val id: String) : Screen
    data object Add : Screen
    class Migrate : Screen {
        val candidates = mutableStateListOf<Card>()
    }
    data class Editor(val id: String? = null, val template: StoreTemplate? = null, val kind: CardKind = CardKind.LOYALTY,
                      val draft: Card? = null) : Screen
    data class StampJoin(val cardId: String, val code: String? = null, val referralToken: String? = null) : Screen
    data class Import(val card: Card) : Screen
    data object Settings : Screen
    data object Backup : Screen
    data object Welcome : Screen
    data object AccountScreen : Screen
    data object Deleted : Screen
    /** Bonnetjes: alle bonnen (met een zoekterm), één bon, en controleren of wijzigen. */
    data class Receipts(val query: String = "") : Screen
    data class ReceiptDetail(val id: String) : Screen
    data class ReceiptReview(val cardId: String?, val useId: String?, val receiptId: String? = null) : Screen
    /** Uitleg en aan/uit voor aankopen vanzelf vastleggen (betaalmeldingen). */
    data object Coupons : Screen
    data object Benefits : Screen
    data object PayCapture : Screen
}

class Nav {
    val stack = mutableStateListOf<Screen>(Screen.Wallet)
    val top get() = stack.last()
    fun push(s: Screen) { stack.add(s) }
    fun pop() { if (stack.size > 1) stack.removeAt(stack.lastIndex) }
    fun replace(s: Screen) { if (stack.size > 1) stack[stack.lastIndex] = s else stack.add(s) }
    fun home() { while (stack.size > 1) stack.removeAt(stack.lastIndex) }
}

val LocalNav = staticCompositionLocalOf { Nav() }
val LocalSnack = staticCompositionLocalOf { SnackbarHostState() }

@Composable
fun Root() {
    var appearance by remember { mutableStateOf(Prefs.appearance) }
    PasrTheme(appearance) {
        val nav = remember { Nav() }
        val snack = remember { SnackbarHostState() }
        var splash by remember { mutableStateOf(true) }
        var onboarded by remember { mutableStateOf(Prefs.onboarded) }
        val locked by Incoming.locked.collectAsState()
        val link by Incoming.link.collectAsState()
        val openCard by Incoming.cardId.collectAsState()
        val scope = rememberCoroutineScope()

        // bij openen en elke keer dat Pasr naar voren komt: winkels, stand van stempelkaarten, sync, apparaat
        LifecycleEventEffect(Lifecycle.Event.ON_START) {
            scope.launch {
                Catalog.refresh()
                app.lrvdlinden.pasr.notify.NearbyStoresAndroid.sync(appContext)
                DeviceRegistry.registerIfNeeded(appContext)
                if (Account.isSignedIn) Sync.sync()
                val before = CardStore.visible.filter { it.isBusinessStamps }.associate { it.id to it.details.stampsFull }
                for (c in Business.refreshAll()) {
                    if (!app.lrvdlinden.pasr.notify.Push.hasToken && before[c.id] == false && c.details.stampsFull) Reminders.stampsFull(appContext, c)
                    GoogleWallet.updateIfSaved(c)
                }
            }
        }
        LaunchedEffect(link) {
            val uri = link ?: return@LaunchedEffect
            Incoming.link.value = null
            handleLink(uri, nav)
        }
        // link uit een pushmelding: pas na splash, welkomst en ontgrendelen, in Custom Tabs
        val web by Incoming.web.collectAsState()
        val ctx = androidx.compose.ui.platform.LocalContext.current
        LaunchedEffect(web, splash, onboarded, locked) {
            val uri = web ?: return@LaunchedEffect
            if (splash || !onboarded || locked) return@LaunchedEffect
            Incoming.web.value = null
            Incoming.leavingOnPurpose = true
            openInApp(ctx, uri.toString())
        }
        LaunchedEffect(openCard) {
            val id = openCard ?: return@LaunchedEffect
            Incoming.cardId.value = null
            if (CardStore.get(id)?.let { it.deletedAt == null } == true) { nav.home(); nav.push(Screen.Detail(id)) }
        }
        val openReceipt by Incoming.receipt.collectAsState()
        LaunchedEffect(openReceipt) {
            val id = openReceipt ?: return@LaunchedEffect
            Incoming.receipt.value = null
            if (app.lrvdlinden.pasr.data.ReceiptStore.get(id) != null) { nav.home(); nav.push(Screen.ReceiptDetail(id)) }
        }
        val receiptShortcut by Incoming.receiptShortcut.collectAsState()
        LaunchedEffect(receiptShortcut, splash, onboarded, locked) {
            val action = receiptShortcut ?: return@LaunchedEffect
            if (splash || !onboarded || locked) return@LaunchedEffect
            Incoming.receiptShortcut.value = null
            nav.home()
            nav.push(Screen.Receipts())
            if (action == "app.lrvdlinden.pasr.SCAN_RECEIPT") ReceiptScans.launch?.invoke(null, null)
        }
        val openStore by Incoming.store.collectAsState()
        LaunchedEffect(openStore) {
            val id = openStore ?: return@LaunchedEffect
            Incoming.store.value = null
            val card = CardStore.visible.firstOrNull { it.templateID.equals(id, true) }
            val t = Catalog.template(id)
            nav.home()
            when {
                card != null -> nav.push(Screen.Detail(card.id))
                t != null -> nav.push(Screen.Editor(template = t, kind = t.kind))
                else -> nav.push(Screen.Add)
            }
        }
        // kaarten veranderd (winkels, zakelijke stempelkaarten): push-gegevens opnieuw melden
        val cardsNow by CardStore.cards.collectAsState()
        LaunchedEffect(cardsNow.map { "${it.id}|${it.storeName}|${it.deletedAt}|${it.places.hashCode()}" }) {
            app.lrvdlinden.pasr.notify.NearbyStoresAndroid.sync(appContext)
        }
        LaunchedEffect(cardsNow.map { "${it.templateID}|${it.details.memberCode}|${it.deletedAt != null}" }.toSet()) {
            kotlinx.coroutines.delay(3000)
            DeviceRegistry.registerIfNeeded(appContext)
        }

        CompositionLocalProviders(nav, snack) {
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                Box(Modifier.fillMaxSize()) {
                    when {
                        !onboarded -> Onboarding(onDone = { Prefs.onboarded = true; onboarded = true })
                        else -> Screens(nav, onAppearance = { appearance = it })
                    }
                    if (onboarded && !locked) UsePromptHost()
                    ReceiptScanHost()
                    if (locked && onboarded) LockScreen(onUnlock = { Incoming.locked.value = false })
                    if (splash) SplashOverlay(onFinished = { splash = false })
                }
            }
        }
    }
}

lateinit var appContext: android.content.Context

@Composable
private fun CompositionLocalProviders(nav: Nav, snack: SnackbarHostState, content: @Composable () -> Unit) {
    androidx.compose.runtime.CompositionLocalProvider(LocalNav provides nav, LocalSnack provides snack, content = content)
}

private fun handleLink(uri: Uri, nav: Nav) {
    Business.cardId(uri)?.let { id ->
        nav.home(); nav.push(Screen.StampJoin(id, Business.memberCode(uri), uri.getQueryParameter("ref"))); return
    }
    Share.decode(uri)?.let { card -> nav.home(); nav.push(Screen.Import(card)) }
}

@Composable
private fun Screens(nav: Nav, onAppearance: (String) -> Unit) {
    val top = nav.top
    BackHandler(enabled = nav.stack.size > 1) { nav.pop() }
    AnimatedContent(
        targetState = top,
        transitionSpec = {
            val forward = nav.stack.size > 1 && targetState == nav.top && initialState != nav.top
            if (targetState is Screen.Wallet) fadeIn() togetherWith fadeOut()
            else (slideInHorizontally { if (forward) it / 4 else -it / 4 } + fadeIn()) togetherWith
                (slideOutHorizontally { if (forward) -it / 6 else it / 6 } + fadeOut())
        },
        label = "screens",
    ) { s ->
        when (s) {
            Screen.Wallet -> WalletScreen()
            is Screen.Detail -> CardDetailScreen(s.id)
            is Screen.Uses -> RecentUsesScreen(s.id)
            Screen.Add -> AddCardScreen()
            is Screen.Migrate -> MigrateScreen(s.candidates)
            is Screen.Editor -> CardEditorScreen(s)
            is Screen.StampJoin -> StampJoinScreen(s.cardId, s.code, s.referralToken)
            is Screen.Import -> ImportScreen(s.card)
            Screen.Settings -> SettingsScreen(onAppearance)
            Screen.Backup -> BackupScreen()
            Screen.Welcome -> Onboarding(onDone = { nav.pop() }, replay = true)
            Screen.AccountScreen -> AccountScreen()
            Screen.Deleted -> DeletedScreen()
            is Screen.Receipts -> ReceiptsScreen(s.query)
            is Screen.ReceiptDetail -> ReceiptDetailScreen(s.id)
            is Screen.ReceiptReview -> ReceiptReviewScreen(s.cardId, s.useId, s.receiptId)
            Screen.Coupons -> CouponsScreen()
            Screen.Benefits -> BenefitsScreen()
            Screen.PayCapture -> PayCaptureScreen()
        }
    }
}
