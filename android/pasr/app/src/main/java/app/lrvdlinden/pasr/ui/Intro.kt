package app.lrvdlinden.pasr.ui

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.Fingerprint
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import app.lrvdlinden.pasr.data.Prefs
import kotlinx.coroutines.launch

/** App-slot met vingerafdruk of gezicht, met de schermvergrendeling (pincode, patroon) als terugval. */
object AppLock {
    private val authenticators get() = if (Build.VERSION.SDK_INT >= 30) BIOMETRIC_WEAK or DEVICE_CREDENTIAL else BIOMETRIC_WEAK

    fun isAvailable(context: android.content.Context) =
        BiometricManager.from(context).canAuthenticate(authenticators) == BiometricManager.BIOMETRIC_SUCCESS

    fun authenticate(activity: FragmentActivity, title: String, onResult: (Boolean) -> Unit) {
        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) = onResult(true)
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) = onResult(false)
        })
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setAllowedAuthenticators(authenticators)
            .apply { if (Build.VERSION.SDK_INT < 30) setNegativeButtonText("Annuleren") }
            .build()
        runCatching { prompt.authenticate(info) }.onFailure { onResult(false) }
    }
}

/** Pasr-logo: drie kaarten in een waaier, zoals het app-icoon. */
@Composable
fun PasrMark(size: androidx.compose.ui.unit.Dp, spread: Float = 1f) {
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        val w = size * 0.62f
        val h = w / Brand.CARD_ASPECT
        listOf(Triple(Brand.mint, -18f, -0.22f), Triple(Brand.iris, -8f, -0.08f), Triple(Brand.coral, 8f, 0.08f)).forEach { (c, deg, dx) ->
            Box(
                Modifier.offset(x = size * dx * spread, y = size * (if (deg < 0) 0.03f else -0.02f) * spread)
                    .rotate(deg * spread).size(w, h).clip(RoundedCornerShape(w * 0.1f))
                    .background(Brush.linearGradient(listOf(c.copy(alpha = 1f), shade(c.toHex(), -0.15f)))),
            )
        }
        // barcode op de voorste kaart
        Row(
            Modifier.offset(x = size * 0.08f * spread, y = size * 0.06f).rotate(8f * spread).width(w * 0.7f).height(h * 0.28f),
            horizontalArrangement = Arrangement.spacedBy(w * 0.025f),
        ) {
            listOf(3, 1, 2, 1, 3, 1, 1, 2, 3, 1, 2, 1).forEach { b ->
                Box(Modifier.width(w * 0.012f * b).height(h * 0.28f).background(Color.White.copy(alpha = 0.92f)))
            }
        }
    }
}

/** Splash na het systeemscherm: de kaarten waaieren uit, daarna verdwijnt hij. */
@Composable
fun SplashOverlay(onFinished: () -> Unit) {
    val spread = remember { Animatable(0f) }
    val alpha = remember { Animatable(1f) }
    LaunchedEffect(Unit) {
        spread.animateTo(1f, tween(650, easing = FastOutSlowInEasing))
        alpha.animateTo(0f, tween(320))
        onFinished()
    }
    Box(
        Modifier.fillMaxSize().alpha(alpha.value)
            .background(Brush.radialGradient(listOf(Color(0xFF2A2160), Color(0xFF0E0D1D)))),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            PasrMark(170.dp, spread.value)
            Spacer(Modifier.height(18.dp))
            Text("Pasr", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.alpha(spread.value).scale(0.9f + 0.1f * spread.value))
        }
    }
}

private data class Page(val icon: ImageVector, val title: String, val text: String)

private val pages = listOf(
    Page(Icons.Outlined.AccountBalanceWallet, "Al je pasjes op één plek",
        "Klantenkaarten, spaarpassen en cadeaukaarten van ruim 300 Nederlandse winkels, met hun echte logo en kleur."),
    Page(Icons.Outlined.QrCodeScanner, "Scannen en klaar",
        "Kies de winkel en scan de barcode met je camera, of kies een foto of screenshot van je kaart."),
    Page(Icons.Outlined.CreditCard, "Altijd bij de hand",
        "Bij de kassa tik je de kaart aan en zie je meteen de barcode, op volle helderheid. Ook in Google Wallet."),
    Page(Icons.Outlined.Verified, "Stempelkaarten van zaken",
        "Sluit je aan bij de stempelkaart van je koffiezaak of kapper. De zaak zet de stempels, jij ziet altijd de stand."),
    Page(Icons.Outlined.Lock, "Veilig en privé",
        "Kaartnummers staan versleuteld op je telefoon. Vergrendel Pasr met je vingerafdruk of gezicht. Geen reclame, geen tracking."),
)

/** Welkom: uitleg, daarna (optioneel) een account en het app-slot. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun Onboarding(onDone: () -> Unit, replay: Boolean = false) {
    val context = LocalContext.current
    val pager = rememberPagerState { pages.size + 2 }
    val scope = rememberCoroutineScope()
    var showAccount by remember { mutableStateOf(false) }
    val notifyPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }

    if (showAccount) {
        AccountScreen(onClose = { showAccount = false; scope.launch { pager.animateScrollToPage(pages.size + 1) } }, embedded = true)
        return
    }
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF17132E), Color(0xFF0A0B10))))) {
        HorizontalPager(pager, Modifier.fillMaxSize(), userScrollEnabled = true) { i ->
            Column(
                Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 28.dp).padding(bottom = 150.dp),
                verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                when {
                    i < pages.size -> {
                        val p = pages[i]
                        if (i == 0) PasrMark(150.dp) else Box(
                            Modifier.size(110.dp).clip(RoundedCornerShape(32.dp)).background(Brand.gradient),
                            contentAlignment = Alignment.Center,
                        ) { Icon(p.icon, null, tint = Color.White, modifier = Modifier.size(54.dp)) }
                        Spacer(Modifier.height(34.dp))
                        Text(p.title, color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                        Spacer(Modifier.height(14.dp))
                        Text(p.text, color = Color.White.copy(alpha = 0.75f), fontSize = 17.sp, textAlign = TextAlign.Center, lineHeight = 24.sp)
                    }
                    i == pages.size -> {
                        Icon(Icons.Outlined.Share, null, tint = Brand.mint, modifier = Modifier.size(64.dp))
                        Spacer(Modifier.height(26.dp))
                        Text("Bewaar je kaarten in een account", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                        Spacer(Modifier.height(14.dp))
                        Text("Gratis en optioneel. Je kaarten staan dan versleuteld op één plek en zijn er meteen weer op een nieuwe telefoon, ook op een iPhone.",
                            color = Color.White.copy(alpha = 0.75f), fontSize = 17.sp, textAlign = TextAlign.Center, lineHeight = 24.sp)
                    }
                    else -> {
                        Icon(Icons.Outlined.Fingerprint, null, tint = Brand.iris, modifier = Modifier.size(72.dp))
                        Spacer(Modifier.height(26.dp))
                        Text("Pasr beveiligen?", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                        Spacer(Modifier.height(14.dp))
                        Text("Dan vraagt Pasr je vingerafdruk, gezicht of pincode als je de app opent, zodat niemand anders je kaarten kan zien. Je kunt dit later altijd wijzigen in Instellingen.",
                            color = Color.White.copy(alpha = 0.75f), fontSize = 17.sp, textAlign = TextAlign.Center, lineHeight = 24.sp)
                    }
                }
            }
        }
        Column(Modifier.align(Alignment.BottomCenter).safeDrawingPadding().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                repeat(pages.size + 2) { i ->
                    Box(Modifier.size(if (pager.currentPage == i) 22.dp else 8.dp, 8.dp).clip(CircleShape)
                        .background(Color.White.copy(alpha = if (pager.currentPage == i) 0.95f else 0.3f)))
                }
            }
            Spacer(Modifier.height(20.dp))
            val page = pager.currentPage
            val primary = ButtonDefaults.buttonColors(containerColor = Brand.iris, contentColor = Color.White)
            fun finish() {
                if (!replay && Build.VERSION.SDK_INT >= 33) notifyPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                onDone()
            }
            when {
                page < pages.size -> Button({ scope.launch { pager.animateScrollToPage(page + 1) } }, Modifier.fillMaxWidth().height(54.dp), colors = primary) {
                    Text("Volgende", fontWeight = FontWeight.SemiBold)
                }
                page == pages.size -> {
                    Button({ showAccount = true }, Modifier.fillMaxWidth().height(54.dp), colors = primary) { Text("Maak een account of log in", fontWeight = FontWeight.SemiBold) }
                    TextButton({ scope.launch { pager.animateScrollToPage(page + 1) } }) { Text("Later", color = Color.White.copy(alpha = 0.8f)) }
                }
                else -> {
                    val activity = context as? FragmentActivity
                    if (activity != null && AppLock.isAvailable(context)) {
                        Button({
                            AppLock.authenticate(activity, "Bevestig om Pasr te vergrendelen") { ok -> if (ok) { Prefs.lockEnabled = true; (activity as? app.lrvdlinden.pasr.MainActivity)?.applyScreenProtection() }; finish() }
                        }, Modifier.fillMaxWidth().height(54.dp), colors = primary) { Text("Zet het slot aan", fontWeight = FontWeight.SemiBold) }
                    }
                    TextButton({ finish() }) { Text("Niet nu", color = Color.White.copy(alpha = 0.8f)) }
                }
            }
        }
    }
}

/** Dekt de app af zolang hij vergrendeld is; vraagt meteen om ontgrendelen. */
@Composable
fun LockScreen(onUnlock: () -> Unit) {
    val activity = LocalContext.current as? FragmentActivity
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(attempt) {
        if (activity == null) onUnlock() else AppLock.authenticate(activity, "Ontgrendel Pasr") { ok -> if (ok) onUnlock() }
    }
    Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(Color(0xFF2A2160), Color(0xFF0E0D1D)))), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(32.dp)) {
            PasrMark(120.dp)
            Spacer(Modifier.height(24.dp))
            Text("Pasr is vergrendeld", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(24.dp))
            Button({ attempt++ }, colors = ButtonDefaults.buttonColors(containerColor = Brand.iris)) {
                Icon(Icons.Outlined.Fingerprint, null); Spacer(Modifier.width(8.dp)); Text("Ontgrendelen")
            }
        }
    }
}

@Composable
fun BrandButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Button(onClick, modifier.fillMaxWidth().height(52.dp), enabled = enabled, shape = RoundedCornerShape(16.dp),
        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)) {
        Text(text, fontWeight = FontWeight.SemiBold)
    }
}
