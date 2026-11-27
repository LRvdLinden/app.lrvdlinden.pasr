package app.lrvdlinden.pasr.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasr.Incoming
import app.lrvdlinden.pasr.data.Backup
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.crypto.AEADBadTagException

@Composable
fun BackupScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }

    fun handle(uri: Uri?, restore: Boolean) {
        if (uri == null || busy || password.isEmpty()) return
        val entered = password
        password = ""
        busy = true
        message = ""
        scope.launch {
            try {
                message = withContext(Dispatchers.IO) {
                    if (restore) {
                        val result = Backup.restore(context, uri, entered)
                        "${result.cards} kaart(en) en ${result.receipts} bon(nen) teruggezet."
                    } else {
                        Backup.write(context, uri, entered)
                        "Versleutelde back-up opgeslagen."
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: AEADBadTagException) {
                message = "Het wachtwoord klopt niet of de back-up is beschadigd."
            } catch (_: Exception) {
                message = if (restore) "Pasr kon deze Android-back-up niet terugzetten." else "Opslaan van de back-up is mislukt."
            } finally {
                busy = false
            }
        }
    }

    val create = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { handle(it, false) }
    val open = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { handle(it, true) }

    SimpleScaffold("Versleutelde back-up") {
        Text("Bewaar je kaarten, kaartfoto’s en bonnetjes in een bestand met je eigen wachtwoord. Je kunt dit bestand terugzetten in Pasr voor Android.")
        Gap(12.dp)
        OutlinedTextField(
            password, { password = it }, Modifier.fillMaxWidth(), enabled = !busy, singleLine = true,
            label = { Text("Wachtwoord") }, visualTransformation = PasswordVisualTransformation(),
            supportingText = { Text("Gebruik voor een nieuwe back-up ten minste acht tekens.") },
        )
        Gap(12.dp)
        BrandButton("Back-up maken", enabled = !busy && password.length >= 8) {
            Incoming.leavingOnPurpose = true
            create.launch("Pasr-Android-backup.json")
        }
        Gap(8.dp)
        BrandButton("Back-up terugzetten", enabled = !busy && password.isNotEmpty()) {
            Incoming.leavingOnPurpose = true
            open.launch(arrayOf("application/json", "application/octet-stream"))
        }
        Gap(12.dp)
        if (busy) CircularProgressIndicator()
        if (message.isNotEmpty()) Text(message)
    }
}
