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
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.OpenInNew
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
import app.lrvdlinden.pasr.data.CardKind
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.Catalog
import app.lrvdlinden.pasr.data.GoogleWallet
import app.lrvdlinden.pasr.data.PasrError
import app.lrvdlinden.pasr.data.Prefs
import app.lrvdlinden.pasr.data.Share
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CardDetailScreen(id: String) {
    val nav = LocalNav.current
    val snack = LocalSnack.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val all by CardStore.cards.collectAsState()
    val card = all.firstOrNull { it.id.equals(id, true) }
    if (card == null) { LaunchedEffect(Unit) { nav.pop() }; return }
    var revealed by remember(id) { mutableStateOf(!card.isLocked) }
    var gwAvailable by remember { mutableStateOf(false) }
    var gwBusy by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var amountDialog by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(id) {
        CardStore.upsert(card.shown(), touch = false)
        gwAvailable = GoogleWallet.isAvailable()
        if (card.isBusinessStamps) Business.refresh(card)?.let { GoogleWallet.updateIfSaved(it) }
    }
    // volle helderheid zolang de code in beeld is (scanners bij de kassa)
    DisposableEffect(Unit) {
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
                        Gap(6.dp)
                        Text("Laat de QR-code scannen bij de kassa. Alleen de zaak zet stempels.",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
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

            if (card.kind == CardKind.VOUCHER) {
                SectionHeader("Tegoed")
                Group {
                    Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(card.balance?.let { euro(it, card.currencyCode) } ?: "Onbekend", style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                        IconButton({ amountDialog = "spent" }) { Icon(Icons.Outlined.Remove, "Uitgegeven") }
                        IconButton({ amountDialog = "topup" }) { Icon(Icons.Outlined.Add, "Opgewaardeerd") }
                    }
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
                RowItem(Icons.Outlined.Share, "Delen", if (card.isBusinessStamps) "Deel de link van de zaak (niet je eigen code)" else "Via WhatsApp, mail of andere apps") {
                    val link = Share.link(card)
                    val text = if (card.isBusinessStamps) "Spaar ook stempels bij ${card.storeName} met Pasr: $link"
                        else "Mijn ${card.kind.title.lowercase()} van ${card.storeName} in Pasr: $link"
                    Incoming.leavingOnPurpose = true
                    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), "Kaart delen"))
                }
                if (card.number.isNotEmpty() && revealed) RowItem(Icons.Outlined.ContentCopy, "Nummer kopiëren") {
                    copy(context, card.number); scope.launch { snack.showSnackbar("Gekopieerd") }
                }
                RowItem(Icons.Outlined.Delete, "Verwijderen", tint = MaterialTheme.colorScheme.error) { confirmDelete = true }
            }
            Gap(40.dp)
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

    amountDialog?.let { mode ->
        var text by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { amountDialog = null },
            title = { Text(if (mode == "spent") "Uitgegeven" else "Opgewaardeerd") },
            text = {
                OutlinedTextField(text, { text = it.filter { c -> c.isDigit() || c == ',' || c == '.' } }, label = { Text("Bedrag in euro") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true)
            },
            confirmButton = {
                TextButton({
                    val v = text.replace(',', '.').toDoubleOrNull()
                    if (v != null && v > 0) {
                        val updated = if (mode == "spent") card.spent(v) else card.toppedUp(v)
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

fun copy(context: Context, text: String) {
    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Pasr", text))
}
