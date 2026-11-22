package app.lrvdlinden.pasrzakelijk.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.lrvdlinden.pasrzakelijk.core.L

/** Schermvullend venster (zoals een sheet op iOS) met kop: Annuleer links, titel, actie rechts. */
@Composable
fun FullSheet(
    onDismiss: () -> Unit,
    title: String,
    cancelText: String? = L("Annuleer"),
    confirmText: String? = null,
    confirmEnabled: Boolean = true,
    busy: Boolean = false,
    onConfirm: () -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    val body: @Composable () -> Unit = {
        Column(Modifier.fillMaxSize().background(Pz.bg).safeDrawingPadding()) {
            Row(Modifier.fillMaxWidth().heightIn(min = 54.dp).padding(horizontal = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) {
                    if (cancelText != null) TextButton(onClick = onDismiss) { Text(cancelText, color = Pz.accent, fontSize = 17.sp) }
                }
                Text(title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = Pz.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center, modifier = Modifier.weight(2f))
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
                    if (busy) CircularProgressIndicator(Modifier.padding(end = 12.dp).size(22.dp), color = Pz.accent, strokeWidth = 2.5.dp)
                    else if (confirmText != null) TextButton(onClick = onConfirm, enabled = confirmEnabled) {
                        Text(confirmText, color = if (confirmEnabled) Pz.accent else Pz.muted, fontWeight = FontWeight.Bold, fontSize = 17.sp)
                    }
                }
            }
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                Column(Modifier.widthIn(max = 620.dp).fillMaxWidth(), content = content)
            }
        }
    }
    // In voorbeelden (screenshots) zonder apart venster tekenen.
    if (isPreview()) body()
    else Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) { body() }
}

/** Bevestigingsvraag (zoals confirmationDialog op iOS). */
@Composable
fun ConfirmDialog(
    title: String,
    message: String? = null,
    confirm: String,
    destructive: Boolean = false,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = message?.let { { Text(it) } },
        confirmButton = {
            TextButton(onClick = { onDismiss(); onConfirm() }) {
                Text(confirm, color = if (destructive) Pz.coral else Pz.accent, fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(L("Annuleer"), color = Pz.accent) } },
        containerColor = Pz.card,
    )
}
