package app.lrvdlinden.pasr.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.FlashlightOn
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.lrvdlinden.pasr.Incoming
import app.lrvdlinden.pasr.data.BarcodeFormat
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

fun mlFormat(f: Int): BarcodeFormat = when (f) {
    Barcode.FORMAT_EAN_13 -> BarcodeFormat.EAN13
    Barcode.FORMAT_EAN_8 -> BarcodeFormat.EAN8
    Barcode.FORMAT_UPC_A -> BarcodeFormat.UPCA
    Barcode.FORMAT_CODE_39 -> BarcodeFormat.CODE39
    Barcode.FORMAT_ITF -> BarcodeFormat.ITF
    Barcode.FORMAT_QR_CODE -> BarcodeFormat.QR
    Barcode.FORMAT_PDF417 -> BarcodeFormat.PDF417
    Barcode.FORMAT_AZTEC -> BarcodeFormat.AZTEC
    else -> BarcodeFormat.CODE128
}

/** Barcode of QR uit een foto of screenshot (ML Kit, op het toestel). */
fun scanImage(context: Context, uri: Uri, onResult: (String?, BarcodeFormat?) -> Unit) {
    val image = runCatching { InputImage.fromFilePath(context, uri) }.getOrNull() ?: return onResult(null, null)
    BarcodeScanning.getClient().process(image)
        .addOnSuccessListener { list ->
            val b = list.firstOrNull { !it.rawValue.isNullOrEmpty() }
            onResult(b?.rawValue, b?.let { mlFormat(it.format) })
        }
        .addOnFailureListener { onResult(null, null) }
}

/** Camera met CameraX en ML Kit (het model zit in de app; werkt zonder Google Play-services). */
@Composable
fun ScannerOverlay(title: String, onResult: (String, BarcodeFormat) -> Unit, onClose: () -> Unit) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current
    var granted by remember { mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    var torch by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var done by remember { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted = it }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scanImage(context, uri) { v, f ->
            if (v != null && f != null && !done) { done = true; onResult(v, f) } else message = "Geen barcode gevonden in deze afbeelding."
        }
    }
    LaunchedEffect(Unit) { if (!granted) permission.launch(Manifest.permission.CAMERA) }
    val cameraRef = remember { mutableStateOf<androidx.camera.core.Camera?>(null) }

    Dialog(onClose, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (granted) {
                val executor = remember { Executors.newSingleThreadExecutor() }
                val scanner = remember { BarcodeScanning.getClient() }
                DisposableEffect(Unit) { onDispose { executor.shutdown(); scanner.close() } }
                AndroidView(factory = { ctx ->
                    val view = PreviewView(ctx)
                    val future = ProcessCameraProvider.getInstance(ctx)
                    future.addListener({
                        val provider = future.get()
                        val preview = Preview.Builder().build().also { it.setSurfaceProvider(view.surfaceProvider) }
                        val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                        analysis.setAnalyzer(executor) { proxy ->
                            val media = proxy.image
                            if (media == null || done) { proxy.close(); return@setAnalyzer }
                            val input = InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees)
                            scanner.process(input)
                                .addOnSuccessListener { list ->
                                    val b = list.firstOrNull { !it.rawValue.isNullOrEmpty() }
                                    if (b != null && !done) {
                                        done = true
                                        ContextCompat.getMainExecutor(ctx).execute { onResult(b.rawValue!!, mlFormat(b.format)) }
                                    }
                                }
                                .addOnCompleteListener { proxy.close() }
                        }
                        runCatching {
                            provider.unbindAll()
                            cameraRef.value = provider.bindToLifecycle(lifecycle, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
                        }
                    }, ContextCompat.getMainExecutor(ctx))
                    view
                }, modifier = Modifier.fillMaxSize(), onRelease = {
                    runCatching { ProcessCameraProvider.getInstance(context).get().unbindAll() }
                })
                Box(Modifier.align(Alignment.Center).fillMaxWidth(0.82f).aspectRatio(1.6f).border(3.dp, Color.White.copy(alpha = 0.9f), RoundedCornerShape(22.dp)))
            } else {
                Text("Pasr heeft de camera nodig om de barcode te scannen. Je kunt ook een foto of screenshot kiezen.",
                    color = Color.White, textAlign = TextAlign.Center, modifier = Modifier.align(Alignment.Center).padding(32.dp))
            }
            Column(Modifier.fillMaxWidth().safeDrawingPadding().padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClose) { Icon(Icons.Outlined.Close, "Sluiten", tint = Color.White) }
                    Text(title, color = Color.White, modifier = Modifier.weight(1f))
                    if (granted) IconButton({ torch = !torch; cameraRef.value?.cameraControl?.enableTorch(torch) }) {
                        Icon(Icons.Outlined.FlashlightOn, "Zaklamp", tint = if (torch) Color.Yellow else Color.White)
                    }
                }
            }
            Column(Modifier.align(Alignment.BottomCenter).safeDrawingPadding().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                message?.let { Text(it, color = Color.White) }
                FilledTonalButton({
                    Incoming.leavingOnPurpose = true
                    picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                }) {
                    Icon(Icons.Outlined.Image, null); Text("  Kies een foto of screenshot")
                }
            }
        }
    }
}

/** Foto verkleinen naar JPEG (hoogstens maxSide pixels), met de juiste stand. */
fun loadJpeg(context: Context, uri: Uri, maxSide: Int = 1600, quality: Int = 82): ByteArray? = runCatching {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
    var bmp = context.contentResolver.openInputStream(uri)?.use {
        BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
    } ?: return null
    val rotation = context.contentResolver.openInputStream(uri)?.use {
        when (androidx.exifinterface.media.ExifInterface(it).getAttributeInt(androidx.exifinterface.media.ExifInterface.TAG_ORIENTATION, 1)) {
            6 -> 90f; 3 -> 180f; 8 -> 270f; else -> 0f
        }
    } ?: 0f
    val scale = minOf(1f, maxSide.toFloat() / maxOf(bmp.width, bmp.height))
    if (rotation != 0f || scale < 1f) {
        val m = Matrix().apply { postScale(scale, scale); postRotate(rotation) }
        bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
    }
    ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.JPEG, quality, it) }.toByteArray()
}.getOrNull()

fun loadPngBase64(context: Context, uri: Uri, maxSide: Int = 512): String? = runCatching {
    val bmp0 = context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) } ?: return null
    val scale = minOf(1f, maxSide.toFloat() / maxOf(bmp0.width, bmp0.height))
    val bmp = if (scale < 1f) Bitmap.createScaledBitmap(bmp0, (bmp0.width * scale).toInt(), (bmp0.height * scale).toInt(), true) else bmp0
    val out = ByteArrayOutputStream(); bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
    android.util.Base64.encodeToString(out.toByteArray(), android.util.Base64.NO_WRAP)
}.getOrNull()
