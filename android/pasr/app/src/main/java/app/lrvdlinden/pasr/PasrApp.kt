package app.lrvdlinden.pasr

import android.app.Application
import app.lrvdlinden.pasr.data.Account
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.Catalog
import app.lrvdlinden.pasr.data.Prefs
import app.lrvdlinden.pasr.notify.Reminders

class PasrApp : Application() {
    override fun onCreate() {
        super.onCreate()
        app.lrvdlinden.pasr.ui.appContext = this
        Prefs.init(this)
        CardStore.init(this)
        app.lrvdlinden.pasr.data.ReceiptStore.init(this)
        Account.init()
        Catalog.init(this)
        Reminders.setup(this)
    }
}
