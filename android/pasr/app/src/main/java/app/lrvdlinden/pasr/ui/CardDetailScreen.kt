package app.lrvdlinden.pasr.ui

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.view.WindowManager
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.AddToHomeScreen
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.FragmentActivity
import app.lrvdlinden.pasr.Incoming
import app.lrvdlinden.pasr.data.Business
import app.lrvdlinden.pasr.data.Api
import app.lrvdlinden.pasr.data.Account
import org.json.JSONObject
import app.lrvdlinden.pasr.data.CardKind
import app.lrvdlinden.pasr.data.CardPlace
import app.lrvdlinden.pasr.data.UseCapture
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.Catalog
import app.lrvdlinden.pasr.data.GoogleWallet
import app.lrvdlinden.pasr.data.PasrError
import app.lrvdlinden.pasr.data.Prefs
import kotlinx.coroutines.launch

/**
 * Detail van één kaart. [inGroup]: één ticket in een groep (TicketGroupScreen.kt); de helderheid regelt dan de groep,
 * en onderin blijft ruimte voor de paginapuntjes.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CardDetailContent(id: String, inGroup: Boolean = false) {
    val nav = LocalNav.current
    val snack = LocalSnack.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val all by CardStore.cards.collectAsState()
    val card = all.firstOrNull { it.deletedAt == null && it.id.equals(id, true) }
    if (card == null) { LaunchedEffect(Unit) { nav.pop() }; return }
    val launcher = context.getSystemService(android.content.pm.ShortcutManager::class.java)
    var revealed by remember(id) { mutableStateOf(!card.isLocked) }
    var gwAvailable by remember { mutableStateOf(false) }
    var vipStatus by remember(id) { mutableStateOf<String?>(null) }
    var vipBenefit by remember(id) { mutableStateOf<String?>(null) }
    var retentionAvailable by remember(id) { mutableStateOf(false) }
    var retentionEnabled by remember(id) { mutableStateOf(false) }
    var retentionDays by remember(id) { mutableStateOf(30) }
    var gwBusy by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var amountDialog by remember { mutableStateOf<String?>(null) }
    var useAmount by remember { mutableStateOf<String?>(null) }
    val locationAsk = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions()) { r ->
        if (r.values.any { it }) scope.launch { pinHere(context, id, snack) }
    }

    // Hoe lang de barcode in beeld is (alleen als de app vooraan staat en de code zichtbaar is). Bij het sluiten vraagt
    // Pasr onderin "Gebruikt bij …?" als dat minstens 5 seconden was; even kijken telt niet meer als gebruik.
    val visible = remember(id) { longArrayOf(0L, 0L) }   // [0] opgeteld, [1] sinds (0 = niet in beeld)
    val codeShown = revealed && card.number.isNotEmpty()
    LaunchedEffect(codeShown) {
        if (codeShown && visible[1] == 0L) visible[1] = System.currentTimeMillis()
        if (!codeShown && visible[1] != 0L) { visible[0] += System.currentTimeMillis() - visible[1]; visible[1] = 0L }
    }
    androidx.lifecycle.compose.LifecycleEventEffect(androidx.lifecycle.Lifecycle.Event.ON_STOP) {
        if (visible[1] != 0L) { visible[0] += System.currentTimeMillis() - visible[1]; visible[1] = 0L }
    }
    androidx.lifecycle.compose.LifecycleEventEffect(androidx.lifecycle.Lifecycle.Event.ON_START) {
        if (codeShown && visible[1] == 0L) visible[1] = System.currentTimeMillis()
    }
    DisposableEffect(id) {
        onDispose {
            val total = visible[0] + (if (visible[1] != 0L) System.currentTimeMillis() - visible[1] else 0L)
            CardStore.get(id)?.let { UsePrompts.cardClosed(context.applicationContext, it, total) }
        }
    }

    LaunchedEffect(id) {
        UsePrompts.cardOpened()
        CardStore.upsert(card.opened(), touch = false)
        gwAvailable = GoogleWallet.isAvailable()
        if (card.isBusinessStamps) {
            Business.refresh(card)?.let { GoogleWallet.updateIfSaved(it) }
            val code = card.details.memberCode
            if (!code.isNullOrBlank() && Account.isSignedIn) runCatching {
                val state = Api.rpc("pasr_business_retention_status",
                    JSONObject().put("p_code", code)) as? JSONObject
                retentionAvailable = state?.optBoolean("available") == true
                retentionEnabled = state?.optBoolean("enabled") == true
                retentionDays = state?.optInt("days", 30) ?: 30
            }
            if (!code.isNullOrBlank()) runCatching {
                val data = Api.publicRpc("pasr_business_vip_status", JSONObject().put("p_code", code)) as? JSONObject
                vipBenefit = data?.optString("benefit")?.takeIf { it.isNotBlank() }
                vipStatus = if (data?.optBoolean("enabled") == true) {
                    val tier = data.optString("tier")
                    val count = data.optInt("visits")
                    "VIP " + tier + " · " + count + " bezoeken"
                } else null
            }
        }
    }
    // volle helderheid zolang de code in beeld is (scanners bij de kassa)
    if (!inGroup) DisposableEffect(Unit) {
        val w = (context as? Activity)?.window
        val before = w?.attributes?.screenBrightness
        if (Prefs.brightness) w?.let { it.attributes = it.attributes.apply { screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL } }
        onDispose { w?.let { it.attributes = it.attributes.apply { screenBrightness = before ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE } } }
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        snackbarHost = { SnackbarHost(snack) },
        topBar = {
            TopAppBar(
                title = { Text(card.storeName.ifBlank { card.kind.title }, maxLines = 1) },
                navigationIcon = { IconButton({ nav.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Terug") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
                actions = {
                if (revealed && card.number.isNotEmpty()) {
                    IconButton({ nav.push(Screen.ShareCard(card.id)) }) { Icon(Icons.Outlined.Share, "Delen") }
                }

                    IconButton({ CardStore.upsert(card.copy(isFavorite = !card.isFavorite)) }) {
                        Icon(if (card.isFavorite) Icons.Filled.Star else Icons.Outlined.StarBorder, "Favoriet")
                    }
                    if (!card.isBusinessStamps) IconButton({ nav.push(Screen.Editor(id = card.id)) }) { Icon(Icons.Outlined.Edit, "Wijzigen") }
                },
            )
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            CardFace(card, Modifier.fillMaxWidth())
            Gap(18.dp)
            // de code
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Color.White).padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (!revealed) {
                    Icon(Icons.Outlined.Lock, null, tint = Color.Gray, modifier = Modifier.size(40.dp))
                    Gap(8.dp)
                    Text("Deze kaart is vergrendeld", color = Color(0xFF111216), fontWeight = FontWeight.SemiBold)
                    TextButton({
                        val a = context as? FragmentActivity
                        if (a == null) revealed = true else AppLock.authenticate(a, "Toon ${card.storeName}") { ok -> if (ok) revealed = true }
                    }) { Text("Toon de code") }
                } else if (card.showsCodeAsText) {
                    Text(card.number, color = Color(0xFF111216), fontSize = 30.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace,
                        textAlign = TextAlign.Center)
                } else if (card.number.isNotEmpty()) {
                    BarcodeImage(card.number, card.format, Modifier.fillMaxWidth(if (card.format.linear) 1f else 0.7f))
                    Gap(10.dp)
                    Text(card.number, color = Color(0xFF111216), fontFamily = FontFamily.Monospace, fontSize = 17.sp,
                        modifier = Modifier.clickable { copy(context, card.number); scope.launch { snack.showSnackbar("Gekopieerd") } })
                }
                if (revealed && card.pin != null) {
                    Gap(6.dp)
                    Text("Pincode: ${card.pin}", color = Color(0xFF444654), fontFamily = FontFamily.Monospace)
                }
            }

            if (card.kind == CardKind.STAMPS) {
                SectionHeader("Stempels")
                Group {
                    Column(Modifier.padding(16.dp)) {
                        StampGrid(card.details.stampsTotalValue, card.details.stampsCountValue, hexColor(card.colorHex).let {
                            if (onCard(card.colorHex) == Color.White) it else Brand.iris
                        })
                        Gap(12.dp)
                        Text("${card.details.stampsCountValue} van ${card.details.stampsTotalValue}: ${card.details.stampsProgressText}",
                            fontWeight = FontWeight.SemiBold)
                        card.details.reward?.let { Text("Beloning: $it", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        vipStatus?.let { Text(it, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary) }
                        vipBenefit?.let { Text("Jouw VIP-voordeel: $it", color = MaterialTheme.colorScheme.primary) }
                        Gap(6.dp)
                        Text("Laat de QR-code scannen bij de kassa. Alleen de zaak zet stempels.",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    RowItem(Icons.Outlined.Share, "Nodig een vriend uit", "Bonus na de eerste geldige aankoop") {
                        scope.launch {
                            try {
                                val memberCode = card.details.memberCode ?: return@launch
                                val result = Api.rpc("pasr_business_referral_invite",
                                    JSONObject().put("p_code", memberCode)) as? JSONObject
                                val link = result?.optString("share_url").orEmpty()
                                if (link.isNotBlank()) {
                                    context.startActivity(Intent.createChooser(
                                        Intent(Intent.ACTION_SEND).apply {
                                            type = "text/plain"
                                            putExtra(Intent.EXTRA_TEXT, link)
                                        }, "Deel je vriendenuitnodiging"))
                                }
                            } catch (e: Exception) {
                                snack.showSnackbar(e.message ?: "Vriendenactie is niet beschikbaar.")
                            }
                        }
                    }
                    if (card.isBusinessStamps && Account.isSignedIn && (retentionAvailable || retentionEnabled)) {
                        RowItem(Icons.Outlined.Refresh,
                            "Terugkomherinneringen",
                            (if (retentionEnabled) "Aan" else "Uit") + " · na $retentionDays dagen") {
                            scope.launch {
                                try {
                                    val member = card.details.memberCode ?: return@launch
                                    val enabled = !retentionEnabled
                                    Api.rpc("pasr_business_retention_consent", JSONObject()
                                        .put("p_code", member).put("p_enabled", enabled))
                                    retentionEnabled = enabled
                                    snack.showSnackbar(if (enabled) "Herinneringen ingeschakeld" else "Herinneringen uitgeschakeld")
                                } catch (e: Exception) {
                                    snack.showSnackbar(e.message ?: "Kon je keuze niet opslaan.")
                                }
                            }
                        }
                    }
                    RowItem(Icons.Outlined.Refresh, "Stand verversen") {
                        scope.launch {
                            val r = Business.refresh(card)
                            r?.let { GoogleWallet.updateIfSaved(it) }
                            snack.showSnackbar(if (r != null) "Bijgewerkt" else "Geen nieuwe stempels")
                        }
                    }
                }
            }

            // Laatst gebruikt (zoals de transacties in Apple Wallet): de laatste 3 keer, met wat je uitgaf
            RecentUsesSection(card, onAll = { nav.push(Screen.Uses(card.id)) }, onAmount = { useAmount = it.id })

            if (card.kind == CardKind.VOUCHER) {
                SectionHeader("Tegoed")
                Group {
                    Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(card.balance?.let { euro(it, card.currencyCode) } ?: "Onbekend", style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                        IconButton({ amountDialog = "spent" }) { Icon(Icons.Outlined.Remove, "Uitgegeven") }
                        IconButton({ amountDialog = "topup" }) { Icon(Icons.Outlined.Add, "Opgewaardeerd") }
                    }
                    RowItem(null, "Saldo corrigeren") { amountDialog = "set" }
                    val page = card.balanceURL ?: Catalog.balancePages[card.templateID?.lowercase()]
                    if (page != null) RowItem(Icons.Outlined.OpenInNew, "Saldo checken") { Incoming.leavingOnPurpose = true; openUrl(context, page) }
                }
            }

            val info = buildList {
                card.expiresAt?.let { add("Geldig tot" to dateText(it)) }
                card.details.eventDate?.let { add("Datum" to dateText(it)) }
                card.details.venue?.let { add("Locatie" to it) }
                card.details.seat?.let { add("Plaats" to it) }
                card.details.renewsAt?.let { add("Verlengt op" to dateText(it)) }
                card.details.cost?.let { add("Kosten" to euro(it)) }
                card.note.takeIf { it.isNotBlank() }?.let { add("Notitie" to it) }
            }
            if (info.isNotEmpty()) {
                SectionHeader("Gegevens")
                Group { info.forEach { (k, v) -> RowItem(null, v, k) } }
            }
            if (card.photos.isNotEmpty()) {
                SectionHeader("Foto's")
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    card.photos.forEach { slot ->
                        val bmp = remember(card.id, slot, card.updatedAt) { CardStore.photo(card.id, slot)?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } }
                        if (bmp != null) Image(bmp.asImageBitmap(), slot, Modifier.size(96.dp).clip(RoundedCornerShape(12.dp)), contentScale = ContentScale.Crop)
                    }
                }
            }

            SectionHeader("Acties")
            Group {
                if (launcher?.isRequestPinShortcutSupported == true) {
                    RowItem(Icons.Outlined.AddToHomeScreen, "Zet op beginscherm", "Open deze kaart rechtstreeks vanuit je beginscherm") {
                        val intent = Intent(context, app.lrvdlinden.pasr.MainActivity::class.java)
                            .setAction(Intent.ACTION_VIEW)
                            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                            .putExtra("cardId", card.id)
                        val shortcut = android.content.pm.ShortcutInfo.Builder(context, "card-${card.id}")
                            .setShortLabel("Pasr-kaart")
                            .setIcon(android.graphics.drawable.Icon.createWithResource(context, app.lrvdlinden.pasr.R.mipmap.ic_launcher))
                            .setIntent(intent)
                            .build()
                        if (runCatching { launcher.requestPinShortcut(shortcut, null) }.getOrDefault(false).not()) {
                            scope.launch { snack.showSnackbar("Snelkoppeling toevoegen is niet gelukt.") }
                        }
                    }
                }
                if (gwAvailable && card.number.isNotEmpty()) {
                    RowItem(Icons.Outlined.AccountBalanceWallet, if (GoogleWallet.hasPass(card)) "Bijwerken in Google Wallet" else "Toevoegen aan Google Wallet",
                        if (gwBusy) "Even geduld…" else "Pas in Google Wallet, werkt vanzelf bij") {
                        if (gwBusy) return@RowItem
                        gwBusy = true
                        scope.launch {
                            try {
                                val url = GoogleWallet.saveLink(card)
                                Incoming.leavingOnPurpose = true
                                openUrl(context, url)
                            } catch (e: PasrError) { snack.showSnackbar(e.message ?: "Mislukt") }
                            gwBusy = false
                        }
                    }
                }
                if (revealed && card.number.isNotEmpty()) {
                    RowItem(Icons.Outlined.Share, "Delen", "Deel een kopie, tijdelijk of via Gedeelde Pasr") {
                        nav.push(Screen.ShareCard(card.id))
                    }
                }
                app.lrvdlinden.pasr.data.Birthday.perk(card)?.let { perk ->
                    RowItem(null, "Verjaardagsvoordeel", perk)
                }
                if (card.number.isNotEmpty() && revealed) RowItem(Icons.Outlined.ContentCopy, "Nummer kopiëren") {
                    copy(context, card.number); scope.launch { snack.showSnackbar("Gekopieerd") }
                }
                // eigen filiaal bewaren: dan vraagt "Alleen bij de winkel" het hier wel, en elders niet
                RowItem(Icons.Outlined.Place, "Ik sta hier", if (card.places.isEmpty()) "Bewaar dit filiaal, dan vraagt Pasr alleen hier of je de kaart gebruikte"
                    else "${card.places.size} filia${if (card.places.size == 1) "al" else "len"} bewaard; voeg deze plek toe") {
                    if (!UseCapture.hasLocation(context)) { locationAsk.launch(arrayOf(android.Manifest.permission.ACCESS_FINE_LOCATION, android.Manifest.permission.ACCESS_COARSE_LOCATION)); return@RowItem }
                    scope.launch { pinHere(context, card.id, snack) }
                }
                RowItem(Icons.Outlined.Delete, "Verwijderen", tint = MaterialTheme.colorScheme.error) { confirmDelete = true }
            }
            Gap(if (inGroup) 96.dp else 40.dp)
        }
    }

    if (confirmDelete) AlertDialog(
        onDismissRequest = { confirmDelete = false },
        title = { Text("Kaart verwijderen?") },
        text = { Text("De kaart gaat naar Recent verwijderd en is daar 30 dagen terug te zetten.") },
        confirmButton = {
            TextButton({
                confirmDelete = false
                scope.launch { GoogleWallet.removeIfSaved(card) }
                CardStore.delete(card.id)
                nav.pop()
            }) { Text("Verwijderen", color = MaterialTheme.colorScheme.error) }
        },
        dismissButton = { TextButton({ confirmDelete = false }) { Text("Annuleren") } },
    )

    useAmount?.let { useId -> UseAmountDialog(card, useId, offersReceipt = true) { useAmount = null } }

    amountDialog?.let { mode ->
        var text by remember(mode) { mutableStateOf(if (mode == "set") card.balance?.toString().orEmpty() else "") }
        AlertDialog(
            onDismissRequest = { amountDialog = null },
            title = { Text(when (mode) { "spent" -> "Uitgegeven"; "set" -> "Saldo corrigeren"; else -> "Opgewaardeerd" }) },
            text = {
                OutlinedTextField(text, { text = it.filter { c -> c.isDigit() || c == ',' || c == '.' } }, label = { Text("Bedrag in euro") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true)
            },
            confirmButton = {
                TextButton({
                    val v = text.replace(',', '.').toDoubleOrNull()
                    if (v != null && v.isFinite() && (v > 0 || (mode == "set" && v == 0.0))) {
                        val updated = when (mode) { "spent" -> card.spent(v); "set" -> card.copy(balance = v, history = app.lrvdlinden.pasr.data.Card.trimHistory(listOf(app.lrvdlinden.pasr.data.CardEvent(kind = "set", balance = v)) + card.history)); else -> card.toppedUp(v) }
                        CardStore.upsert(updated)
                        scope.launch { GoogleWallet.updateIfSaved(updated) }
                    }
                    amountDialog = null
                }) { Text("Bewaar") }
            },
            dismissButton = { TextButton({ amountDialog = null }) { Text("Annuleren") } },
        )
    }
}

/** "Ik sta hier": deze plek als filiaal van de kaart bewaren (zoals op iPhone). */
private suspend fun pinHere(context: Context, id: String, snack: androidx.compose.material3.SnackbarHostState) {
    val loc = UseCapture.currentLocation(context)
    val card = CardStore.get(id) ?: return
    when {
        loc == null -> snack.showSnackbar("Je plek is nu niet bekend. Probeer het buiten of bij een raam.")
        !UseCapture.isNew(card, loc) -> snack.showSnackbar("Deze plek is al bewaard")
        card.places.size >= 10 -> snack.showSnackbar("Je kunt hoogstens 10 filialen bewaren")
        else -> {
            CardStore.upsert(card.copy(places = card.places + CardPlace(name = card.storeName, latitude = loc.latitude, longitude = loc.longitude)))
            snack.showSnackbar("Filiaal bewaard")
        }
    }
}

fun copy(context: Context, text: String) {
    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Pasr", text))
}
