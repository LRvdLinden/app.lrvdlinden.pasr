package app.lrvdlinden.pasrzakelijk

import android.app.Application
import android.content.res.Configuration
import app.lrvdlinden.pasrzakelijk.core.I18n
import app.lrvdlinden.pasrzakelijk.core.Prefs
import app.lrvdlinden.pasrzakelijk.core.SecureStore
import app.lrvdlinden.pasrzakelijk.data.Account
import app.lrvdlinden.pasrzakelijk.data.BusinessApi
import app.lrvdlinden.pasrzakelijk.data.BusinessStore
import app.lrvdlinden.pasrzakelijk.data.DeviceRegistry

class PasrZakelijkApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        I18n.update(resources.configuration.locales[0])
        Prefs.init(this)
        SecureStore.init(this)
        DeviceRegistry.init(this)
        Account.restore()
        BusinessStore.restore()
        BusinessApi.setDevice(resources.configuration.smallestScreenWidthDp >= 600)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        I18n.update(newConfig.locales[0])
    }
}
