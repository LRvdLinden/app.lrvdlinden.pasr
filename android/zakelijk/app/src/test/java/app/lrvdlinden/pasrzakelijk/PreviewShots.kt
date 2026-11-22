package app.lrvdlinden.pasrzakelijk

import androidx.activity.OnBackPressedDispatcher
import androidx.activity.OnBackPressedDispatcherOwner
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.compose.LocalOnBackPressedDispatcherOwner
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.core.app.ActivityOptionsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import app.lrvdlinden.pasrzakelijk.core.I18n
import app.lrvdlinden.pasrzakelijk.data.Account
import app.lrvdlinden.pasrzakelijk.data.BusinessStore
import app.lrvdlinden.pasrzakelijk.data.Demo
import app.lrvdlinden.pasrzakelijk.data.StaffInvite
import app.lrvdlinden.pasrzakelijk.ui.MainTabs
import app.lrvdlinden.pasrzakelijk.ui.PasrTheme
import app.lrvdlinden.pasrzakelijk.ui.PendingScreen
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.SplashScreen
import app.lrvdlinden.pasrzakelijk.ui.WelcomeScreen
import app.lrvdlinden.pasrzakelijk.ui.cards.CardEditorSheet
import app.lrvdlinden.pasrzakelijk.ui.cards.CardShareSheet
import app.lrvdlinden.pasrzakelijk.ui.overview.LogScreen
import app.lrvdlinden.pasrzakelijk.ui.scan.ScanResultContent
import app.lrvdlinden.pasrzakelijk.ui.staff.InviteStaffSheet
import org.junit.Rule
import org.junit.Test

/**
 * Schermafbeeldingen van Pasr Zakelijk voor Android met voorbeeldgegevens (Paparazzi, zonder toestel).
 * CI: ./gradlew :app:recordPaparazziDebug → app/src/test/snapshots/images/*.png
 */
class PreviewShots {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_6.copy(softButtons = false), maxPercentDifference = 0.0)

    private fun shot(dark: Boolean = false, content: @Composable () -> Unit) {
        I18n.dutch = true
        Demo.enabled = true
        Account.demo("anna@deboon.nl")
        BusinessStore.demo(listOf(Demo.business))
        paparazzi.snapshot {
            Owners {
                PasrTheme(dark = dark) {
                    Box(Modifier.fillMaxSize().background(Pz.bg)) { content() }
                }
            }
        }
    }

    @Composable
    private fun Owners(content: @Composable () -> Unit) {
        val owner = LocalLifecycleOwner.current
        val registry = object : ActivityResultRegistryOwner {
            override val activityResultRegistry = object : ActivityResultRegistry() {
                override fun <I, O> onLaunch(requestCode: Int, contract: ActivityResultContract<I, O>, input: I, options: ActivityOptionsCompat?) {}
            }
        }
        val back = object : OnBackPressedDispatcherOwner {
            override val onBackPressedDispatcher = OnBackPressedDispatcher()
            override val lifecycle: Lifecycle = owner.lifecycle
        }
        CompositionLocalProvider(LocalActivityResultRegistryOwner provides registry, LocalOnBackPressedDispatcherOwner provides back) { content() }
    }

    @Test fun splash() = shot(dark = true) { SplashScreen(static = true) }
    @Test fun welkom() = shot { WelcomeScreen() }
    @Test fun scannen() = shot { MainTabs(Demo.business, "scan") }
    @Test fun scanResultaat() = shot { ScanResultContent(Demo.business, Demo.scan) {} }
    @Test fun scanResultaatDonker() = shot(dark = true) { ScanResultContent(Demo.business, Demo.scan.copy(stamps = 10, canRedeem = true)) {} }
    @Test fun kaarten() = shot { MainTabs(Demo.business, "cards") }
    @Test fun kaartBewerken() = shot { CardEditorSheet(Demo.business, Demo.business.cards[0]) {} }
    @Test fun kaartDelen() = shot { CardShareSheet(Demo.business, Demo.business.cards[0]) {} }
    @Test fun overzicht() = shot { MainTabs(Demo.business, "overview") }
    @Test fun overzichtDonker() = shot(dark = true) { MainTabs(Demo.business, "overview") }
    @Test fun logboek() = shot { LogScreen(Demo.business) {} }
    @Test fun medewerkers() = shot { MainTabs(Demo.business, "staff") }
    @Test fun uitnodiging() = shot { InviteStaffSheet(Demo.business, StaffInvite("ABCDEFGHJK23456789MN", "https://pasr.nl/zakelijk/uitnodiging/#ABCDEFGHJK23456789MN")) {} }
    @Test fun instellingen() = shot { MainTabs(Demo.business, "settings") }
    @Test fun wachtOpGoedkeuring() = shot { PendingScreen(Demo.business.copy(status = app.lrvdlinden.pasrzakelijk.data.BusinessStatus.pending)) }
}
