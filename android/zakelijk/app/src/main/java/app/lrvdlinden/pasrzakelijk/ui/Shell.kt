package app.lrvdlinden.pasrzakelijk.ui

import android.app.Activity
import android.view.WindowManager
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import app.lrvdlinden.pasrzakelijk.core.Biometrics
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.core.Prefs
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Houdt bij of de app afgedekt is (splash of slot): dan geen uitnodigingsvenster. */
object ShellState {
    var locked by mutableStateOf(true)
}

/** Splashscreen, slot met vingerafdruk/gezicht en afdekking in het overzicht van apps om de app heen (zelfde opzet als iOS). */
@Composable
fun AppShell() {
    var showSplash by rememberSaveable { mutableStateOf(true) }
    var locked by rememberSaveable { mutableStateOf(Prefs.appLock) }
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle

    // Afdekken in het overzicht van apps zolang de vergrendeling aan staat (FLAG_SECURE).
    DisposableEffect(Prefs.appLock) {
        val window = (context as? Activity)?.window
        if (Prefs.appLock) window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE) else window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        onDispose { }
    }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP && Prefs.appLock) locked = true
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    ShellState.locked = showSplash || locked

    Box(Modifier.fillMaxSize().background(Pz.bg)) {
        if (!showSplash && !locked) RootScreen()
        AnimatedVisibility(locked && !showSplash, enter = fadeIn(), exit = fadeOut()) {
            LockScreen { locked = false }
        }
        AnimatedVisibility(showSplash, enter = fadeIn(), exit = fadeOut(tween(350))) {
            SplashScreen { showSplash = false }
        }
    }
}

/**
 * Openingsanimatie zoals in Pasr: drie kaarten komen omhoog en waaieren uit, het groene vinkje van het Pasr
 * Zakelijk-icoon springt erop, daarna verschijnt "pasr ZAKELIJK". Kort (± 1,5 s) en wacht nooit op het netwerk.
 */
@Composable
fun SplashScreen(static: Boolean = false, onFinish: () -> Unit = {}) {
    val night = Pz.night
    var cardsIn by remember { mutableStateOf(static) }
    var fanned by remember { mutableStateOf(static) }
    var badge by remember { mutableStateOf(static) }
    var wordmark by remember { mutableStateOf(static) }
    val glow = remember { Animatable(if (static) 1f else 0f) }
    val inspection = isPreview()
    LaunchedEffect(Unit) {
        if (static || inspection) { cardsIn = true; fanned = true; badge = true; wordmark = true; return@LaunchedEffect }
        cardsIn = true
        launch { glow.animateTo(1f, tween(1200, easing = FastOutSlowInEasing)) }
        delay(420); fanned = true
        delay(180); badge = true
        delay(160); wordmark = true
        delay(800); onFinish()
    }
    val cards = listOf(Triple(Pz.mint, -14f, -22f), Triple(Pz.iris, -4f, -6f), Triple(Pz.coral, 7f, 10f))
    Box(
        Modifier.fillMaxSize().background(night).semantics { contentDescription = "Pasr Zakelijk" },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.fillMaxSize().blur(20.dp).background(Brush.radialGradient(listOf(Pz.iris.copy(alpha = 0.35f * glow.value), Color.Transparent), radius = 900f)))
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(34.dp)) {
            Box(Modifier.height(170.dp).width(260.dp), contentAlignment = Alignment.Center) {
                cards.forEachIndexed { index, (color, angle, dx) ->
                    val rise by animateFloatAsState(if (cardsIn) 1f else 0f, spring(dampingRatio = 0.78f, stiffness = Spring.StiffnessLow), label = "rise$index")
                    val fan by animateFloatAsState(if (fanned) 1f else 0f, spring(dampingRatio = 0.7f, stiffness = Spring.StiffnessMediumLow), label = "fan$index")
                    SplashCard(
                        color, showsCode = index == cards.lastIndex,
                        modifier = Modifier
                            .offset(x = (dx * 1.4f * fan).dp, y = ((index * 14 - 14) + (1 - rise) * 420).dp)
                            .rotate(angle * fan)
                            .alpha(rise),
                    )
                }
                // het vinkje van het Zakelijk-icoon: de ondernemer zet de stempel
                val badgeScale by animateFloatAsState(if (badge) 1f else 0.2f, spring(dampingRatio = 0.6f), label = "badge")
                Box(
                    Modifier
                        .offset(x = 70.dp, y = 44.dp)
                        .scale(badgeScale)
                        .alpha(if (badge) 1f else 0f)
                        .size(66.dp)
                        .border(5.dp, night, CircleShape)
                        .clip(CircleShape)
                        .background(Pz.mint)
                        .padding(8.dp)
                        .border(3.dp, Color.White.copy(alpha = 0.9f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(30.dp)) }
            }
            val wm by animateFloatAsState(if (wordmark) 1f else 0f, spring(dampingRatio = 0.8f), label = "wordmark")
            Row(
                Modifier.alpha(wm).scale(0.86f + 0.14f * wm).blur(((1 - wm) * 8).dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text("pasr", style = TextStyle(brush = Pz.gradient, fontSize = 54.sp, fontWeight = FontWeight.Black, letterSpacing = (-1.5).sp))
                Text(
                    L("ZAKELIJK"), color = Pz.mint, fontSize = 15.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp,
                    modifier = Modifier.border(1.dp, Pz.mint.copy(alpha = 0.6f), CircleShape).padding(horizontal = 9.dp, vertical = 4.dp),
                )
            }
        }
    }
}

@Composable
private fun SplashCard(color: Color, showsCode: Boolean, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(16.dp)
    Box(
        modifier
            .width(150.dp).height((150 / 1.586).dp)
            .shadow(16.dp, shape, ambientColor = Color.Black.copy(alpha = 0.35f), spotColor = Color.Black.copy(alpha = 0.35f))
            .clip(shape)
            .background(Brush.linearGradient(listOf(color.copy(alpha = 0.95f), color)))
            .border(0.75.dp, Color.White.copy(alpha = 0.18f), shape),
    ) {
        Box(Modifier.padding(14.dp).width(46.dp).height(7.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.5f)))
        if (showsCode) {
            Row(Modifier.align(Alignment.BottomCenter).padding(bottom = 14.dp).height(22.dp), horizontalArrangement = Arrangement.spacedBy(2.5.dp)) {
                val widths = listOf(3f, 1.5f, 2f, 1f, 3f, 2f, 1.5f)
                repeat(15) { i -> Box(Modifier.width(widths[i % 7].dp).fillMaxHeight().background(Color.White.copy(alpha = 0.85f))) }
            }
        }
    }
}

/** Over de app zolang hij vergrendeld is (vingerafdruk, gezicht of schermvergrendeling). */
@Composable
fun LockScreen(onUnlock: () -> Unit) {
    val activity = LocalContext.current as? FragmentActivity
    var trying by remember { mutableStateOf(false) }
    fun unlock() {
        if (activity == null) return onUnlock()
        if (trying) return
        trying = true
        Biometrics.authenticate(activity, L("Ontgrendel Pasr Zakelijk"), L("Ontgrendel Pasr Zakelijk om stempels te zetten.")) { ok ->
            trying = false
            if (ok) onUnlock()
        }
    }
    LaunchedEffect(Unit) { unlock() }
    Column(
        Modifier.fillMaxSize().background(Pz.bg).safeDrawingPadding().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        ZakelijkLogo(34f)
        Spacer(Modifier.height(26.dp))
        Icon(Icons.Filled.Fingerprint, null, tint = Pz.muted, modifier = Modifier.size(48.dp))
        Spacer(Modifier.height(16.dp))
        Text(L("Pasr Zakelijk is vergrendeld"), color = Pz.muted, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
        Spacer(Modifier.weight(1f))
        BigButton(L("Ontgrendelen"), { unlock() }, Modifier.widthIn(max = 300.dp).padding(bottom = 32.dp), icon = Icons.Filled.Fingerprint, enabled = !trying)
    }
}
