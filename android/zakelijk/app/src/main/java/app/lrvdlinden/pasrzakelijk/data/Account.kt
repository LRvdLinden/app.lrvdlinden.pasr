package app.lrvdlinden.pasrzakelijk.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.core.SecureStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.json.JSONTokener
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Waar het Pasr-account woont. Beide waarden zijn openbaar (de publishable key mag alleen wat de database-regels
 * toestaan); zelfde server als de app Pasr en de iOS-app Pasr Zakelijk. Geen geheimen in de app.
 */
object AccountConfig {
    const val URL = "https://xcfuiszcfgkpbixqzrjb.supabase.co"
    const val PUBLISHABLE_KEY = "sb_publishable_wFRG_22hV_8FJUX1JcS8SQ_2JHxQlzw"
}

/** Fout met een nette tekst voor in beeld. */
class ApiError(message: String, val status: Int = 0) : Exception(message)

/**
 * Het Pasr-account van de ondernemer of medewerker (e-mail en wachtwoord, zelfde account als in Pasr en op
 * pasr.nl/zakelijk). Gewone HTTPS, geen SDK. De sessie staat alleen op dit toestel, versleuteld.
 */
object Account {
    data class Session(
        val accessToken: String,
        val refreshToken: String,
        val expiresAt: Long,
        val userID: String,
        val email: String,
        val firstName: String?,
    ) {
        fun toJson(): String = JSONObject()
            .put("accessToken", accessToken).put("refreshToken", refreshToken).put("expiresAt", expiresAt)
            .put("userID", userID).put("email", email).put("firstName", firstName ?: JSONObject.NULL).toString()

        companion object {
            fun fromJson(s: String): Session? = runCatching {
                val j = JSONObject(s)
                Session(j.getString("accessToken"), j.getString("refreshToken"), j.getLong("expiresAt"),
                    j.getString("userID"), j.optString("email"), j.optString("firstName").takeIf { it.isNotEmpty() && it != "null" })
            }.getOrNull()
        }
    }

    enum class SignUpResult { SignedIn, CheckInbox }

    var session by mutableStateOf<Session?>(null)
        private set
    val isSignedIn: Boolean get() = session != null

    private val refreshLock = Mutex()

    fun restore() {
        session = SecureStore.load("session")?.let { Session.fromJson(it) }
    }

    /** Alleen voor voorbeelden (screenshots). */
    fun demo(email: String) {
        session = Session("demo", "demo", Long.MAX_VALUE, "demo", email, "Anna")
    }

    // Inloggen

    suspend fun signIn(email: String, password: String) {
        val json = request("auth/v1/token?grant_type=password", JSONObject().put("email", clean(email)).put("password", password))
        store(json as? JSONObject)
    }

    suspend fun signUp(firstName: String, email: String, password: String, honeypot: String, fillMilliseconds: Long): SignUpResult {
        val data = JSONObject().put("first_name", cleanName(firstName)).put("fill_ms", fillMilliseconds).put("app", "zakelijk-android")
        if (honeypot.isNotEmpty()) data.put("hp", honeypot)
        val body = JSONObject().put("email", clean(email)).put("password", password).put("data", data)
        val json = request("auth/v1/signup?redirect_to=https%3A%2F%2Fpasr.nl%2Fbevestigen%2F", body) as? JSONObject
        if (json?.has("access_token") == true) {
            store(json)
            return SignUpResult.SignedIn
        }
        return SignUpResult.CheckInbox
    }

    /** Lukt altijd (de server zegt nooit of een adres een account heeft). */
    suspend fun sendPasswordReset(email: String) {
        request("auth/v1/recover?redirect_to=https%3A%2F%2Fpasr.nl%2Fbevestigen%2F", JSONObject().put("email", clean(email)))
    }

    suspend fun resendConfirmation(email: String) {
        request("auth/v1/resend", JSONObject().put("type", "signup").put("email", clean(email)))
    }

    suspend fun signOut() {
        session?.accessToken?.let { token -> runCatching { request("auth/v1/logout?scope=local", JSONObject(), token) } }
        clear()
    }

    /** Verwijdert het Pasr-account (ook je zaak als je eigenaar bent). Zelfde functie als in Pasr. */
    suspend fun deleteAccount() {
        rpc("pasr_delete_account", JSONObject())
        DeviceRegistry.unregister()
        clear()
    }

    fun clear() {
        session = null
        SecureStore.delete("session")
    }

    // Database

    /** Roept een databasefunctie aan (POST /rest/v1/rpc/<naam>) als de ingelogde gebruiker. */
    suspend fun rpc(name: String, body: JSONObject): Any? = request("rest/v1/rpc/$name", body, validAccessToken())

    /** Zonder inloggen (alleen functies die anon toestaan). */
    suspend fun rpcAnon(name: String, body: JSONObject): Any? = request("rest/v1/rpc/$name", body, session?.accessToken)

    /** Roept een Edge Function aan (POST /functions/v1/<naam>) als de ingelogde gebruiker. */
    suspend fun function(name: String, body: JSONObject): Any? = request("functions/v1/$name", body, validAccessToken())

    private suspend fun validAccessToken(): String = refreshLock.withLock {
        val current = session ?: throw ApiError(L("Je bent niet ingelogd."))
        if (current.expiresAt - System.currentTimeMillis() > 60_000) return current.accessToken
        try {
            val json = request("auth/v1/token?grant_type=refresh_token", JSONObject().put("refresh_token", current.refreshToken))
            store(json as? JSONObject)
            session?.accessToken ?: current.accessToken
        } catch (e: ApiError) {
            if (e.status == 400 || e.status == 401) {
                clear()
                throw ApiError(L("Je bent uitgelogd. Log opnieuw in."))
            }
            throw e
        }
    }

    // HTTP

    private suspend fun request(path: String, body: JSONObject, token: String? = null): Any? = withContext(Dispatchers.IO) {
        val conn = (URL("${AccountConfig.URL}/$path").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 20_000
            readTimeout = 20_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("apikey", AccountConfig.PUBLISHABLE_KEY)
            if (token != null) setRequestProperty("Authorization", "Bearer $token")
        }
        val status: Int
        val text: String
        try {
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            status = conn.responseCode
            text = (if (status in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.use { it.readText() } ?: ""
        } catch (e: IOException) {
            throw ApiError(L("Geen verbinding. Controleer je internet en probeer het opnieuw."))
        } finally {
            conn.disconnect()
        }
        val json: Any? = if (text.isBlank()) JSONObject() else runCatching { JSONTokener(text).nextValue() }.getOrNull() ?: JSONObject()
        if (status !in 200..299) {
            val d = json as? JSONObject ?: JSONObject()
            fun s(vararg k: String) = k.firstNotNullOfOrNull { key -> d.optString(key).takeIf { d.has(key) && it.isNotEmpty() && it != "null" } } ?: ""
            throw ApiErrors.from(status, s("error_code", "code", "error"), s("msg", "message", "error_description"), s("hint"), s("details"))
        }
        json
    }

    private fun store(json: JSONObject?) {
        val access = json?.optString("access_token")?.takeIf { it.isNotEmpty() }
        val refresh = json?.optString("refresh_token")?.takeIf { it.isNotEmpty() }
        val user = json?.optJSONObject("user")
        val id = user?.optString("id")?.takeIf { it.isNotEmpty() }
        if (access == null || refresh == null || id == null) throw ApiError(L("Er ging iets mis. Probeer het opnieuw."))
        val expires = json.optDouble("expires_in", 3600.0).takeIf { !it.isNaN() } ?: 3600.0
        val meta = user.optJSONObject("user_metadata")
        val new = Session(
            accessToken = access, refreshToken = refresh,
            expiresAt = System.currentTimeMillis() + (expires * 1000).toLong(),
            userID = id,
            email = user.optString("email").takeIf { it.isNotEmpty() } ?: session?.email ?: "",
            firstName = meta?.optString("first_name")?.takeIf { it.isNotEmpty() } ?: session?.firstName,
        )
        session = new
        SecureStore.save("session", new.toJson())
    }

    fun clean(email: String) = email.trim().lowercase()

    fun cleanName(name: String): String =
        name.replace(Regex("[<>]"), "").split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ").take(40)
}

/** Nette teksten bij wat de server zegt (zelfde regels als APIError.from in de iOS-app). */
object ApiErrors {
    fun from(status: Int, code: String, message: String, hint: String = "", details: String = ""): ApiError {
        hintText(hint, details)?.let { return ApiError(it, status) }
        val s = "$code $message"
        fun has(k: String) = s.contains(k, ignoreCase = true)
        val text = when {
            has("invalid_credentials") || (status == 400 && code == "invalid_grant") -> L("E-mailadres of wachtwoord klopt niet.")
            has("email_not_confirmed") || has("not_confirmed") -> L("Bevestig eerst je e-mailadres. Kijk in je inbox (en bij ongewenste mail).")
            has("weak_password") -> L("Kies een wachtwoord van minstens 8 tekens.")
            has("user_already_exists") || has("email_exists") -> L("Er is al een account met dit e-mailadres. Log in of vraag een nieuw wachtwoord aan.")
            has("email_address_invalid") || has("validation_failed") -> L("Dit e-mailadres klopt niet.")
            status == 429 || has("rate_limit") -> L("Te veel pogingen. Wacht een paar minuten en probeer het opnieuw.")
            hintText(message.trim(), details) != null -> hintText(message.trim(), details)!!
            code == "P0002" -> L("Deze code is niet bekend. Laat de klant de kaart opnieuw tonen of typ de code over.")
            code == "28000" -> L("Je bent uitgelogd. Log opnieuw in.")
            message.length > 12 && message.contains(" ") && !Regex("[a-z]+_[a-z]+").containsMatchIn(message) -> message
            else -> L("Er ging iets mis. Probeer het opnieuw.")
        }
        return ApiError(text, status)
    }

    fun hintText(hint: String, details: String): String? = when (hint) {
        "cooldown" -> {
            val seconds = details.trim().toIntOrNull()
            if (seconds != null && seconds > 0) {
                val minutes = maxOf(1, Math.ceil(seconds / 60.0).toInt())
                L("Deze klant kreeg net al een stempel. Probeer het over %lld min opnieuw.", minutes)
            } else L("Deze klant kreeg net al een stempel. Probeer het straks opnieuw.")
        }
        "too_many", "bad_amount" -> L("Zoveel stempels tegelijk mag niet. Pas het maximum aan in Instellingen.")
        "too_soon" -> L("Net al gescand. Wacht een paar seconden.")
        "not_approved" -> L("Je zaak is nog niet goedgekeurd. Stempels zetten kan pas daarna.")
        "not_allowed", "not_owner" -> L("Dit mag je niet (meer) bij deze zaak. Vraag de eigenaar.")
        "not_found" -> L("Deze code is niet bekend. Laat de klant de kaart opnieuw tonen of typ de code over.")
        "other_business" -> L("Deze kaart hoort bij een andere zaak.")
        "not_enough" -> L("De kaart is nog niet vol. Inwisselen kan pas bij een volle kaart.")
        "undo_expired" -> L("Ongedaan maken kan alleen binnen 2 minuten.")
        "undo_not_latest" -> L("Alleen de laatste actie bij deze klant kan ongedaan worden gemaakt.")
        "invite_invalid" -> L("Deze uitnodiging bestaat niet (meer). Vraag de eigenaar om een nieuwe.")
        "invite_own" -> L("Dit is een uitnodiging voor je eigen zaak.")
        "staff_limit" -> L("Je hebt al 25 medewerkers. Trek er eerst één in.")
        "bad_settings" -> L("Deze instellingen kloppen niet.")
        "bad_name" -> L("Vul een naam in.")
        "bad_email" -> L("Dit e-mailadres klopt niet.")
        "bad_reward" -> L("Vul de beloning in.")
        "bad_logo" -> L("Dit logo is te groot of geen afbeelding. Kies een kleinere afbeelding.")
        "card_limit" -> L("Je hebt al 5 kaarten. Verwijder er eerst één.")
        "blocked" -> L("Deze zaak is geblokkeerd. Neem contact op met Pasr.")
        "not_confirmed" -> L("Bevestig eerst je e-mailadres. Kijk in je inbox (en bij ongewenste mail).")
        "owner_taken" -> L("Dit account is al eigenaar van een andere zaak. Log in met een ander account.")
        "not_signed_in", "not signed in" -> L("Je bent uitgelogd. Log opnieuw in.")
        "rate_limited" -> L("Te veel pogingen. Wacht een paar minuten en probeer het opnieuw.")
        else -> null
    }
}
