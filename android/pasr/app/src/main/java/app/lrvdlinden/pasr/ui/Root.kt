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
    data object Add : Screen
    data class Editor(val id: String? = null, val template: StoreTemplate? = null, val kind: CardKind = CardKind.LOYALTY,
                      val draft: Card? = null) : Screen
    data class StampJoin(val cardId: String, val code: String? = null) : Screen
    data class Import(val card: Card) : Screen
    data object Settings : Screen
    data object AccountScreen : Screen
    data object Deleted : Screen
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
                DeviceRegistry.registerIfNeeded()
                if (Account.isSignedIn) Sync.sync()
                val before = CardStore.visible.filter { it.isBusinessStamps }.associate { it.id to it.details.stampsFull }
                for (c in Business.refreshAll()) {
                    if (before[c.id] == false && c.details.stampsFull) Reminders.stampsFull(appContext, c)
                    GoogleWallet.updateIfSaved(c)
                }
            }
        }
        LaunchedEffect(link) {
            val uri = link ?: return@LaunchedEffect
            Incoming.link.value = null
            handleLink(uri, nav)
        }
        LaunchedEffect(openCard) {
            val id = openCard ?: return@LaunchedEffect
            Incoming.cardId.value = null
            if (CardStore.get(id) != null) { nav.home(); nav.push(Screen.Detail(id)) }
        }

        CompositionLocalProviders(nav, snack) {
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                Box(Modifier.fillMaxSize()) {
                    when {
                        !onboarded -> Onboarding(onDone = { Prefs.onboarded = true; onboarded = true })
                        else -> Screens(nav, onAppearance = { appearance = it })
                    }
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
        nav.home(); nav.push(Screen.StampJoin(id, Business.memberCode(uri))); return
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
            Screen.Add -> AddCardScreen()
            is Screen.Editor -> CardEditorScreen(s)
            is Screen.StampJoin -> StampJoinScreen(s.cardId, s.code)
            is Screen.Import -> ImportScreen(s.card)
            Screen.Settings -> SettingsScreen(onAppearance)
            Screen.AccountScreen -> AccountScreen()
            Screen.Deleted -> DeletedScreen()
        }
    }
}
