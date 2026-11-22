package app.lrvdlinden.pasrzakelijk.core

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Instellingen van dit toestel (weergave, slot, gekozen zaak en tabblad). Werkt ook zonder Context (voorbeelden). */
object Prefs {
    private var prefs: SharedPreferences? = null

    fun init(context: Context) {
        prefs = context.getSharedPreferences("ui", Context.MODE_PRIVATE)
        appearance = prefs?.getString("ui.appearance", "system") ?: "system"
        appLock = prefs?.getBoolean("security.appLock", false) ?: false
    }

    /** "system", "light" of "dark". */
    var appearance by mutableStateOf("system")
        private set
    var appLock by mutableStateOf(false)
        private set

    fun setAppearance(value: String) {
        appearance = value
        prefs?.edit()?.putString("ui.appearance", value)?.apply()
    }

    fun setAppLock(on: Boolean) {
        appLock = on
        prefs?.edit()?.putBoolean("security.appLock", on)?.apply()
    }

    fun string(key: String, default: String = ""): String = prefs?.getString(key, default) ?: default
    fun putString(key: String, value: String) { prefs?.edit()?.putString(key, value)?.apply() }
    fun long(key: String): Long = prefs?.getLong(key, 0L) ?: 0L
    fun putLong(key: String, value: Long) { prefs?.edit()?.putLong(key, value)?.apply() }
}
