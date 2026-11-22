package app.lrvdlinden.pasrzakelijk.ui.cards

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.AutoFixHigh
import androidx.compose.material.icons.outlined.CardGiftcard
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.LibraryAdd
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Photo
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.core.LogoImage
import app.lrvdlinden.pasrzakelijk.data.Business
import app.lrvdlinden.pasrzakelijk.data.BusinessApi
import app.lrvdlinden.pasrzakelijk.data.BusinessCard
import app.lrvdlinden.pasrzakelijk.data.BusinessStore
import app.lrvdlinden.pasrzakelijk.ui.BigButton
import app.lrvdlinden.pasrzakelijk.ui.ConfirmDialog
import app.lrvdlinden.pasrzakelijk.ui.EmptyState
import app.lrvdlinden.pasrzakelijk.ui.ErrorLine
import app.lrvdlinden.pasrzakelijk.ui.FullSheet
import app.lrvdlinden.pasrzakelijk.ui.Group
import app.lrvdlinden.pasrzakelijk.ui.GroupDivider
import app.lrvdlinden.pasrzakelijk.ui.LinkButton
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.PzField
import app.lrvdlinden.pasrzakelijk.ui.ScreenScaffold
import app.lrvdlinden.pasrzakelijk.ui.SectionFooter
import app.lrvdlinden.pasrzakelijk.ui.SectionHeader
import app.lrvdlinden.pasrzakelijk.ui.SettingsRow
import app.lrvdlinden.pasrzakelijk.ui.StampCardView
import app.lrvdlinden.pasrzakelijk.ui.hexColor
import app.lrvdlinden.pasrzakelijk.ui.rememberHaptics
import app.lrvdlinden.pasrzakelijk.ui.shareText
import kotlinx.coroutines.launch
import java.io.File

/** Kaarten van de zaak (eigenaar): maken, bewerken, publiceren, delen en flyer. */
@Composable
fun CardsScreen(business: Business) {
    var editing by remember { mutableStateOf<BusinessCard?>(null) }
    var sharing by remember { mutableStateOf<BusinessCard?>(null) }
    ScreenScaffold(L("Kaarten"), actions = {
        IconButton(onClick = { editing = BusinessCard() }, enabled = business.cards.size < 5) {
            Icon(Icons.Filled.Add, L("Nieuwe kaart"), tint = if (business.cards.size < 5) Pz.accent else Pz.muted)
        }
    }) {
        if (business.cards.isEmpty()) {
            EmptyState(
                Icons.Outlined.LibraryAdd, L("Nog geen stempelkaart"),
                L("Maak je eerste stempelkaart: kies een naam, kleur, aantal stempels en beloning."),
                Modifier.padding(top = 40.dp),
            ) { BigButton(L("Nieuwe kaart"), { editing = BusinessCard() }, Modifier.widthIn(max = 260.dp)) }
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
            items(business.cards, key = { it.id }) { card ->
                Column(Modifier.widthIn(max = 620.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    StampCardView(
                        card.name, business.name, card.color, card.logo, card.stampsTotal,
                        minOf(card.stampsTotal, maxOf(1, card.stampsTotal / 2)), card.reward,
                        Modifier.clip(RoundedCornerShape(20.dp)).clickable { editing = card }, textColor = card.textColor,
                    )
                    Group {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(if (card.published) Icons.Filled.Verified else Icons.Outlined.EditNote, null,
                                tint = if (card.published) Pz.mint else Pz.muted, modifier = Modifier.size(18.dp))
                            Text("  " + if (card.published) L("Online") else L("Concept"), color = if (card.published) Pz.mint else Pz.muted, fontSize = 15.sp)
                            Spacer(Modifier.weight(1f))
                            Stat(Icons.Outlined.Group, card.members)
                            Stat(Icons.Outlined.Verified, card.stamps)
                            Stat(Icons.Outlined.CardGiftcard, card.rewards)
                        }
                        GroupDivider()
                        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                            TextButton(onClick = { editing = card }) {
                                Icon(Icons.Filled.Edit, null, tint = Pz.accent, modifier = Modifier.size(18.dp))
                                Text("  " + L("Bewerken"), color = Pz.accent, fontWeight = FontWeight.SemiBold)
                            }
                            Spacer(Modifier.weight(1f))
                            if (card.published) {
                                TextButton(onClick = { sharing = card }) {
                                    Icon(Icons.Filled.QrCode, null, tint = Pz.accent, modifier = Modifier.size(18.dp))
                                    Text("  " + L("QR, link en flyer"), color = Pz.accent, fontWeight = FontWeight.SemiBold)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    editing?.let { CardEditorSheet(business, it) { editing = null } }
    sharing?.let { CardShareSheet(business, it) { sharing = null } }
}

@Composable
private fun Stat(icon: ImageVector, value: Int) {
    Row(Modifier.padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Pz.muted, modifier = Modifier.size(16.dp))
        Text(" $value", color = Pz.muted, fontSize = 15.sp)
    }
}

/** Kaart maken of bewerken, met automatische huisstijl van de website (business-brand). */
@Composable
fun CardEditorSheet(business: Business, initial: BusinessCard, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val inspection = LocalInspectionMode.current
    var card by remember { mutableStateOf(initial) }
    var logoChanged by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var brandBusy by remember { mutableStateOf(false) }
    var brandDomain by remember { mutableStateOf<String?>(null) }
    var brandFailed by remember { mutableStateOf(false) }
    var customHex by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val isNew = initial.id.isEmpty()
    val valid = card.name.isNotBlank() && card.reward.isNotBlank()

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        uri ?: return@rememberLauncherForActivityResult
        val bmp: Bitmap? = runCatching {
            if (Build.VERSION.SDK_INT >= 28) ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { d, _, _ ->
                d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
            else @Suppress("DEPRECATION") MediaStore.Images.Media.getBitmap(context.contentResolver, uri)
        }.getOrNull()
        val encoded = bmp?.let { LogoImage.encode(it) }
        if (encoded != null) { card = card.copy(logo = encoded); logoChanged = true } else message = L("Dit bestand is geen afbeelding.")
    }

    /** Logo, kleur en tekstkleur van de website. Lukt het niet: Pasr-kleur en initiaal, zonder fout. */
    fun fetchBrand() {
        brandBusy = true
        scope.launch {
            val brand = BusinessApi.brand(business.id, business.website)
            if (brand == null) {
                brandFailed = true
                brandDomain = null
                if (isNew && card.logo == null) card = card.copy(color = "#6A5CFF", textColor = null)
            } else {
                brandFailed = false
                var c = card
                brand.logo?.let { c = c.copy(logo = it); logoChanged = true }
                brand.color?.let { c = c.copy(color = it) }
                c = c.copy(textColor = brand.textColor)
                if (c.name.isBlank() && brand.name != null) c = c.copy(name = brand.name.take(40))
                card = c
                brandDomain = brand.domain ?: business.website?.let { runCatching { Uri.parse(if (it.contains("://")) it else "https://$it").host }.getOrNull() }
                    ?: L("je website")
            }
            brandBusy = false
        }
    }
    LaunchedEffect(Unit) { if (isNew && card.logo == null && !inspection) fetchBrand() }

    FullSheet(onDismiss, if (isNew) L("Nieuwe kaart") else L("Kaart bewerken"), confirmText = L("Opslaan"), confirmEnabled = valid, busy = busy, onConfirm = {
        busy = true; message = null
        scope.launch {
            try {
                BusinessApi.saveCard(card, business, logoChanged)
                haptics.success()
                BusinessStore.load()
                onDismiss()
            } catch (e: Exception) { message = e.message; haptics.error() } finally { busy = false }
        }
    }) {
        Column(Modifier.imePadding().verticalScroll(rememberScrollState()).padding(16.dp)) {
            StampCardView(
                card.name.ifEmpty { L("Naam van de kaart") }, business.name, card.color, card.logo, card.stampsTotal,
                maxOf(1, card.stampsTotal * 6 / 10), card.reward.ifEmpty { L("Je beloning") }, textColor = card.textColor,
            )
            Spacer(Modifier.height(16.dp))
            // huisstijl
            Group {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (brandDomain != null) Icons.Outlined.AutoFixHigh else Icons.Outlined.Palette, null,
                        tint = if (brandDomain != null) Pz.mint else Pz.muted, modifier = Modifier.size(20.dp))
                    Text(
                        when {
                            brandBusy -> L("Huisstijl ophalen…")
                            brandDomain != null -> L("Overgenomen van %@", brandDomain)
                            brandFailed -> L("Geen huisstijl gevonden. Kies zelf een logo en kleur.")
                            else -> L("Huisstijl van je website")
                        },
                        Modifier.weight(1f).padding(horizontal = 10.dp), fontSize = 15.sp, color = Pz.text,
                    )
                    if (brandBusy) CircularProgressIndicator(Modifier.size(20.dp), color = Pz.accent, strokeWidth = 2.dp)
                    else LinkButton(L("Opnieuw ophalen"), { fetchBrand() })
                }
            }
            SectionFooter(L("Logo en kleuren komen van de website van je zaak. Je kunt alles hieronder aanpassen."))

            SectionHeader(L("Kaart"))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                PzField(card.name, { card = card.copy(name = it.take(40)) }, L("Naam (bijv. Koffiekaart)"))
                PzField(card.reward, { card = card.copy(reward = it.take(80)) }, L("Beloning (bijv. 1 gratis koffie)"))
            }
            Spacer(Modifier.height(8.dp))
            Group {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(L("Aantal stempels"), Modifier.weight(1f), fontSize = 17.sp, color = Pz.text)
                    Stepper(card.stampsTotal, 2..30) { card = card.copy(stampsTotal = it) }
                }
            }

            SectionHeader(L("Kleur"))
            Group {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (row in Pz.swatches.chunked(6)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            for (hex in row) {
                                val on = card.color.equals(hex, ignoreCase = true)
                                Box(
                                    Modifier.weight(1f).aspectRatio(1f).clip(CircleShape).background(hexColor(hex))
                                        .border(if (on) 3.dp else 0.dp, Pz.text, CircleShape)
                                        .clickable { card = card.copy(color = hex, textColor = null) },
                                )
                            }
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        PzField(customHex, { customHex = it.take(7) }, L("Eigen kleur (#RRGGBB)"), Modifier.weight(1f),
                            capitalization = KeyboardCapitalization.Characters, autoCorrect = false, monospace = true)
                        val parsed = BusinessApi.hex(customHex)
                        TextButton(onClick = { parsed?.let { card = card.copy(color = it, textColor = null) } }, enabled = parsed != null) {
                            Text(L("Gebruik"), color = if (parsed != null) Pz.accent else Pz.muted, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }

            SectionHeader(L("Logo"))
            Group {
                SettingsRow(if (card.logo == null) L("Logo kiezen") else L("Ander logo kiezen"), Icons.Outlined.Photo, Pz.sky,
                    onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) })
                if (card.logo != null) {
                    GroupDivider()
                    SettingsRow(L("Logo weghalen"), titleColor = Pz.coral, onClick = { card = card.copy(logo = null); logoChanged = true })
                }
            }
            SectionFooter(L("Een vierkant logo werkt het best. Pasr verkleint het tot 256 pixels."))

            Spacer(Modifier.height(16.dp))
            Group {
                SettingsRow(L("Online (klanten kunnen sparen)"), enabled = business.isApproved, onClick = { card = card.copy(published = !card.published) }) {
                    Switch(card.published, { card = card.copy(published = it) }, enabled = business.isApproved,
                        colors = SwitchDefaults.colors(checkedTrackColor = Pz.mint))
                }
            }
            SectionFooter(L("Een concept zie je alleen zelf. Zet de kaart online om de QR-code en flyer te gebruiken."))
            message?.let { Spacer(Modifier.height(12.dp)); ErrorLine(it) }
            if (!isNew) {
                Spacer(Modifier.height(16.dp))
                Group { SettingsRow(L("Kaart verwijderen"), titleColor = Pz.coral, onClick = { confirmDelete = true }) }
                SectionFooter(L("Klanten met deze kaart kunnen dan niet meer sparen."))
            }
            Spacer(Modifier.height(30.dp))
        }
    }
    if (confirmDelete) {
        ConfirmDialog(L("Kaart verwijderen?"), null, L("Verwijderen"), destructive = true, onConfirm = {
            busy = true
            scope.launch {
                try { BusinessApi.deleteCard(card.id); BusinessStore.load(); onDismiss() } catch (e: Exception) { message = e.message } finally { busy = false }
            }
        }, onDismiss = { confirmDelete = false })
    }
}

/** − waarde + (zoals een Stepper op iOS). */
@Composable
fun Stepper(value: Int, range: IntRange, onChange: (Int) -> Unit) {
    val haptics = rememberHaptics()
    Row(verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = { onChange(maxOf(range.first, value - 1)); haptics.tick() }, enabled = value > range.first) {
            Text("−", fontSize = 22.sp, color = if (value > range.first) Pz.accent else Pz.muted)
        }
        Text("$value", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Pz.text, textAlign = TextAlign.Center, modifier = Modifier.widthIn(min = 32.dp))
        TextButton(onClick = { onChange(minOf(range.last, value + 1)); haptics.tick() }, enabled = value < range.last) {
            Text("+", fontSize = 22.sp, color = if (value < range.last) Pz.accent else Pz.muted)
        }
    }
}

/** QR-code, link en flyer (A4-PDF) van een kaart. */
@Composable
fun CardShareSheet(business: Business, card: BusinessCard, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val qr = remember(card.id) { QrCode.bitmap(card.joinURL)?.asImageBitmap() }
    var flyer by remember { mutableStateOf<File?>(null) }
    LaunchedEffect(card.id) { flyer = Flyer.makePDF(context, business, card) }
    FullSheet(onDismiss, card.name, cancelText = null, confirmText = L("Klaar"), onConfirm = onDismiss) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Text(L("Klanten scannen deze code met hun camera en sparen in Pasr of in de browser."), color = Pz.muted, textAlign = TextAlign.Center)
            if (qr != null) {
                Image(
                    qr, L("QR-code van de kaart"), filterQuality = FilterQuality.None,
                    modifier = Modifier.widthIn(max = 260.dp).fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(20.dp)).background(Color.White).padding(16.dp),
                )
            }
            Text(card.joinURL, color = Pz.muted, fontSize = 13.sp, fontFamily = FontFamily.Monospace, textAlign = TextAlign.Center)
            BigButton(L("Link delen"), {
                context.shareText(L("Spaar bij %@ met de digitale stempelkaart.", business.name) + "\n" + card.joinURL, card.name)
            }, icon = Icons.Filled.Share)
            val file = flyer
            if (file != null) {
                BigButton(L("Flyer (A4, PDF)"), { Flyer.share(context, file) }, icon = Icons.Filled.Share, color = Pz.mint, foreground = Color.Black)
                BigButton(L("Flyer afdrukken"), { Flyer.print(context, file) }, icon = Icons.Filled.Print, color = Pz.card2, foreground = Pz.text)
            } else {
                CircularProgressIndicator(color = Pz.accent)
            }
            Text(L("Print de flyer en zet hem op de toonbank."), color = Pz.muted, fontSize = 13.sp)
        }
    }
}

