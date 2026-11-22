package app.lrvdlinden.pasr.ui

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AddPhotoAlternate
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasr.Incoming
import app.lrvdlinden.pasr.data.BarcodeFormat
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.CardKind
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.Catalog
import app.lrvdlinden.pasr.data.GoogleWallet
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CardEditorScreen(s: Screen.Editor) {
    val nav = LocalNav.current
    val snack = LocalSnack.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val existing = s.id?.let { CardStore.get(it) }
    val initial = remember(s) {
        existing ?: s.draft?.let { d -> d.copy(kindRaw = if (d.kindRaw.isNotEmpty()) d.kindRaw else s.kind.raw) } ?: s.template?.let { t ->
            Card(storeName = t.name, templateID = t.id, colorHex = t.cardHex, formatRaw = t.format.raw, website = t.domain, kindRaw = t.kind.raw,
                currencyCode = if (t.kind == CardKind.VOUCHER) "EUR" else null)
        } ?: Card(kindRaw = s.kind.raw, colorHex = Brand.palette.first())
    }
    var card by remember(s) { mutableStateOf(initial) }
    var scanning by remember { mutableStateOf(false) }
    var kindMenu by remember { mutableStateOf(false) }
    var formatMenu by remember { mutableStateOf(false) }
    var dateField by remember { mutableStateOf<String?>(null) }
    var balanceText by remember { mutableStateOf(initial.balance?.let { "%.2f".format(it).replace('.', ',') } ?: "") }
    var costText by remember { mutableStateOf(initial.details.cost?.let { "%.2f".format(it).replace('.', ',') } ?: "") }
    val pendingPhotos = remember { mutableStateOf(mapOf<String, ByteArray?>()) }
    var photoSlot by remember { mutableStateOf("front") }
    val template = Catalog.template(card.templateID)

    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) {
            when (photoSlot) {
                "cover" -> loadJpeg(context, uri, 1000, 80)?.let { card = card.copy(cover = android.util.Base64.encodeToString(it, android.util.Base64.NO_WRAP)) }
                "logo" -> loadPngBase64(context, uri)?.let { card = card.copy(logo = it, logoFromWebsite = false) }
                else -> loadJpeg(context, uri)?.let { pendingPhotos.value = pendingPhotos.value + (photoSlot to it) }
            }
        }
    }
    fun pick(slot: String) {
        photoSlot = slot
        Incoming.leavingOnPurpose = true
        photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
    }

    fun save() {
        val name = card.storeName.trim()
        if (name.isEmpty()) { scope.launch { snack.showSnackbar("Vul de naam van de winkel in.") }; return }
        if (card.number.isBlank() && card.kind != CardKind.STAMPS && card.kind != CardKind.TICKET) {
            scope.launch { snack.showSnackbar("Vul de ${card.kind.codeLabel.lowercase()} in of scan hem.") }; return
        }
        val bal = balanceText.replace(',', '.').toDoubleOrNull()
        val cost = costText.replace(',', '.').toDoubleOrNull()
        var c = card.copy(storeName = name, number = card.number.trim(), balance = if (card.kind == CardKind.VOUCHER) bal else card.balance,
            details = card.details.copy(cost = if (card.kind == CardKind.SUBSCRIPTION) cost else card.details.cost))
        if (c.kind == CardKind.VOUCHER && existing?.balance != c.balance && c.balance != null) {
            c = c.copy(history = Card.trimHistory(listOf(app.lrvdlinden.pasr.data.CardEvent(kind = "set", balance = c.balance)) + c.history))
        }
        CardStore.upsert(c)
        pendingPhotos.value.forEach { (slot, data) -> CardStore.setPhoto(c.id, slot, data) }
        scope.launch { GoogleWallet.updateIfSaved(CardStore.get(c.id) ?: c) }
        if (existing == null) nav.replace(Screen.Detail(c.id)) else nav.pop()
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        snackbarHost = { SnackbarHost(snack) },
        topBar = {
            TopAppBar(
                title = { Text(if (existing == null) "Nieuwe ${card.kind.title.lowercase()}" else "Wijzigen") },
                navigationIcon = { IconButton({ nav.pop() }) { Icon(Icons.Outlined.Close, "Annuleren") } },
                actions = { TextButton(::save) { Text("Bewaar", fontWeight = FontWeight.SemiBold) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            CardFace(card.copy(storeName = card.storeName.ifBlank { "Nieuwe kaart" }), Modifier.fillMaxWidth(0.8f).align(Alignment.CenterHorizontally))
            SectionHeader("Kaart")
            Box {
                RowItem(null, card.kind.title, "Soort", trailing = { Text("Wijzig", color = MaterialTheme.colorScheme.primary) }) { kindMenu = true }
                DropdownMenu(kindMenu, { kindMenu = false }) {
                    CardKind.choosable(card.kind).forEach { k -> DropdownMenuItem({ Text(k.title) }, { card = card.copy(kindRaw = k.raw); kindMenu = false }) }
                }
            }
            Field("Naam van de winkel", card.storeName) { card = card.copy(storeName = it) }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Field(card.kind.codeLabel, card.number, Modifier.weight(1f)) {
                    card = card.copy(number = it, formatRaw = if (existing == null && template == null && card.kind != CardKind.CODE) BarcodeFormat.guess(it).raw else card.formatRaw)
                }
                IconButton({ scanning = true }) { Icon(Icons.Outlined.QrCodeScanner, "Scannen", tint = MaterialTheme.colorScheme.primary) }
            }
            if (!card.showsCodeAsText) Box {
                RowItem(null, card.format.title, "Soort barcode", trailing = { Text("Wijzig", color = MaterialTheme.colorScheme.primary) }) { formatMenu = true }
                DropdownMenu(formatMenu, { formatMenu = false }) {
                    BarcodeFormat.entries.forEach { f -> DropdownMenuItem({ Text(f.title) }, { card = card.copy(formatRaw = f.raw); formatMenu = false }) }
                }
            }
            if (card.kind == CardKind.CODE) Toggle("Toon als barcode", card.details.codeAsBarcode == true) {
                card = card.copy(details = card.details.copy(codeAsBarcode = it))
            }

            when (card.kind) {
                CardKind.VOUCHER -> {
                    SectionHeader("Cadeaukaart")
                    Field("Tegoed (euro)", balanceText, keyboard = KeyboardType.Decimal) { balanceText = it.filter { c -> c.isDigit() || c == ',' || c == '.' } }
                    Field("Pincode (optioneel)", card.pin ?: "", keyboard = KeyboardType.Number) { card = card.copy(pin = it.ifBlank { null }) }
                    DateRow("Geldig tot", card.expiresAt) { dateField = "expires" }
                }
                CardKind.CODE -> { SectionHeader("Kortingscode"); DateRow("Geldig tot", card.expiresAt) { dateField = "expires" } }
                CardKind.TICKET -> {
                    SectionHeader("Ticket")
                    DateRow("Datum", card.details.eventDate) { dateField = "event" }
                    Field("Locatie", card.details.venue ?: "") { card = card.copy(details = card.details.copy(venue = it.ifBlank { null })) }
                    Field("Plaats of rij", card.details.seat ?: "") { card = card.copy(details = card.details.copy(seat = it.ifBlank { null })) }
                }
                CardKind.SUBSCRIPTION -> {
                    SectionHeader("Abonnement")
                    DateRow("Verlengt op", card.details.renewsAt) { dateField = "renews" }
                    Field("Kosten (euro)", costText, keyboard = KeyboardType.Decimal) { costText = it.filter { c -> c.isDigit() || c == ',' || c == '.' } }
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("week" to "Week", "month" to "Maand", "quarter" to "Kwartaal", "year" to "Jaar").forEach { (k, t) ->
                            androidx.compose.material3.FilterChip((card.details.period ?: "month") == k, { card = card.copy(details = card.details.copy(period = k)) }, { Text(t) })
                        }
                    }
                }
                else -> {}
            }

            SectionHeader("Kleur")
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                (listOfNotNull(template?.cardHex) + Brand.palette).distinct().forEach { hex ->
                    Box(Modifier.size(38.dp).clip(CircleShape).background(hexColor(hex))
                        .border(if (hex.equals(card.colorHex, true)) 3.dp else 0.dp, MaterialTheme.colorScheme.onBackground, CircleShape)
                        .clickable { card = card.copy(colorHex = hex) })
                }
            }

            SectionHeader("Logo en foto's")
            Group {
                RowItem(Icons.Outlined.Image, if (card.logo != null) "Ander logo kiezen" else "Eigen logo kiezen", "Uit je foto's") { pick("logo") }
                if (card.logo != null) RowItem(Icons.Outlined.Close, "Eigen logo weghalen") { card = card.copy(logo = null) }
                RowItem(Icons.Outlined.AddPhotoAlternate, if (card.cover != null) "Andere voorkant" else "Eigen voorkant", "Een foto van je kaart als voorkant") { pick("cover") }
                if (card.cover != null) RowItem(Icons.Outlined.Close, "Eigen voorkant weghalen") { card = card.copy(cover = null) }
                RowItem(Icons.Outlined.AddPhotoAlternate, "Foto van de voorkant", "Blijft alleen op dit toestel") { pick("front") }
                RowItem(Icons.Outlined.AddPhotoAlternate, "Foto van de achterkant", "Blijft alleen op dit toestel") { pick("back") }
                RowItem(Icons.Outlined.AddPhotoAlternate, "Foto-notitie (bonnetje, voorwaarden)") {
                    pick((1..4).map { "note$it" }.firstOrNull { it !in card.photos && it !in pendingPhotos.value.keys } ?: "note4")
                }
            }
            val shown = (card.photos + pendingPhotos.value.keys).distinct().filter { pendingPhotos.value[it] != null || (it in card.photos && it !in pendingPhotos.value.keys) }
            if (shown.isNotEmpty()) Row(Modifier.padding(top = 10.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                shown.forEach { slot ->
                    val bytes = pendingPhotos.value[slot] ?: CardStore.photo(card.id, slot)
                    val bmp = remember(slot, bytes?.size) { bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } }
                    Box {
                        if (bmp != null) Image(bmp.asImageBitmap(), slot, Modifier.size(86.dp).clip(RoundedCornerShape(12.dp)), contentScale = ContentScale.Crop)
                        IconButton({ pendingPhotos.value = pendingPhotos.value + (slot to null) }, Modifier.align(Alignment.TopEnd).size(28.dp)
                            .clip(CircleShape).background(Color.Black.copy(alpha = 0.5f))) {
                            Icon(Icons.Outlined.Close, "Weghalen", tint = Color.White, modifier = Modifier.size(16.dp))
                        }
                    }
                }
            }

            SectionHeader("Meer")
            Field("Website (voor het logo)", card.website ?: "") { card = card.copy(website = it.ifBlank { null }) }
            Field("Notitie", card.note, singleLine = false) { card = card.copy(note = it) }
            Toggle("Favoriet", card.isFavorite) { card = card.copy(isFavorite = it) }
            Toggle("Code verbergen tot ontgrendelen", card.isLocked) { card = card.copy(isLocked = it) }
            Gap(48.dp)
        }
    }

    if (scanning) ScannerOverlay("Scan de barcode van je kaart", onResult = { v, f ->
        scanning = false
        card = card.copy(number = v, formatRaw = f.raw)
    }, onClose = { scanning = false })

    dateField?.let { which ->
        val current = when (which) { "event" -> card.details.eventDate; "renews" -> card.details.renewsAt; else -> card.expiresAt }
        val state = rememberDatePickerState(initialSelectedDateMillis = current ?: System.currentTimeMillis())
        DatePickerDialog(
            onDismissRequest = { dateField = null },
            confirmButton = {
                TextButton({
                    val v = state.selectedDateMillis
                    card = when (which) {
                        "event" -> card.copy(details = card.details.copy(eventDate = v))
                        "renews" -> card.copy(details = card.details.copy(renewsAt = v))
                        else -> card.copy(expiresAt = v)
                    }
                    dateField = null
                }) { Text("Kies") }
            },
            dismissButton = {
                TextButton({
                    card = when (which) {
                        "event" -> card.copy(details = card.details.copy(eventDate = null))
                        "renews" -> card.copy(details = card.details.copy(renewsAt = null))
                        else -> card.copy(expiresAt = null)
                    }
                    dateField = null
                }) { Text("Geen datum") }
            },
        ) { DatePicker(state) }
    }
}

@Composable
fun Field(label: String, value: String, modifier: Modifier = Modifier, keyboard: KeyboardType = KeyboardType.Text,
          singleLine: Boolean = true, onChange: (String) -> Unit) {
    OutlinedTextField(value, onChange, modifier.fillMaxWidth().padding(vertical = 4.dp), label = { Text(label) }, singleLine = singleLine,
        keyboardOptions = KeyboardOptions(keyboardType = keyboard), shape = RoundedCornerShape(14.dp))
}

@Composable
fun Toggle(title: String, value: Boolean, subtitle: String? = null, onChange: (Boolean) -> Unit) {
    RowItem(null, title, subtitle, trailing = { Switch(value, onChange) }) { onChange(!value) }
}

@Composable
private fun DateRow(title: String, value: Long?, onClick: () -> Unit) {
    RowItem(Icons.Outlined.CalendarMonth, value?.let { dateText(it) } ?: "Geen datum", title, onClick = onClick)
}
