package app.lrvdlinden.pasrzakelijk.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.outlined.CardGiftcard
import androidx.compose.material.icons.outlined.Fingerprint
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material.icons.outlined.Print
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.automirrored.outlined.ShowChart
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.BuildConfig
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.ui.FullSheet
import app.lrvdlinden.pasrzakelijk.ui.Group
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.SectionHeader

/** Wat is nieuw in deze versie. */
@Composable
fun WhatsNewSheet(onDismiss: () -> Unit) {
    FullSheet(onDismiss, L("Wat is nieuw"), cancelText = null, confirmText = L("Klaar"), onConfirm = onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp)) {
            SectionHeader(BuildConfig.VERSION_NAME)
            Group {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Item(Icons.Outlined.QrCodeScanner, L("Scannen aan de kassa"), L("Scan de QR-code van je klant, kies het aantal stempels en tik op Stempels toevoegen."))
                    Item(Icons.Outlined.CardGiftcard, L("Beloning inwisselen"), L("Is de kaart vol, dan wissel je de beloning in met één tik."))
                    Item(Icons.AutoMirrored.Filled.Undo, L("Ongedaan maken"), L("Vergist? Maak de laatste stempel of inwisseling binnen 2 minuten ongedaan."))
                    Item(Icons.Outlined.Timer, L("Afkoeltijd"), L("Een klant krijgt niet twee keer kort na elkaar een stempel. Je kiest zelf hoe lang."))
                    Item(Icons.Outlined.Group, L("Medewerkers"), L("Nodig je team uit met een link. Medewerkers zien alleen de scanner."))
                    Item(Icons.AutoMirrored.Outlined.ShowChart, L("Overzicht en logboek"), L("Stempels, beloningen en nieuwe leden per dag, en wie wat deed."))
                    Item(Icons.Outlined.Print, L("Flyer"), L("Deel de QR-code of maak een A4-flyer voor op de toonbank."))
                    Item(Icons.Outlined.Fingerprint, L("Vergrendelen met vingerafdruk of gezicht"), L("Zet in Instellingen de vergrendeling aan; bij openen vraagt de app om je vingerafdruk, gezicht of schermvergrendeling."))
                    Item(Icons.Outlined.Place, L("Vindbaar in Pasr"), L("Klanten vinden je stempelkaart in de lijst in Pasr, ook in de buurt."))
                }
            }
        }
    }
}

@Composable
private fun Item(icon: ImageVector, title: String, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = Pz.mint, modifier = Modifier.size(26.dp))
        Column {
            Text(title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = Pz.text)
            Text(text, color = Pz.muted, fontSize = 15.sp)
        }
    }
}
