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
    /** Winkel uit een pushbericht: open die kaart, of Kaart toevoegen bij die winkel. */
    val store = MutableStateFlow<String?>(null)
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
        if (Prefs.lockEnabled) window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        if (savedInstanceState == null) Incoming.locked.value = Prefs.lockEnabled && Prefs.onboarded
        ProcessLifecycleOwner.get().lifecycle.addObserver(lockObserver)
        handle(intent)
        setContent { Root() }
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
        intent.data?.let { Incoming.link.value = it }
        intent.getStringExtra("cardId")?.let { Incoming.cardId.value = it }
        intent.getStringExtra("store")?.let { Incoming.store.value = it }
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
