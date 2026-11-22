package app.lrvdlinden.pasrzakelijk

import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.SideEffect
import androidx.fragment.app.FragmentActivity
import app.lrvdlinden.pasrzakelijk.core.I18n
import app.lrvdlinden.pasrzakelijk.data.BusinessStore
import app.lrvdlinden.pasrzakelijk.push.Push
import app.lrvdlinden.pasrzakelijk.ui.AppShell
import app.lrvdlinden.pasrzakelijk.ui.LocalDark
import app.lrvdlinden.pasrzakelijk.ui.PasrTheme

/** Eén scherm met Compose. FragmentActivity voor de systeemvraag van vingerafdruk/gezicht. */
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        I18n.update(resources.configuration.locales[0])
        if (savedInstanceState == null) handle(intent)
        setContent {
            PasrTheme {
                val dark = LocalDark.current
                SideEffect {
                    enableEdgeToEdge(
                        statusBarStyle = if (dark) SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
                        else SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
                        navigationBarStyle = if (dark) SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
                        else SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
                    )
                }
                AppShell()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    /** Link (uitnodiging) of tik op een pushmelding (zaak kiezen, link openen). */
    private fun handle(intent: Intent?) {
        intent ?: return
        BusinessStore.handle(intent.data)
        // link uit een melding: een uitnodiging opent in de app, een andere https-link in Custom Tabs (na het slot)
        intent.getStringExtra(Push.EXTRA_URL)?.let { android.net.Uri.parse(it) }?.let { uri ->
            if (BusinessStore.isAppLink(uri)) BusinessStore.handle(uri)
            else if (uri.scheme == "https") Push.pendingWeb.value = uri
        }
        intent.getStringExtra(Push.EXTRA_BUSINESS)?.let { BusinessStore.select(it) }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        I18n.update(newConfig.locales[0])
    }
}
