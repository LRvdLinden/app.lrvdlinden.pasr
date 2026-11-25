package app.lrvdlinden.pasr.data

import android.content.Context
import app.lrvdlinden.pasr.notify.Reminders
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.MonthDay
import java.time.LocalTime

object Birthday {
    private const val VALUE = "birthday.value"
    private const val CHANGED = "birthday.changed"
    private const val PUSHED = "birthday.pushed"

    private fun scoped(key: String, user: String? = Account.session.value?.userID) = "$key.${user ?: "local"}"

    fun value(): MonthDay? = Prefs.string(scoped(VALUE))?.let { runCatching { MonthDay.parse(it) }.getOrNull() }

    fun set(day: MonthDay?) {
        Prefs.setString(scoped(VALUE), day?.toString())
        Prefs.setLong(scoped(CHANGED), nowMs())
    }

    suspend fun sync() {
        val user = Account.session.value?.userID ?: return
        val changed = Prefs.long(scoped(CHANGED))
        if (changed > Prefs.long(scoped(PUSHED))) {
            val birthday = value()
            Api.rpc("pasr_birthday_set", JSONObject()
                .put("p_day", birthday?.dayOfMonth ?: JSONObject.NULL)
                .put("p_month", birthday?.monthValue ?: JSONObject.NULL))
            if (Account.session.value?.userID == user) Prefs.setLong(scoped(PUSHED), changed)
            return
        }
        val remote = when (val result = Api.rpc("pasr_birthday_get", JSONObject())) {
            is JSONObject -> result
            is JSONArray -> result.optJSONObject(0)
            else -> null
        } ?: return
        val stamp = parseIso(remote.str("updated_at")) ?: return
        if (stamp > Prefs.long(scoped(CHANGED)) && Account.session.value?.userID == user) {
            val birthday = runCatching { MonthDay.of(remote.getInt("month"), remote.getInt("day")) }.getOrNull()
            Prefs.setString(scoped(VALUE), birthday?.toString())
            Prefs.setLong(scoped(CHANGED), stamp)
            Prefs.setLong(scoped(PUSHED), stamp)
        }
    }

    fun perk(card: Card): String? = (Catalog.template(card.templateID)
        ?: Catalog.search(card.storeName, card.kind).firstOrNull { Catalog.fold(it.name) == Catalog.fold(card.storeName) })
        ?.guide?.str("birthday")?.takeIf { it.isNotBlank() }

    fun notifyIfDue(context: Context) {
        val birthday = value() ?: return
        val today = LocalDate.now()
        if (today.monthValue != birthday.monthValue ||
            today.dayOfMonth > birthday.atYear(today.year).dayOfMonth ||
            LocalTime.now().hour < 10 || !Reminders.canNotify(context)) return
        val perks = CardStore.visible.mapNotNull { card -> perk(card)?.let { card to it } }
            .distinctBy { it.first.templateID ?: it.first.storeName.lowercase() }.sortedBy { it.first.storeName.lowercase() }
        if (perks.isEmpty()) return
        val key = scoped("birthday.notified.${today.year}.${today.monthValue}")
        if (Prefs.bool(key)) return
        val first = perks.singleOrNull()
        val stores = perks.take(3).joinToString { it.first.storeName }
        val more = if (perks.size > 3) " en ${perks.size - 3} meer" else ""
        val body = first?.let { "${it.first.storeName}: ${it.second}" }
            ?: "Je hebt verjaardagsvoordeel bij $stores$more. Bekijk het bij de kaart onder Details."
        Reminders.notify(context, key, Reminders.CHANNEL, "Het is bijna je verjaardag", body, first?.first?.id)
        Prefs.setBool(key, true)
    }
}

object ReminderPreferences {
    var expiry: Boolean
        get() = Prefs.p.getBoolean("reminders.expiry", true)
        set(value) = Prefs.setBool("reminders.expiry", value)
    var balance: Boolean
        get() = Prefs.p.getBoolean("reminders.balance", true)
        set(value) = Prefs.setBool("reminders.balance", value)
    var interval: String
        get() = Prefs.string("reminders.interval") ?: "month"
        set(value) = Prefs.setString("reminders.interval", value)
    var channel: String
        get() = if (Account.isSignedIn) Prefs.string("reminders.channel.${Account.session.value?.userID}") ?: "push" else "push"
        set(value) = Prefs.setString("reminders.channel.${Account.session.value?.userID}", value)

    suspend fun refresh() {
        val result = Api.rpc("pasr_mail_prefs_get", JSONObject()) as? JSONObject ?: return
        channel = if (result.optBoolean("enabled")) if (channel == "mail") "mail" else "both" else "push"
    }

    suspend fun save(selected: String = channel) {
        if (!Account.isSignedIn) return
        Api.rpc("pasr_mail_prefs_set", JSONObject().put("p_enabled", selected != "push")
            .put("p_expiry", expiry).put("p_balance", balance).put("p_interval", interval)
            .put("p_tz", java.time.ZoneId.systemDefault().id))
    }
}
