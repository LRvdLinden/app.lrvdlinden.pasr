package app.lrvdlinden.pasr

import android.util.Base64
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Fingerprint
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import app.lrvdlinden.pasr.data.BarcodeFormat
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.CardDetails
import app.lrvdlinden.pasr.data.CardKind
import app.lrvdlinden.pasr.data.StoreTemplate
import app.lrvdlinden.pasr.ui.BarcodeImage
import app.lrvdlinden.pasr.ui.Brand
import app.lrvdlinden.pasr.ui.CardFace
import app.lrvdlinden.pasr.ui.Gap
import app.lrvdlinden.pasr.ui.Group
import app.lrvdlinden.pasr.ui.MoreAppsCard
import app.lrvdlinden.pasr.ui.PasrMark
import app.lrvdlinden.pasr.ui.PasrTheme
import app.lrvdlinden.pasr.ui.RowItem
import app.lrvdlinden.pasr.ui.SectionHeader
import app.lrvdlinden.pasr.ui.StampGrid
import app.lrvdlinden.pasr.ui.StoreTile
import app.lrvdlinden.pasr.ui.hexColor
import app.lrvdlinden.pasr.data.CardEvent
import app.lrvdlinden.pasr.ui.RecentUsesSection
import app.lrvdlinden.pasr.ui.UseFormat
import app.lrvdlinden.pasr.ui.UseRow
import app.lrvdlinden.pasr.ui.UsesPanel
import androidx.compose.material3.HorizontalDivider
import app.lrvdlinden.pasr.data.Receipt
import app.lrvdlinden.pasr.ui.ReceiptRow
import app.lrvdlinden.pasr.ui.Toggle
import app.lrvdlinden.pasr.ui.UsePromptBar
import app.lrvdlinden.pasr.ui.UsePromptData
import org.junit.Rule
import org.junit.Test
import java.io.File

/** Previews van Pasr voor Android (Paparazzi, zonder emulator). Statische schermen met de echte componenten. */
class PreviewTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5, theme = "android:Theme.Material.Light.NoActionBar")

    private fun logo(domain: String): String? = runCatching {
        Base64.encodeToString(File("src/main/assets/logos/$domain.png").readBytes(), Base64.NO_WRAP)
    }.getOrNull()

    private val cards by lazy {
        listOf(
            Card(storeName = "Albert Heijn", number = "2620123456785", formatRaw = "ean13", colorHex = "#00A0E2", logo = logo("ah.nl"), isFavorite = true),
            Card(storeName = "Jumbo", number = "2710123456786", formatRaw = "ean13", colorHex = "#FFC917", logo = logo("jumbo.com")),
            Card(storeName = "Kruidvat", number = "2101234567897", formatRaw = "ean13", colorHex = "#E2001A", logo = logo("kruidvat.nl")),
            Card(storeName = "HEMA", number = "6064123456789012", kindRaw = "voucher", colorHex = "#E30613", logo = logo("hema.nl"), balance = 25.0, currencyCode = "EUR"),
            Card(storeName = "Koffiebar De Boon", number = "PZABCDEFGHJK2345", formatRaw = "qr", kindRaw = "stamps", colorHex = "#5B3A29",
                details = CardDetails(issuer = "business", businessCardId = "x", stampsTotal = 10, stampsCount = 7, reward = "Gratis koffie")),
            Card(storeName = "Decathlon", number = "2090123456781", formatRaw = "ean13", colorHex = "#0082C3", logo = logo("decathlon.nl")),
        )
    }

    @Composable
    private fun Frame(dark: Boolean = false, content: @Composable () -> Unit) {
        PasrTheme(if (dark) "dark" else "light") {
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                Column(Modifier.fillMaxSize().statusBarsPadding().padding(horizontal = 16.dp)) { content() }
            }
        }
    }

    @Composable
    private fun Title(text: String, icon: Boolean = true) {
        Row(Modifier.fillMaxWidth().padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(text, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            if (icon) Icon(Icons.Outlined.Settings, null)
        }
    }

    @Test fun wallet() = paparazzi.snapshot {
        Frame {
            Title("Pasr")
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceContainer).padding(14.dp)) {
                Icon(Icons.Outlined.Search, null, tint = MaterialTheme.colorScheme.onSurfaceVariant); Text("  Zoek in je kaarten", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Row(Modifier.padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("Alles", "Favorieten", "Klantenkaarten").forEachIndexed { i, t -> FilterChip(i == 0, {}, { Text(t) }) }
            }
            cards.chunked(2).forEach { row ->
                Row(Modifier.padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { c ->
                        Column(Modifier.weight(1f)) {
                            CardFace(c, Modifier.fillMaxWidth(), compact = true)
                            Text(c.storeName, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 6.dp, start = 4.dp))
                        }
                    }
                }
            }
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                ExtendedFloatingActionButton(onClick = {}, icon = { Icon(Icons.Filled.Add, null) }, text = { Text("Kaart toevoegen") },
                    containerColor = MaterialTheme.colorScheme.primary, contentColor = Color.White)
            }
        }
    }

    @Test fun detail() = paparazzi.snapshot {
        val c = cards[0]
        Frame {
            Title(c.storeName, icon = false)
            CardFace(c, Modifier.fillMaxWidth())
            Gap(16.dp)
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Color.White).padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                BarcodeImage(c.number, BarcodeFormat.EAN13)
                Gap(8.dp)
                Text(c.number, color = Color(0xFF111216), fontFamily = FontFamily.Monospace, fontSize = 17.sp)
            }
            SectionHeader("Acties")
            Group {
                RowItem(Icons.Outlined.AccountBalanceWallet, "Toevoegen aan Google Wallet", "Pas in Google Wallet, werkt vanzelf bij")
                RowItem(Icons.Outlined.Share, "Delen", "Via WhatsApp, mail of andere apps")
                RowItem(Icons.Outlined.Delete, "Verwijderen", tint = MaterialTheme.colorScheme.error)
            }
        }
    }

    @Test fun stamps() = paparazzi.snapshot {
        val c = cards[4]
        Frame(dark = true) {
            Title(c.storeName, icon = false)
            CardFace(c, Modifier.fillMaxWidth())
            Gap(16.dp)
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Color.White).padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                BarcodeImage(c.number, BarcodeFormat.QR, Modifier.width(180.dp))
            }
            SectionHeader("Stempels")
            Group {
                Column(Modifier.padding(16.dp)) {
                    StampGrid(10, 7, Brand.mint)
                    Gap(10.dp)
                    Text("7 van 10: ${c.details.stampsProgressText}", fontWeight = FontWeight.SemiBold)
                    Text("Laat de QR-code scannen bij de kassa. Alleen de zaak zet stempels.", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                RowItem(Icons.Outlined.Refresh, "Stand verversen")
            }
        }
    }

    @Test fun add() = paparazzi.snapshot {
        val stores = listOf("ah" to ("Albert Heijn" to ("ah.nl" to "#00A0E2")), "jumbo" to ("Jumbo" to ("jumbo.com" to "#FFC917")),
            "kruidvat" to ("Kruidvat" to ("kruidvat.nl" to "#E2001A")), "hema" to ("HEMA" to ("hema.nl" to "#E30613")),
            "action" to ("Action" to ("action.com" to "#FFFFFF")), "ikea" to ("IKEA Family" to ("ikea.com" to "#0058A3")),
            "bol" to ("bol" to ("bol.com" to "#0000A5")), "decathlon" to ("Decathlon" to ("decathlon.nl" to "#0082C3")),
            "etos" to ("Etos" to ("etos.nl" to "#003B7E")))
            .map { (id, v) -> StoreTemplate(id, v.first, v.second.first, "Winkel", v.second.second, BarcodeFormat.EAN13, managed = true, remoteLogo = logo(v.second.first)) }
        Frame {
            Title("Kaart toevoegen", icon = false)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("Klantenkaart", "Cadeaukaart", "Stempelkaart", "Overig").forEachIndexed { i, t -> FilterChip(i == 0, {}, { Text(t) }) }
            }
            Gap(10.dp)
            stores.chunked(3).forEach { row ->
                Row(Modifier.padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    row.forEach { t -> Box(Modifier.weight(1f)) { StoreTile(t) {} } }
                }
            }
        }
    }

    @Test fun splash() = paparazzi.snapshot {
        Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(Color(0xFF2A2160), Color(0xFF0E0D1D)))), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                PasrMark(170.dp)
                Gap(18.dp)
                Text("Pasr", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Bold)
            }
        }
    }

    @Test fun settings() = paparazzi.snapshot {
        Frame {
            Title("Instellingen", icon = false)
            SectionHeader("Account")
            Group { RowItem(Icons.Outlined.AccountCircle, "Pasr-account", "Bewaar je kaarten versleuteld, ook tussen Android en iPhone") }
            SectionHeader("Beveiliging")
            Group {
                RowItem(Icons.Outlined.Fingerprint, "App-slot", "Vingerafdruk, gezicht of pincode bij openen")
                RowItem(Icons.Outlined.Notifications, "Herinneringen", "Cadeaukaarten en codes die verlopen")
            }
            MoreAppsCard()
            Gap(16.dp)
            Text("Versie 1.0.0", Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Box(Modifier.padding(top = 8.dp).clip(RoundedCornerShape(8.dp)).background(hexColor("#2ED3A6")).padding(6.dp)) { Text(CardKind.STAMPS.title) }
        }
    }

    // Laatst gebruikt: PLUS-kaart met drie keer (een met bedrag, een zonder, een oudere)
    private val plus by lazy {
        val now = System.currentTimeMillis()
        val h = 3_600_000L
        Card(storeName = "PLUS", number = "6064365152405021013", formatRaw = "qr", colorHex = "#FFFFFF", logo = logo("plus.nl"),
            history = listOf(
                CardEvent(date = now - 2 * h, kind = "shown", place = "PLUS Apeldoorn", amount = 6.48),
                CardEvent(date = now - 4 * 24 * h, kind = "shown", place = "PLUS Anklaar"),
                CardEvent(date = now - 13 * 24 * h, kind = "shown", place = "PLUS Twello", amount = 31.20),
                CardEvent(date = now - 18 * 24 * h, kind = "shown", place = "PLUS Apeldoorn", amount = 32.85),
                CardEvent(date = now - 35 * 24 * h, kind = "shown", place = "PLUS Apeldoorn", amount = 14.10),
            ))
    }

    @Composable
    private fun LaatstDetail() {
        val c = plus
        Title(c.storeName, icon = false)
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Color.White).padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            BarcodeImage(c.number, BarcodeFormat.QR, Modifier.width(150.dp))
            Gap(6.dp)
            Text("6064 3651 5240 5021 013", color = Color(0xFF111216), fontFamily = FontFamily.Monospace, fontSize = 14.sp)
        }
        RecentUsesSection(c, onAll = {}, onAmount = {})
    }

    @Test fun laatstGebruikt() = paparazzi.snapshot { Frame(dark = true) { LaatstDetail() } }

    @Test fun laatstGebruiktLicht() = paparazzi.snapshot { Frame { LaatstDetail() } }

    @Test fun laatstAlles() = paparazzi.snapshot {
        val c = plus
        Frame(dark = true) {
            Text("Laatst gebruikt", fontSize = 30.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.padding(top = 18.dp, bottom = 12.dp))
            val month = c.uses.filter { UseFormat.isThisMonth(it.date) }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(UseFormat.monthName() to "${month.size}× gebruikt",
                    "Ingevuld" to app.lrvdlinden.pasr.ui.euro(month.mapNotNull { it.amount }.sum())).forEach { (l, v) ->
                    Column(Modifier.weight(1f).clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.surfaceContainer).padding(horizontal = 14.dp, vertical = 10.dp)) {
                        Text(l, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(v, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
                    }
                }
            }
            c.uses.groupBy { UseFormat.group(it.date) }.forEach { (title, events) ->
                Text(title.uppercase(), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 4.dp, top = 18.dp, bottom = 6.dp))
                UsesPanel {
                    events.forEachIndexed { i, e ->
                        UseRow(c, e, withTime = true) {}
                        if (i < events.size - 1) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    }
                }
            }
        }
    }

    // Gebruik slim bijhouden (1.0.3): vraag bij sluiten, betaalmelding bij een cadeaukaart, bonnetjes
    @Test fun slimVraag() = paparazzi.snapshot {
        Frame(dark = true) {
            Box(Modifier.fillMaxSize()) {
                Column {
                    Title("Pasr")
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        cards.take(2).forEach { c -> Box(Modifier.weight(1f)) { CardFace(c, Modifier.fillMaxWidth(), compact = true) } }
                    }
                }
                Box(Modifier.align(Alignment.BottomCenter)) {
                    UsePromptBar(UsePromptData(cardId = plus.id, title = "PLUS Apeldoorn", place = "PLUS Apeldoorn"), plus, onYes = {}, onNo = {})
                }
            }
        }
    }

    @Test fun slimAfboeken() = paparazzi.snapshot {
        val now = System.currentTimeMillis()
        val hema = cards[3].copy(history = listOf(
            CardEvent(date = now - 60_000, kind = "shown", source = "pay", pendingAmount = 12.95),
            CardEvent(date = now - 3 * 86_400_000L, kind = "shown", place = "HEMA Apeldoorn", amount = 7.50, receiptID = "r1"),
        ))
        Frame(dark = true) {
            Title("HEMA", icon = false)
            Text("Laatst gebruikt", fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.padding(bottom = 8.dp))
            UsesPanel {
                hema.uses.forEachIndexed { i, e ->
                    UseRow(hema, e, withTime = true) {}
                    if (i < hema.uses.size - 1) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                }
            }
        }
    }

    @Test fun slimBonnetjes() = paparazzi.snapshot {
        val day = 86_400_000L
        val now = System.currentTimeMillis()
        val list = listOf(
            Receipt(storeName = "Coolblue", title = "Wasmachine", date = now - 2 * day, total = 649.0, warrantyUntil = now + 728 * day),
            Receipt(storeName = "PLUS", date = now - 5 * day, total = 23.45),
            Receipt(storeName = "MediaMarkt", title = "Koptelefoon", date = now - 400 * day, total = 129.99, warrantyUntil = now + 330 * day),
            Receipt(storeName = "IKEA", title = "Bureaustoel", date = now - 800 * day, total = 89.0, warrantyUntil = now - 70 * day),
        )
        Frame(dark = true) {
            Title("Bonnetjes", icon = false)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(true, {}, { Text("Alles") })
                FilterChip(false, {}, { Text("Garantie loopt nog") })
                FilterChip(false, {}, { Text("PLUS") })
            }
            list.groupBy { UseFormat.group(it.date) }.forEach { (title, items) ->
                Text(title.uppercase(), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 4.dp, top = 18.dp, bottom = 6.dp))
                UsesPanel {
                    items.forEachIndexed { i, r ->
                        ReceiptRow(r) {}
                        if (i < items.size - 1) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    }
                }
            }
        }
    }

    @Test fun slimInstellingen() = paparazzi.snapshot {
        Frame {
            Title("Instellingen", icon = false)
            SectionHeader("Laatst gebruikt")
            Group {
                Toggle("Vraag na het tonen", true, "Was de barcode 5 seconden in beeld, dan vraagt Pasr bij het sluiten of je de kaart gebruikte") {}
                Toggle("Alleen bij de winkel", true, "Niet vragen als je niet bij een bewaard filiaal bent (Ik sta hier). Je plek blijft op je telefoon.") {}
                RowItem(Icons.Outlined.Notifications, "Aankopen vanzelf vastleggen", "Uit") {}
                RowItem(Icons.Outlined.Search, "Bonnetjes", "Alle bewaarde kassabonnen, met garantie") {}
            }
            SectionHeader("Wat Pasr leest bij betaalmeldingen")
            Group {
                Column(Modifier.padding(16.dp)) {
                    listOf("Alleen betaalmeldingen met een €-bedrag.", "Daaruit alleen de winkel en het bedrag.",
                        "Alles op je telefoon; niets bewaard of verstuurd.").forEach { Text("• $it", Modifier.padding(vertical = 3.dp)) }
                }
            }
        }
    }
}
