package app.lrvdlinden.pasr.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.CardGiftcard
import androidx.compose.material.icons.outlined.ConfirmationNumber
import androidx.compose.material.icons.outlined.Receipt
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.SortByAlpha
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasr.data.Account
import app.lrvdlinden.pasr.data.Business
import app.lrvdlinden.pasr.data.CardKind
import app.lrvdlinden.pasr.data.CardOrder
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.ReceiptUseLinker
import app.lrvdlinden.pasr.data.Catalog
import app.lrvdlinden.pasr.data.Prefs
import app.lrvdlinden.pasr.data.Sync
import app.lrvdlinden.pasr.data.ordered
import app.lrvdlinden.pasr.data.stackItems
import kotlinx.coroutines.launch

private enum class Filter(val title: String) { ALL("Alles"), FAV("Favorieten"), LOYALTY("Klantenkaarten"), GIFT("Cadeaukaarten"), STAMPS("Stempelkaarten"), OTHER("Overig") }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WalletScreen() {
    val nav = LocalNav.current
    val snack = LocalSnack.current
    val scope = rememberCoroutineScope()
    val all by CardStore.cards.collectAsState()
    var query by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf(Filter.ALL) }
    var order by remember { mutableStateOf(Prefs.order) }
    var orderMenu by remember { mutableStateOf(false) }
    val walletContext = androidx.compose.ui.platform.LocalContext.current
    var here by remember { mutableStateOf<android.location.Location?>(null) }
    var locationTick by remember { mutableStateOf(0) }
    val locationPermission = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions()) { locationTick++ }
    LaunchedEffect(order, locationTick, all.size) {
        here = if (order == CardOrder.NEARBY) lastKnownLocation(walletContext) else null
    }
    var refreshing by remember { mutableStateOf(false) }
    val visible = all.filter { it.deletedAt == null }
    val q = Catalog.fold(query.trim())
    fun matches(c: app.lrvdlinden.pasr.data.Card) =
        (q.isEmpty() || Catalog.fold("${c.storeName} ${c.note}").contains(q)) && when (filter) {
            Filter.ALL -> true
            Filter.FAV -> c.isFavorite
            Filter.LOYALTY -> c.kind == CardKind.LOYALTY
            Filter.GIFT -> c.kind == CardKind.VOUCHER
            Filter.STAMPS -> c.kind == CardKind.STAMPS
            Filter.OTHER -> c.kind in CardKind.others
        }
    // tickets voor hetzelfde evenement op dezelfde dag zijn één tegel (data/TicketGroups.kt); een groep staat erin als
    // één van zijn tickets bij het filter en de zoekterm past
    val cards = visible.ordered(order, here).stackItems().filter { item -> item.cards.any(::matches) }
    val favorites = if (filter == Filter.ALL && q.isEmpty()) cards.filter { item -> item.cards.any { it.isFavorite } } else emptyList()
    // de zoekbalk vindt ook bonnetjes (winkel, bedrag of datum)
    val receipts by app.lrvdlinden.pasr.data.ReceiptStore.receipts.collectAsState()
    // Herstel bestaande kassabonnen uit oudere builds zonder dubbele transactie.
    LaunchedEffect(receipts.map { it.id + ":" + (it.useID ?: "") }.joinToString(),
        all.filter { it.deletedAt == null }.map { it.id }.sorted().joinToString()) {
        ReceiptUseLinker.reconcile()
    }
    val foundReceipts = if (query.isBlank()) emptyList() else receipts.filter { it.matches(query) }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        snackbarHost = { SnackbarHost(snack) },
        topBar = {
            TopAppBar(
                title = { Text("Pasr", fontWeight = FontWeight.Bold) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
                actions = {
                    Box {
                        IconButton({ orderMenu = true }) { Icon(Icons.Outlined.SortByAlpha, "Volgorde") }
                        DropdownMenu(orderMenu, { orderMenu = false }) {
                            CardOrder.entries.forEach { o ->
                                DropdownMenuItem({ Text((if (o == order) "✓ " else "") + o.title) }, {
                                    order = o; Prefs.order = o; orderMenu = false
                                    if (o == CardOrder.NEARBY && lastKnownLocation(walletContext) == null) {
                                        app.lrvdlinden.pasr.Incoming.leavingOnPurpose = true
                                        locationPermission.launch(arrayOf(android.Manifest.permission.ACCESS_COARSE_LOCATION,
                                            android.Manifest.permission.ACCESS_FINE_LOCATION))
                                    }
                                })
                            }
                        }
                    }
                    IconButton({ nav.push(Screen.Benefits) }) { Icon(Icons.Outlined.CardGiftcard, "Mijn voordelen") }
                    IconButton({ nav.push(Screen.Coupons) }) { Icon(Icons.Outlined.ConfirmationNumber, "Kortingsbonnen") }
                    IconButton({ nav.push(Screen.Receipts()) }) { Icon(Icons.Outlined.Receipt, "Bonnetjes") }
                    IconButton({ nav.push(Screen.Settings) }) { Icon(Icons.Outlined.Settings, "Instellingen") }
                },
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { nav.push(Screen.Add) }, containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary, icon = { Icon(Icons.Filled.Add, null) },
                text = { Text("Kaart toevoegen") },
            )
        },
    ) { pad ->
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch {
                    refreshing = true
                    if (Account.isSignedIn) Sync.sync()
                    Business.refreshAll(force = true)
                    Catalog.refresh(force = true)
                    refreshing = false
                    Sync.lastError.value?.let { snack.showSnackbar(it) }
                }
            },
            modifier = Modifier.padding(pad).fillMaxSize(),
        ) {
            if (visible.isEmpty()) {
                EmptyWallet { nav.push(Screen.Add) }
                return@PullToRefreshBox
            }
            LazyVerticalGrid(
                GridCells.Adaptive(160.dp), Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 100.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Column {
                        OutlinedTextField(
                            query, { query = it }, Modifier.fillMaxWidth(), placeholder = { Text("Zoek in je kaarten en bonnetjes") },
                            leadingIcon = { Icon(Icons.Outlined.Search, null) }, singleLine = true, shape = RoundedCornerShape(16.dp),
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                            colors = OutlinedTextFieldDefaults.colors(
                                unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                                focusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                                unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant,
                            ),
                        )
                        Row(Modifier.fillMaxWidth().padding(top = 8.dp).horizontalScrollCompat(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Filter.entries.forEach { f -> FilterChip(f == filter, { filter = f }, { Text(f.title) }) }
                        }
                    }
                }
                if (favorites.isNotEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) { SectionHeader("Favorieten") }
                    items(favorites, key = { "fav-" + it.id }) { item -> StackTile(item) { nav.push(Screen.Detail(item.id)) } }
                    item(span = { GridItemSpan(maxLineSpan) }) { SectionHeader("Alle kaarten") }
                }
                items(cards, key = { it.id }) { item -> StackTile(item) { nav.push(Screen.Detail(item.id)) } }
                if (foundReceipts.isNotEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            SectionHeader(if (foundReceipts.size == 1) "1 bonnetje" else "${foundReceipts.size} bonnetjes", Modifier.weight(1f))
                            androidx.compose.material3.TextButton({ nav.push(Screen.Receipts(query)) }, Modifier.padding(top = 14.dp)) { Text("Alles") }
                        }
                    }
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        UsesPanel {
                            foundReceipts.take(5).forEach { r -> ReceiptRow(r) { nav.push(Screen.ReceiptDetail(r.id)) } }
                        }
                    }
                }
                if (cards.isEmpty() && foundReceipts.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) {
                    Text("Geen kaarten gevonden.", Modifier.padding(32.dp).fillMaxWidth(), textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** Een losse kaart, of een groep tickets als één tegel. */
@Composable
private fun StackTile(item: app.lrvdlinden.pasr.data.CardStackItem, onClick: () -> Unit) {
    if (item.isGroup) TicketGroupTile(item, onClick) else CardTile(item.first, onClick)
}

@Composable
fun CardTile(card: app.lrvdlinden.pasr.data.Card, onClick: () -> Unit) {
    Column(Modifier.clickable(onClick = onClick)) {
        CardFace(card, Modifier.fillMaxWidth(), compact = true)
        Text(card.storeName.ifBlank { card.kind.title }, style = MaterialTheme.typography.labelLarge, maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 4.dp, top = 6.dp))
    }
}

@Composable
private fun EmptyWallet(onAdd: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        PasrMark(140.dp)
        Spacer(Modifier.height(24.dp))
        Text("Nog geen kaarten", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        Text("Voeg je eerste klantenkaart, cadeaukaart of stempelkaart toe. Kies de winkel en scan de barcode.",
            textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(24.dp))
        BrandButton("Kaart toevoegen", Modifier.size(width = 240.dp, height = 52.dp), onClick = onAdd)
    }
}

@Composable
fun Modifier.horizontalScrollCompat(): Modifier = this.then(Modifier.horizontalScroll(androidx.compose.foundation.rememberScrollState()))


/** Laatst bekende locatie van het toestel (alleen voor de volgorde In de buurt; blijft op het toestel). */
@android.annotation.SuppressLint("MissingPermission")
internal fun lastKnownLocation(context: android.content.Context): android.location.Location? {
    val fine = androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION) ==
        android.content.pm.PackageManager.PERMISSION_GRANTED
    val coarse = androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_COARSE_LOCATION) ==
        android.content.pm.PackageManager.PERMISSION_GRANTED
    if (!fine && !coarse) return null
    val lm = context.getSystemService(android.content.Context.LOCATION_SERVICE) as? android.location.LocationManager ?: return null
    return runCatching {
        lm.getProviders(true).mapNotNull { lm.getLastKnownLocation(it) }
            .filter { System.currentTimeMillis() - it.time < 6 * 3_600_000L }
            .maxByOrNull { it.time }
    }.getOrNull()
}
