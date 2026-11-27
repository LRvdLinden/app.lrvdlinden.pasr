package app.lrvdlinden.pasr

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import app.lrvdlinden.pasr.data.Prefs
import app.lrvdlinden.pasr.ui.Root
import kotlinx.coroutines.flow.MutableStateFlow

/** Wat de app van buiten krijgt: een link (gedeelde kaart, stempelkaart van een zaak) of een kaart uit een melding. */
object Incoming {
    val link = MutableStateFlow<Uri?>(null)
    val cardId = MutableStateFlow<String?>(null)
    /** Bonnetje uit een garantieherinnering. */
    val receipt = MutableStateFlow<String?>(null)
    val receiptShortcut = MutableStateFlow<String?>(null)
    /** Winkel uit een pushbericht: open die kaart, of Kaart toevoegen bij die winkel. */
    val store = MutableStateFlow<String?>(null)
    /** https-link uit een pushbericht die Pasr zelf niet kent: openen in Custom Tabs (na splash en ontgrendelen). */
    val web = MutableStateFlow<Uri?>(null)

    /** Links van pasr.nl die Pasr zelf opent (zelfde paden als de App Links in het manifest). */
    fun isAppLink(uri: Uri): Boolean {
        val host = uri.host?.lowercase() ?: return false
        val path = uri.path ?: ""
        return uri.scheme == "https" && (host == "pasr.nl" || host == "www.pasr.nl") &&
            (path.startsWith("/kaart") || path.startsWith("/zakelijk/kaart") || path == "/tijdelijk" || path.startsWith("/tijdelijk/") ||
                path.startsWith("/add/"))
    }
    /** Vergrendeld (app-slot): bij opstarten en elke keer dat Pasr weer naar voren komt. */
    val locked = MutableStateFlow(false)
    /** Even naar een ander scherm (fotokiezer, delen, Google Wallet): dan niet vergrendelen bij terugkomst. */
    @Volatile var leavingOnPurpose = false
}

class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // kaartnummers niet in de lijst met recente apps tonen als het slot aanstaat
        applyScreenProtection()
        if (savedInstanceState == null) Incoming.locked.value = Prefs.lockEnabled && Prefs.onboarded
        ProcessLifecycleOwner.get().lifecycle.addObserver(lockObserver)
        handle(intent)
        setContent { Root() }
    }

    private var borrowedCardVisible = false

    fun setBorrowedCardVisible(visible: Boolean) {
        borrowedCardVisible = visible
        applyScreenProtection()
    }

    fun applyScreenProtection() {
        if (borrowedCardVisible || Prefs.lockEnabled || Prefs.bool("screen.block")) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        updateCardWidgets(this)
    }

    override fun onResume() {
        super.onResume()
        applyScreenProtection()
    }

    override fun onDestroy() {
        ProcessLifecycleOwner.get().lifecycle.removeObserver(lockObserver)
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        intent ?: return
        when (intent.action) {
            "app.lrvdlinden.pasr.RECEIPTS", "app.lrvdlinden.pasr.SCAN_RECEIPT" ->
                Incoming.receiptShortcut.value = intent.action
        }
        intent.data?.let { Incoming.link.value = it }
        intent.getStringExtra("cardId")?.let { Incoming.cardId.value = it }
        intent.getStringExtra("receipt")?.let { Incoming.receipt.value = it }
        intent.getStringExtra("store")?.let { Incoming.store.value = it }
        intent.getStringExtra("url")?.let { Uri.parse(it) }?.takeIf { it.scheme == "https" }?.let { uri ->
            if (Incoming.isAppLink(uri)) Incoming.link.value = uri else Incoming.web.value = uri
        }
        if (intent.action == Intent.ACTION_SEND) {
            intent.getStringExtra(Intent.EXTRA_TEXT)?.let { text ->
                Regex("(https://(www\\.)?pasr\\.nl/\\S+|pasr://\\S+)").find(text)?.value?.let { Incoming.link.value = Uri.parse(it) }
            }
        }
    }

    private val lockObserver = object : DefaultLifecycleObserver {
        override fun onStop(owner: LifecycleOwner) {
            if (Incoming.leavingOnPurpose) { Incoming.leavingOnPurpose = false; return }
            if (Prefs.lockEnabled) Incoming.locked.value = true
        }
    }
}
