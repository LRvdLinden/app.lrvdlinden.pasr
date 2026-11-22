package app.lrvdlinden.pasr.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Rect
import android.graphics.pdf.PdfDocument
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.DocumentScanner
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.PictureAsPdf
import androidx.compose.material.icons.outlined.Receipt
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import app.lrvdlinden.pasr.Incoming
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.Receipt
import app.lrvdlinden.pasr.data.ReceiptParser
import app.lrvdlinden.pasr.data.ReceiptStore
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale
import kotlin.coroutines.resume

/** Gescande pagina's tussen de scanner en het controleren (alleen in het geheugen). */
object ReceiptDraft {
    var pages: List<ByteArray> = emptyList()
    var read: ReceiptParser.Result? = null
}

fun Context.findActivity(): Activity? {
    var c: Context? = this
    while (c is ContextWrapper) { if (c is Activity) return c; c = c.baseContext }
    return null
}

/**
 * Bon scannen met de ML Kit-documentscanner (recht trekken, bijsnijden, tot 4 pagina's); zonder Google Play-services
 * een foto kiezen. Daarna leest ML Kit-tekstherkenning (in de app, geen server) het totaal en de datum en opent
 * "Controleer de bon".
 */
object ReceiptScans {
    /** Gezet door ReceiptScanHost (één keer, in Root), zodat de scanner ook werkt vanuit een venster dat sluit. */
    var launch: ((String?, String?) -> Unit)? = null
}

/** Knop "Bon scannen" voor deze kaart en dit moment (of los). */
fun rememberReceiptScan(cardId: String?, useId: String?): () -> Unit = { ReceiptScans.launch?.invoke(cardId, useId) }

@Composable
fun ReceiptScanHost() {
    val context = LocalContext.current
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    var target by remember { mutableStateOf<Pair<String?, String?>>(null to null) }
    fun handle(uris: List<Uri>) {
        val (cardId, useId) = target
        if (uris.isEmpty()) return
        scope.launch {
            val pages = withContext(Dispatchers.IO) {
                uris.take(Receipt.MAX_PAGES).mapNotNull { u ->
                    runCatching { context.contentResolver.openInputStream(u)?.use { it.readBytes() } }.getOrNull()
                        ?.let { ReceiptStore.decode(it, 2000) }?.let { ReceiptStore.jpeg(it) }
                }
            }
            if (pages.isEmpty()) return@launch
            ReceiptDraft.pages = pages
            ReceiptDraft.read = null
            nav.push(Screen.ReceiptReview(cardId = cardId, useId = useId))
            ReceiptDraft.read = readText(pages)
        }
    }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(Receipt.MAX_PAGES)) { handle(it) }
    val scan = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { res ->
        if (res.resultCode == Activity.RESULT_OK) {
            GmsDocumentScanningResult.fromActivityResultIntent(res.data)?.pages?.map { it.imageUri }?.let { handle(it) }
        }
    }
    val start: (String?, String?) -> Unit = { cardId, useId ->
        target = cardId to useId
        Incoming.leavingOnPurpose = true
        val activity = context.findActivity()
        val fallback = { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
        if (activity == null) fallback() else {
            val options = GmsDocumentScannerOptions.Builder()
                .setGalleryImportAllowed(true)
                .setPageLimit(Receipt.MAX_PAGES)
                .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
                .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
                .build()
            GmsDocumentScanning.getClient(options).getStartScanIntent(activity)
                .addOnSuccessListener { scan.launch(IntentSenderRequest.Builder(it).build()) }
                .addOnFailureListener { fallback() }
        }
    }
    androidx.compose.runtime.DisposableEffect(Unit) {
        ReceiptScans.launch = start
        onDispose { if (ReceiptScans.launch === start) ReceiptScans.launch = null }
    }
}

/** Tekst van de pagina's (regels op dezelfde hoogte samengevoegd) → totaal en datum. */
suspend fun readText(pages: List<ByteArray>): ReceiptParser.Result {
    val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    val lines = mutableListOf<String>()
    for (bytes in pages) {
        val bmp = withContext(Dispatchers.IO) { ReceiptStore.decode(bytes, 2000) } ?: continue
        val text = suspendCancellableCoroutine { cont ->
            recognizer.process(InputImage.fromBitmap(bmp, 0))
                .addOnSuccessListener { cont.resume(it) }
                .addOnFailureListener { cont.resume(null) }
        } ?: continue
        val rows = mutableListOf<Pair<Rect, MutableList<Pair<Int, String>>>>()
        text.textBlocks.flatMap { it.lines }.sortedBy { it.boundingBox?.centerY() ?: 0 }.forEach { l ->
            val box = l.boundingBox ?: return@forEach
            val row = rows.firstOrNull { kotlin.math.abs(it.first.centerY() - box.centerY()) < maxOf(it.first.height(), box.height()) * 0.6 }
            if (row != null) row.second += box.left to l.text else rows += Rect(box) to mutableListOf(box.left to l.text)
        }
        lines += rows.map { r -> r.second.sortedBy { it.first }.joinToString(" ") { it.second } }
    }
    recognizer.close()
    return ReceiptParser.parse(lines)
}

/** Controleer de bon: winkel, totaal, datum, wat je kocht en garantie. Ook om een bewaarde bon te wijzigen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceiptReviewScreen(cardId: String?, useId: String?, receiptId: String? = null) {
    val nav = LocalNav.current
    val cards by CardStore.cards.collectAsState()
    val existing = receiptId?.let { ReceiptStore.get(it) }
    val card = cards.firstOrNull { it.id == (cardId ?: existing?.cardID) }
    val pages = remember { if (existing == null) ReceiptDraft.pages else emptyList() }
    val bitmaps = remember(pages) { pages.mapNotNull { ReceiptStore.decode(it, 600) } }
    val useDate = card?.history?.firstOrNull { it.id == useId }?.date
    var store by remember { mutableStateOf(existing?.storeName ?: card?.storeName ?: "") }
    var chosenCard by remember { mutableStateOf(existing?.cardID ?: cardId) }
    var totalText by remember { mutableStateOf(existing?.total?.let { String.format(Locale("nl", "NL"), "%.2f", it) } ?: "") }
    var date by remember { mutableStateOf(existing?.date ?: useDate ?: System.currentTimeMillis()) }
    var title by remember { mutableStateOf(existing?.title ?: "") }
    var hasWarranty by remember { mutableStateOf(existing?.warrantyUntil != null) }
    var warranty by remember { mutableStateOf(existing?.warrantyUntil ?: Receipt.defaultWarranty(date)) }
    var picking by remember { mutableStateOf<String?>(null) }
    var reading by remember { mutableStateOf(existing == null && ReceiptDraft.read == null) }
    var cardMenu by remember { mutableStateOf(false) }

    // de tekstherkenning loopt nog even door nadat dit scherm opent
    LaunchedEffect(Unit) {
        if (existing != null) return@LaunchedEffect
        repeat(60) {
            ReceiptDraft.read?.let { r ->
                if (totalText.isBlank()) r.total?.let { totalText = String.format(Locale("nl", "NL"), "%.2f", it) }
                if (r.date != null && (useDate == null || kotlin.math.abs(r.date - useDate) > 2 * 86_400_000L)) date = r.date
                if (!hasWarranty) warranty = Receipt.defaultWarranty(date)
                reading = false
                return@LaunchedEffect
            }
            kotlinx.coroutines.delay(250)
        }
        reading = false
    }
    val total = totalText.takeIf { it.isNotBlank() }?.let { ReceiptParser.parseAmount(it) }

    SimpleScaffold(if (existing == null) "Bonnetje" else "Bonnetje wijzigen") {
        if (bitmaps.isNotEmpty()) {
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                bitmaps.forEach { b ->
                    Image(b.asImageBitmap(), "Gescande bon", Modifier.height(170.dp).clip(RoundedCornerShape(10.dp)), contentScale = ContentScale.Fit)
                }
            }
        }
        if (reading) Text("Totaal en datum lezen…", Modifier.padding(top = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        SectionHeader("Controleer de bon")
        if (card == null && existing == null) {
            Box {
                RowItem(Icons.Outlined.Receipt, cards.firstOrNull { it.id == chosenCard }?.storeName ?: "Geen kaart", "Kaart") { cardMenu = true }
                androidx.compose.material3.DropdownMenu(cardMenu, { cardMenu = false }) {
                    androidx.compose.material3.DropdownMenuItem({ Text("Geen kaart") }, { chosenCard = null; cardMenu = false })
                    CardStore.visible.sortedBy { it.storeName.lowercase() }.forEach { c ->
                        androidx.compose.material3.DropdownMenuItem({ Text(c.storeName) }, { chosenCard = c.id; store = c.storeName; cardMenu = false })
                    }
                }
            }
        }
        Field("Winkel", store) { store = it }
        OutlinedTextField(totalText, { totalText = it.filter { c -> c.isDigit() || c == ',' || c == '.' } }, Modifier.fillMaxWidth().padding(vertical = 4.dp),
            label = { Text("Totaal") }, prefix = { Text("€ ") }, singleLine = true, shape = RoundedCornerShape(14.dp),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), isError = totalText.isNotBlank() && total == null)
        RowItem(Icons.Outlined.CalendarMonth, dateText(date), "Datum op de bon") { picking = "date" }
        Field("Wat kocht je? (optioneel)", title) { title = it }
        if (pages.isNotEmpty()) Text("Pasr las het totaal en de datum op je telefoon. Klopt iets niet, pas het dan aan.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        SectionHeader("Garantie")
        Group {
            RowItem(Icons.Outlined.VerifiedUser, "Garantie bijhouden", if (hasWarranty) "Tot ${dateText(warranty)}" else "Herinnering een maand van tevoren",
                trailing = { Switch(hasWarranty, { hasWarranty = it }) }) { hasWarranty = !hasWarranty }
            if (hasWarranty) {
                RowItem(Icons.Outlined.CalendarMonth, dateText(warranty), "Garantie tot") { picking = "warranty" }
                Row(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(1, 2, 3, 5).forEach { y ->
                        AssistChip({ warranty = java.util.Calendar.getInstance().apply { timeInMillis = date; add(java.util.Calendar.YEAR, y) }.timeInMillis },
                            { Text("$y jaar") })
                    }
                }
            }
        }
        Text("De bon blijft versleuteld op je telefoon, net als de foto's van een kaart. Hij gaat niet via je Pasr-account.",
            Modifier.padding(top = 8.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Gap(16.dp)
        BrandButton("Bewaar", Modifier.fillMaxWidth().height(52.dp), enabled = store.isNotBlank() && (totalText.isBlank() || total != null)) {
            val r = (existing ?: Receipt(cardID = chosenCard, useID = useId)).copy(
                cardID = existing?.cardID ?: chosenCard, storeName = store.trim(), date = date, total = total,
                currencyCode = card?.currencyCode, title = title.trim(), warrantyUntil = if (hasWarranty) warranty else null,
            )
            ReceiptStore.save(r, if (existing == null) pages else null)
            if (existing == null && useId != null) card?.let { c -> CardStore.upsert(c.updatingUse(useId) { it.copy(receiptID = r.id) }) }
            ReceiptDraft.pages = emptyList()
            nav.pop()
        }
        Gap(40.dp)
    }

    picking?.let { which ->
        val state = rememberDatePickerState(initialSelectedDateMillis = if (which == "date") date else warranty)
        DatePickerDialog(
            onDismissRequest = { picking = null },
            confirmButton = {
                TextButton({
                    state.selectedDateMillis?.let { v ->
                        if (which == "date") { date = v; if (!hasWarranty) warranty = Receipt.defaultWarranty(v) } else warranty = v
                    }
                    picking = null
                }) { Text("Kies") }
            },
            dismissButton = { TextButton({ picking = null }) { Text("Annuleren") } },
        ) { DatePicker(state) }
    }
}

/** Alle bonnetjes van alle kaarten, nieuwste eerst; zoeken op winkel, bedrag of datum; "Garantie loopt nog". */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceiptsScreen(initialQuery: String = "") {
    val nav = LocalNav.current
    val receipts by ReceiptStore.receipts.collectAsState()
    val cards by CardStore.cards.collectAsState()
    var query by remember { mutableStateOf(initialQuery) }
    var onlyWarranty by remember { mutableStateOf(false) }
    var cardFilter by remember { mutableStateOf<String?>(null) }
    val scan = rememberReceiptScan(cardFilter, null)
    val visible = receipts.filter { (!onlyWarranty || it.warrantyActive) && (cardFilter == null || it.cardID == cardFilter) && it.matches(query) }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Bonnetjes", fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton({ nav.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Terug") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(onClick = scan, containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary, icon = { Icon(Icons.Outlined.DocumentScanner, null) }, text = { Text("Bon scannen") })
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth(), placeholder = { Text("Winkel, bedrag of datum") },
                leadingIcon = { Icon(Icons.Outlined.Search, null) }, singleLine = true, shape = RoundedCornerShape(16.dp))
            Row(Modifier.fillMaxWidth().padding(top = 8.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(!onlyWarranty && cardFilter == null, { onlyWarranty = false; cardFilter = null }, { Text("Alles") })
                FilterChip(onlyWarranty, { onlyWarranty = !onlyWarranty }, { Text("Garantie loopt nog") },
                    leadingIcon = { Icon(Icons.Outlined.VerifiedUser, null, Modifier.size(18.dp)) })
                cards.filter { c -> c.deletedAt == null && receipts.any { it.cardID == c.id } }.sortedBy { it.storeName.lowercase() }.forEach { c ->
                    FilterChip(cardFilter == c.id, { cardFilter = if (cardFilter == c.id) null else c.id }, { Text(c.storeName) })
                }
            }
            if (visible.isEmpty()) {
                Column(Modifier.fillMaxWidth().padding(vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Outlined.Receipt, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(40.dp))
                    Gap(10.dp)
                    Text(if (receipts.isEmpty()) "Nog geen bonnetjes" else "Geen bonnetjes gevonden", fontWeight = FontWeight.Bold)
                    Text(if (receipts.isEmpty()) "Scan de kassabon van een aankoop, bij een kaart of los. Met Garantie tot krijg je een herinnering voordat de garantie afloopt."
                         else "Zoek op winkel, bedrag (12,50) of datum (12 november).",
                        color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center, style = MaterialTheme.typography.bodySmall)
                }
            }
            visible.groupBy { UseFormat.group(it.date) }.forEach { (title, items) ->
                Text(title.uppercase(), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 4.dp, top = 20.dp, bottom = 6.dp).semantics { heading(); contentDescription = title })
                UsesPanel {
                    items.forEachIndexed { i, r ->
                        ReceiptRow(r) { nav.push(Screen.ReceiptDetail(r.id)) }
                        if (i < items.size - 1) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    }
                }
            }
            Gap(100.dp)
        }
    }
}

@Composable
fun ReceiptThumb(r: Receipt, size: Int = 42) {
    val bmp = remember(r.id, r.updatedAt) { ReceiptStore.pageBitmap(r.id, 0, 200) }
    Box(Modifier.size(size.dp).clip(RoundedCornerShape((size * 0.22f).dp)).background(Color.White)
        .border(0.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f), RoundedCornerShape((size * 0.22f).dp)),
        contentAlignment = Alignment.Center) {
        if (bmp != null) Image(bmp.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        else Icon(Icons.Outlined.Receipt, null, tint = Color.Gray)
    }
}

@Composable
fun ReceiptRow(r: Receipt, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        ReceiptThumb(r)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(if (r.title.isBlank()) r.storeName else "${r.storeName} · ${r.title}", fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val w = r.warrantyUntil?.let { if (r.warrantyActive) " · garantie tot ${dateText(it)}" else " · garantie verlopen" } ?: ""
            Text(dateText(r.date) + w, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        }
        r.total?.let { Text(euro(it, r.currencyCode), fontWeight = FontWeight.SemiBold) }
    }
}

/** Eén bon: groot met knijpen om te zoomen, delen als PDF of afbeelding, wijzigen en verwijderen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceiptDetailScreen(id: String) {
    val nav = LocalNav.current
    val context = LocalContext.current
    val receipts by ReceiptStore.receipts.collectAsState()
    val r = receipts.firstOrNull { it.id == id }
    if (r == null) { LaunchedEffect(Unit) { nav.pop() }; return }
    var confirmDelete by remember { mutableStateOf(false) }
    val pager = rememberPagerState { r.pages.coerceAtLeast(1) }
    Scaffold(
        containerColor = Color.Black,
        topBar = {
            TopAppBar(
                title = { Text(r.storeName, maxLines = 1) },
                navigationIcon = { IconButton({ nav.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Terug") } },
                actions = {
                    IconButton({ ReceiptShare.share(context, r, pdf = true) }) { Icon(Icons.Outlined.PictureAsPdf, "Deel als PDF") }
                    IconButton({ ReceiptShare.share(context, r, pdf = false) }) { Icon(Icons.Outlined.Image, "Deel als afbeelding") }
                    IconButton({ nav.push(Screen.ReceiptReview(cardId = r.cardID, useId = r.useID, receiptId = r.id)) }) { Icon(Icons.Outlined.Edit, "Wijzig") }
                    IconButton({ confirmDelete = true }) { Icon(Icons.Outlined.Delete, "Verwijder") }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize()) {
            HorizontalPager(pager, Modifier.weight(1f).fillMaxWidth()) { page ->
                val bmp = remember(r.id, page, r.updatedAt) { ReceiptStore.pageBitmap(r.id, page) }
                if (bmp != null) ZoomableBitmap(bmp, "Bon, pagina ${page + 1} van ${r.pages}")
            }
            Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer).padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(r.title.ifBlank { r.storeName }, fontWeight = FontWeight.Bold)
                        Text(dateText(r.date), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    r.total?.let { Text(euro(it, r.currencyCode), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold) }
                }
                r.warrantyUntil?.let {
                    Text(if (r.warrantyActive) "Garantie tot ${dateText(it)}" else "Garantie verlopen op ${dateText(it)}",
                        color = if (r.warrantyActive) Brand.mint else MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(top = 6.dp))
                }
            }
        }
    }
    if (confirmDelete) AlertDialog(
        onDismissRequest = { confirmDelete = false },
        title = { Text("Dit bonnetje verwijderen?") },
        text = { Text("De bon en de garantieherinnering verdwijnen van dit toestel.") },
        confirmButton = {
            TextButton({
                r.cardID?.let { cid -> CardStore.get(cid)?.let { c ->
                    r.useID?.let { uid -> CardStore.upsert(c.updatingUse(uid) { e -> if (e.receiptID == r.id) e.copy(receiptID = null) else e }) }
                } }
                ReceiptStore.delete(r.id)
                confirmDelete = false
                nav.pop()
            }) { Text("Verwijder", color = MaterialTheme.colorScheme.error) }
        },
        dismissButton = { TextButton({ confirmDelete = false }) { Text("Annuleren") } },
    )
}

@Composable
private fun ZoomableBitmap(bmp: Bitmap, description: String) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    Box(Modifier.fillMaxSize().clip(RoundedCornerShape(0.dp))
        .pointerInput(Unit) {
            detectTransformGestures { _, pan, zoom, _ ->
                scale = (scale * zoom).coerceIn(1f, 6f)
                offset = if (scale == 1f) Offset.Zero else offset + pan
            }
        }
        .pointerInput(Unit) { detectTapGestures(onDoubleTap = { scale = if (scale > 1f) 1f else 2.5f; if (scale == 1f) offset = Offset.Zero }) },
        contentAlignment = Alignment.Center) {
        Image(bmp.asImageBitmap(), description, Modifier.fillMaxSize().graphicsLayer {
            scaleX = scale; scaleY = scale; translationX = offset.x; translationY = offset.y
        }, contentScale = ContentScale.Fit)
    }
}

/** Een bon delen als PDF (alle pagina's) of als afbeeldingen, via een tijdelijk bestand (FileProvider). */
object ReceiptShare {
    fun share(context: Context, r: Receipt, pdf: Boolean) {
        val dir = File(context.cacheDir, "shared").apply { mkdirs(); listFiles()?.forEach { it.delete() } }
        val base = "Bon ${r.storeName} ${java.text.SimpleDateFormat("yyyy-MM-dd", Locale.US).format(r.date)}".replace(Regex("[/\\\\:?%*|\"<>]"), "")
        val uris = mutableListOf<Uri>()
        val authority = "${context.packageName}.files"
        if (pdf) {
            val doc = PdfDocument()
            for (i in 0 until r.pages) {
                val bmp = ReceiptStore.pageBitmap(r.id, i) ?: continue
                val width = 595
                val height = (width * bmp.height / bmp.width.toFloat()).toInt().coerceAtLeast(200)
                val page = doc.startPage(PdfDocument.PageInfo.Builder(width, height, i + 1).create())
                page.canvas.drawBitmap(bmp, null, Rect(0, 0, width, height), null)
                doc.finishPage(page)
            }
            val f = File(dir, "$base.pdf")
            f.outputStream().use { doc.writeTo(it) }
            doc.close()
            uris += FileProvider.getUriForFile(context, authority, f)
        } else {
            for (i in 0 until r.pages) {
                val bytes = ReceiptStore.pageBytes(r.id, i) ?: continue
                val f = File(dir, if (r.pages > 1) "$base ${i + 1}.jpg" else "$base.jpg")
                f.writeBytes(bytes)
                uris += FileProvider.getUriForFile(context, authority, f)
            }
        }
        if (uris.isEmpty()) return
        val send = if (uris.size == 1) Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
            else Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
        send.setType(if (pdf) "application/pdf" else "image/jpeg").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        Incoming.leavingOnPurpose = true
        context.startActivity(Intent.createChooser(send, "Bon delen"))
    }
}
