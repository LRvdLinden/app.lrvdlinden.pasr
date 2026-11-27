package app.lrvdlinden.pasr.ui

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.lrvdlinden.pasr.Incoming
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.Catalog
import app.lrvdlinden.pasr.data.readImportedCards
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

@Composable
fun MigrateScreen(cards: MutableList<Card>) {
    val context = LocalContext.current
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    var progress by remember { mutableStateOf<Float?>(null) }
    var message by remember { mutableStateOf("") }

    fun scan(uris: List<Uri>, video: Boolean) {
        if (uris.isEmpty() || progress != null) return
        progress = 0f
        message = ""
        scope.launch {
            val seen = (CardStore.cards.value.map { it.number } + cards.map { it.number }).toMutableSet()
            val previousCount = cards.size
            try {
                val failed = scanMedia(context, uris, video, seen, { progress = it }, { cards.add(it) })
                message = when {
                    failed == uris.size -> "Pasr kon de geselecteerde media niet lezen."
                    cards.size == previousCount -> "Geen nieuwe barcodes gevonden."
                    failed > 0 -> "Een deel van de geselecteerde media kon niet worden gelezen."
                    else -> ""
                }
            } finally {
                progress = null
            }
        }
    }

    val images = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(50)) { scan(it, false) }
    val video = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { scan(listOfNotNull(it), true) }

    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty() && progress == null) {
            progress = 0f
            message = ""
            scope.launch {
                val seen = (CardStore.cards.value.map { it.number } + cards.map { it.number }).toMutableSet()
                var failed = 0
                val before = cards.size
                try {
                    for ((index, uri) in uris.withIndex()) {
                        try {
                            cards.addAll(withContext(Dispatchers.IO) { readImportedCards(context, uri) }
                                .filter { seen.add(it.number) })
                        } catch (e: CancellationException) {
                            throw e
                        } catch (_: Exception) {
                            failed++
                        }
                        progress = (index + 1f) / uris.size
                    }
                    message = when {
                        failed == uris.size -> "Pasr kon de geselecteerde bestanden niet lezen."
                        failed > 0 -> "Een deel van de bestanden kon niet worden gelezen."
                        cards.size == before -> "Geen nieuwe kaarten gevonden."
                        else -> ""
                    }
                } finally {
                    progress = null
                }
            }
        }
    }

    val savedCards by CardStore.cards.collectAsState()
    SimpleScaffold("Kaarten importeren") {
        Text("Haal barcodes uit screenshots of een schermopname van je vorige kaartenapp.")
        Gap(12.dp)
        TextButton(enabled = progress == null, onClick = {
            Incoming.leavingOnPurpose = true
            images.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        }) { Text("Kies screenshots") }
        TextButton(enabled = progress == null, onClick = {
            Incoming.leavingOnPurpose = true
            video.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly))
        }) { Text("Kies schermopname") }
        TextButton(enabled = progress == null, onClick = {
            Incoming.leavingOnPurpose = true
            files.launch(arrayOf("*/*"))
        }) { Text("Kies CSV-, JSON- of Wallet-bestanden") }
        progress?.let { fraction -> LinearProgressIndicator(progress = { fraction }, modifier = Modifier.fillMaxWidth()) }
        if (message.isNotEmpty()) Text(message)
        for (card in cards.filterNot { candidate -> savedCards.any { it.id == candidate.id || it.number == candidate.number } }) {
            TextButton(enabled = progress == null, onClick = {
                nav.push(Screen.Editor(draft = card))
            }) { Text("Controleer ${card.storeName.ifBlank { "kaart" }} · ${card.number}") }
        }
    }
}

private suspend fun scanMedia(
    context: Context,
    uris: List<Uri>,
    video: Boolean,
    seen: MutableSet<String>,
    progress: (Float) -> Unit,
    found: (Card) -> Unit,
): Int = withContext(Dispatchers.IO) {
    val scanner = BarcodeScanning.getClient()
    val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    suspend fun read(image: InputImage) {
        val barcodes = scanner.process(image).resultWhenComplete().filter { !it.rawValue.isNullOrBlank() }
        if (barcodes.none { it.rawValue !in seen }) return
        val text = try {
            Catalog.fold(recognizer.process(image).resultWhenComplete().text)
                .replace(Regex("\\s+"), " ")
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            ""
        }
        val template = Catalog.all.value
            .filter { it.kind == app.lrvdlinden.pasr.data.CardKind.LOYALTY }
            .filter { it.name.length >= 4 && Catalog.fold(it.name) in text }
            .maxByOrNull { it.name.length }
        for (barcode in barcodes) {
            val number = barcode.rawValue ?: continue
            if (seen.add(number)) {
                val card = Card(
                    storeName = template?.name.orEmpty(), templateID = template?.id,
                    colorHex = template?.cardHex ?: "#2B2F3A", number = number,
                    formatRaw = mlFormat(barcode.format).raw,
                )
                withContext(Dispatchers.Main) { found(card) }
            }
        }
    }

    var failed = 0
    try {
        for ((index, uri) in uris.withIndex()) {
            ensureActive()
            try {
                if (video) {
                    val reader = MediaMetadataRetriever()
                    try {
                        reader.setDataSource(context, uri)
                        val duration = reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                            ?.toLongOrNull()?.takeIf { it > 0 } ?: error("Video zonder duur")
                        val width = reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 1
                        val height = reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 1
                        val scale = minOf(1f, 1400f / maxOf(width, height, 1))
                        var time = 0L
                        val step = maxOf(333L, duration / 1800)
                        while (time < duration) {
                            ensureActive()
                            val frame = if (Build.VERSION.SDK_INT >= 27) reader.getScaledFrameAtTime(
                                time * 1000, MediaMetadataRetriever.OPTION_CLOSEST,
                                (width * scale).toInt().coerceAtLeast(1), (height * scale).toInt().coerceAtLeast(1),
                            ) else reader.getFrameAtTime(time * 1000, MediaMetadataRetriever.OPTION_CLOSEST)
                            if (frame != null) {
                                read(InputImage.fromBitmap(frame, 0))
                            }
                            time += step
                            withContext(Dispatchers.Main) { progress((time.toFloat() / duration).coerceAtMost(1f)) }
                        }
                    } finally {
                        reader.release()
                    }
                } else {
                    read(InputImage.fromFilePath(context, uri))
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                failed++
            }
            withContext(Dispatchers.Main) { progress((index + 1f) / uris.size) }
        }
    } finally {
        scanner.close()
        recognizer.close()
    }
    failed
}

private suspend fun <T> Task<T>.resultWhenComplete(): T = suspendCancellableCoroutine { continuation ->
    addOnCompleteListener { task ->
        when {
            task.isCanceled -> continuation.cancel()
            task.isSuccessful -> continuation.resume(task.result)
            else -> continuation.resumeWithException(task.exception ?: IllegalStateException("Barcode lezen mislukt"))
        }
    }
}
