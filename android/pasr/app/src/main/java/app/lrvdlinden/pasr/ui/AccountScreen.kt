package app.lrvdlinden.pasr.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.DeleteForever
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.material3.OutlinedTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.shape.RoundedCornerShape
import app.lrvdlinden.pasr.data.Account
import app.lrvdlinden.pasr.data.DeviceRegistry
import app.lrvdlinden.pasr.data.PasrError
import app.lrvdlinden.pasr.data.Sync
import kotlinx.coroutines.launch

/** Pasr-account: inloggen, account maken (met honeypot tegen bots), wachtwoord vergeten, uitloggen, verwijderen. */
@Composable
fun AccountScreen(onClose: (() -> Unit)? = null, embedded: Boolean = false) {
    val session by Account.session.collectAsState()
    if (embedded) {
        Column(Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(20.dp)) {
            AccountContent(onDone = { onClose?.invoke() })
            TextButton({ onClose?.invoke() }, Modifier.fillMaxWidth()) { Text(if (session != null) "Verder" else "Terug") }
        }
    } else SimpleScaffold("Pasr-account") { AccountContent(onDone = null) }
}

@Composable
private fun AccountContent(onDone: (() -> Unit)?) {
    val session by Account.session.collectAsState()
    val running by Sync.running.collectAsState()
    val syncError by Sync.lastError.collectAsState()
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }

    val s = session
    if (s != null) {
        Gap(12.dp)
        Text("Ingelogd als", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(s.email, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Gap(6.dp)
        Text("Je kaarten staan versleuteld in je account en synchroniseren met je andere telefoons en tablets, ook iPhone en iPad. Foto's blijven op dit toestel.",
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        SectionHeader("Synchroniseren")
        Group {
            val last = Sync.lastSync(s.userID)
            RowItem(Icons.Outlined.Sync, if (running) "Bezig…" else "Nu synchroniseren",
                syncError ?: last?.let { "Laatst: ${dateText(it)} ${java.text.SimpleDateFormat("HH:mm", java.util.Locale("nl")).format(java.util.Date(it))}" }) {
                scope.launch { Sync.sync() }
            }
        }
        SectionHeader("Account")
        Group {
            RowItem(Icons.AutoMirrored.Outlined.Logout, "Uitloggen", "Je kaarten blijven op dit toestel") {
                scope.launch { Account.signOut(); DeviceRegistry.registerIfNeeded(force = true) }
            }
            RowItem(Icons.Outlined.DeleteForever, "Account verwijderen", "Wist je account en de kaarten op de server", tint = MaterialTheme.colorScheme.error) {
                confirmDelete = true
            }
        }
        message?.let { Gap(10.dp); Text(it, color = MaterialTheme.colorScheme.error) }
        if (confirmDelete) AlertDialog(
            { confirmDelete = false }, title = { Text("Account verwijderen?") },
            text = { Text("Je account en de kaarten op de server worden gewist. De kaarten op dit toestel blijven staan.") },
            confirmButton = {
                TextButton({
                    confirmDelete = false
                    scope.launch {
                        try { Account.deleteAccount(); DeviceRegistry.registerIfNeeded(force = true) } catch (e: PasrError) { message = e.message }
                    }
                }) { Text("Verwijderen", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton({ confirmDelete = false }) { Text("Annuleren") } },
        )
        return
    }

    var mode by remember { mutableStateOf(0) } // 0 inloggen, 1 account maken
    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    val honeypot = ""
    val opened = remember { mutableLongStateOf(System.currentTimeMillis()) }
    var info by remember { mutableStateOf<String?>(null) }

    Gap(8.dp)
    Text("Bewaar je kaarten in een account", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
    Text("Gratis en optioneel. Je kaarten staan versleuteld op één plek en zijn er meteen weer op een nieuwe telefoon. Hetzelfde account werkt op Android en iPhone.",
        color = MaterialTheme.colorScheme.onSurfaceVariant)
    Gap(16.dp)
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        listOf("Inloggen", "Account maken").forEachIndexed { i, t ->
            SegmentedButton(mode == i, { mode = i; message = null; info = null }, SegmentedButtonDefaults.itemShape(i, 2)) { Text(t) }
        }
    }
    Gap(12.dp)
    if (mode == 1) Field("Voornaam", name) { name = it }
    Field("E-mailadres", email, keyboard = KeyboardType.Email) { email = it.trim() }
    OutlinedTextField(password, { password = it }, Modifier.fillMaxWidth().padding(vertical = 4.dp), label = { Text("Wachtwoord") },
        singleLine = true, visualTransformation = PasswordVisualTransformation(), shape = RoundedCornerShape(14.dp),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
    // honeypot (veld "website") blijft in de app altijd leeg; de server rekent ook de invultijd mee (fill_ms)
    message?.let { Gap(8.dp); Text(it, color = MaterialTheme.colorScheme.error) }
    info?.let { Gap(8.dp); Text(it, color = MaterialTheme.colorScheme.tertiary) }
    Gap(16.dp)
    BrandButton(if (busy) "Even geduld…" else if (mode == 0) "Inloggen" else "Account maken", enabled = !busy && email.contains("@") && password.length >= 8) {
        busy = true; message = null; info = null
        scope.launch {
            try {
                if (mode == 0) {
                    Account.signIn(email, password)
                } else {
                    val signedIn = Account.signUp(name, email, password, honeypot, System.currentTimeMillis() - opened.longValue)
                    if (!signedIn) info = "Bijna klaar: bevestig je e-mailadres via de link in de mail van support@pasr.nl. Log daarna hier in."
                }
                if (Account.isSignedIn) {
                    Sync.sync()
                    DeviceRegistry.registerIfNeeded(force = true)
                    onDone?.invoke()
                }
            } catch (e: PasrError) {
                message = e.message
            }
            busy = false
        }
    }
    if (mode == 0) TextButton({
        if (!email.contains("@")) { message = "Vul eerst je e-mailadres in."; return@TextButton }
        scope.launch {
            runCatching { Account.sendPasswordReset(email) }
            info = "Als er een account is met dit adres, krijg je een mail om een nieuw wachtwoord te kiezen."
        }
    }, Modifier.fillMaxWidth()) { Text("Wachtwoord vergeten?") }
    if (mode == 1) TextButton({
        if (!email.contains("@")) { message = "Vul eerst je e-mailadres in."; return@TextButton }
        scope.launch { runCatching { Account.resendConfirmation(email) }; info = "Bevestigingsmail opnieuw verstuurd." }
    }, Modifier.fillMaxWidth()) { Text("Bevestigingsmail opnieuw sturen") }
    Text("Minstens 8 tekens. Met een account ga je akkoord met de privacyverklaring op pasr.nl/privacy.",
        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}
