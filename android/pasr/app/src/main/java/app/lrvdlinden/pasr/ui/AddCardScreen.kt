package app.lrvdlinden.pasr.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.ConfirmationNumber
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.LocalOffer
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasr.data.Business
import app.lrvdlinden.pasr.data.CardKind
import app.lrvdlinden.pasr.data.Catalog
import app.lrvdlinden.pasr.data.DirectoryCard
import app.lrvdlinden.pasr.data.StoreTemplate
import kotlinx.coroutines.delay

private val tabs = listOf("Klantenkaart", "Cadeaukaart", "Stempelkaart", "Overig")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddCardScreen() {
    val nav = LocalNav.current
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var query by rememberSaveable { mutableStateOf("") }
    var scanning by remember { mutableStateOf(false) }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            Column {
                TopAppBar(
                    title = { Text("Kaart toevoegen") },
                    navigationIcon = { IconButton({ nav.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Terug") } },
                    actions = {
                        androidx.compose.material3.TextButton({ nav.push(Screen.Migrate()) }) { Text("Importeer") }
                        IconButton({ scanning = true }) { Icon(Icons.Outlined.QrCodeScanner, "QR van een zaak scannen") }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
                )
                PrimaryTabRow(tab, containerColor = MaterialTheme.colorScheme.background) {
                    tabs.forEachIndexed { i, t -> Tab(tab == i, { tab = i }, text = { Text(t, maxLines = 1) }) }
                }
                if (tab != 3) OutlinedTextField(
                    query, { query = it }, Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                    placeholder = { Text(if (tab == 2) "Zoek op zaak of plaats" else "Zoek een winkel") },
                    leadingIcon = { Icon(Icons.Outlined.Search, null) }, singleLine = true, shape = RoundedCornerShape(16.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                        unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant,
                    ),
                )
            }
        },
    ) { pad ->
        Box(Modifier.padding(pad).fillMaxSize()) {
            when (tab) {
                0 -> StoreGrid(query, CardKind.LOYALTY)
                1 -> StoreGrid(query, CardKind.VOUCHER)
                2 -> StampDirectory(query)
                else -> OtherKinds()
            }
        }
    }
    if (scanning) ScannerOverlay(
        title = "Scan de QR-code van de zaak of een Pasr-link",
        onResult = { value, _ ->
            scanning = false
            val uri = android.net.Uri.parse(value.trim())
            val id = Business.cardId(uri)
            when {
                id != null -> nav.replace(Screen.StampJoin(id, Business.memberCode(uri)))
                app.lrvdlinden.pasr.data.Share.decode(uri) != null -> nav.replace(Screen.Import(app.lrvdlinden.pasr.data.Share.decode(uri)!!))
                else -> nav.replace(Screen.Editor(kind = CardKind.LOYALTY, draft = app.lrvdlinden.pasr.data.Card(number = value,
                    formatRaw = app.lrvdlinden.pasr.data.BarcodeFormat.guess(value).raw)))
            }
        },
        onClose = { scanning = false },
    )
}

@Composable
private fun StoreGrid(query: String, kind: CardKind) {
    val nav = LocalNav.current
    val all by Catalog.all.collectAsState()
    val list = remember(all, query, kind) { Catalog.search(query, kind) }
    LazyVerticalGrid(
        GridCells.Adaptive(104.dp), Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 40.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Group(Modifier.padding(bottom = 6.dp)) {
                RowItem(Icons.Outlined.CreditCard, if (kind == CardKind.VOUCHER) "Andere cadeaukaart" else "Winkel staat er niet bij",
                    "Maak zelf een kaart met naam, kleur en logo") {
                    nav.replace(Screen.Editor(kind = kind, draft = app.lrvdlinden.pasr.data.Card(storeName = query.trim(), kindRaw = kind.raw)))
                }
            }
        }
        items(list, key = { it.id }) { t -> StoreTile(t) { nav.replace(Screen.Editor(template = t, kind = t.kind)) } }
        if (list.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) {
            Text("Geen winkel gevonden. Maak hierboven zelf een kaart.", Modifier.fillMaxWidth().padding(24.dp),
                textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun StoreTile(t: StoreTemplate, onClick: () -> Unit) {
    val logo = remember(t.id, t.remoteLogo) { Catalog.logo(t) }
    val style = if (t.managed) null else t.style
    Column(Modifier.clickable(onClick = onClick), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier.fillMaxWidth().aspectRatio(Brand.CARD_ASPECT).clip(RoundedCornerShape(12.dp)).background(hexColor(t.cardHex)).padding(10.dp),
            contentAlignment = Alignment.Center,
        ) {
            if (logo != null) Image(logo.asImageBitmap(), t.name, Modifier.fillMaxSize(), contentScale = ContentScale.Fit,
                colorFilter = style?.tint?.let { ColorFilter.tint(hexColor(it)) })
            else Text(t.name, color = onCard(t.cardHex), fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, maxLines = 2)
        }
        Text(t.name, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 4.dp))
    }
}

@Composable
private fun StampDirectory(query: String) {
    val nav = LocalNav.current
    var results by remember { mutableStateOf<List<DirectoryCard>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(query) {
        delay(300)
        error = null
        results = runCatching { Business.directory(query) }.onFailure { error = it.message }.getOrNull() ?: emptyList()
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item {
            Text("Stempelkaarten van zaken met Pasr Zakelijk. Alleen de zaak zet stempels; jij ziet altijd de stand.",
                color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
        }
        val r = results
        when {
            r == null -> item { Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
            error != null && r.isEmpty() -> item { Text(error ?: "", color = MaterialTheme.colorScheme.error) }
            r.isEmpty() -> item {
                Text("Nog geen stempelkaart van jouw zaak? Vraag de ondernemer om Pasr Zakelijk.", Modifier.fillMaxWidth().padding(24.dp),
                    textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            else -> items(r, key = { it.cardId }) { d ->
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceContainer)
                        .clickable { nav.replace(Screen.StampJoin(d.cardId)) }.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val logo = remember(d.cardId) { Catalog.decodeBase64Bitmap(d.logo) }
                    Box(Modifier.size(64.dp, 40.dp).clip(RoundedCornerShape(8.dp)).background(hexColor(d.color)).padding(4.dp), contentAlignment = Alignment.Center) {
                        if (logo != null) Image(logo.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                        else Text(d.business.take(1), color = onCard(d.color), fontWeight = FontWeight.Bold)
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(d.business, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(listOfNotNull(d.cardName.takeIf { it.isNotBlank() }, d.city).joinToString(" · "),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                        d.reward?.let { Text("${d.stampsTotal ?: 10} stempels: $it", style = MaterialTheme.typography.bodySmall, maxLines = 1) }
                    }
                    d.distanceKm?.let { Text("%.1f km".format(it), style = MaterialTheme.typography.labelSmall) }
                }
            }
        }
    }
}

@Composable
private fun OtherKinds() {
    val nav = LocalNav.current
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Group {
            RowItem(Icons.Outlined.LocalOffer, "Kortingscode", "Een code voor korting, met einddatum") { nav.replace(Screen.Editor(kind = CardKind.CODE)) }
            RowItem(Icons.Outlined.ConfirmationNumber, "Ticket", "Concert, museum of evenement") { nav.replace(Screen.Editor(kind = CardKind.TICKET)) }
            RowItem(Icons.Outlined.Sync, "Abonnement", "Sportschool, bibliotheek of lidmaatschap") { nav.replace(Screen.Editor(kind = CardKind.SUBSCRIPTION)) }
            RowItem(Icons.Outlined.CreditCard, "Eigen klantenkaart", "Elke kaart met een barcode of QR-code") { nav.replace(Screen.Editor(kind = CardKind.LOYALTY)) }
        }
    }
}
