package app.lrvdlinden.pasr.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

/** Waar het Pasr-account staat. Beide waarden zijn openbaar (de publishable key mag alleen wat de database toestaat). */
object AccountConfig {
    const val URL = "https://xcfuiszcfgkpbixqzrjb.supabase.co"
    const val PUBLISHABLE_KEY = "sb_publishable_wFRG_22hV_8FJUX1JcS8SQ_2JHxQlzw"
}

class PasrError(message: String, val status: Int = 0, val code: String = "", val hint: String = "") : Exception(message)

/** Kale HTTPS naar Supabase (geen SDK), zoals de iOS-app. */
object Api {
    suspend fun post(path: String, body: Any, token: String? = null, timeoutMs: Int = 20_000): Any? = withContext(Dispatchers.IO) {
        val conn = (URL("${AccountConfig.URL}/$path").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = timeoutMs
            readTimeout = timeoutMs
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("apikey", AccountConfig.PUBLISHABLE_KEY)
            if (token != null) setRequestProperty("Authorization", "Bearer $token")
        }
        try {
            conn.outputStream.use { it.write(body.toString().toByteArray()) }
            val status = conn.responseCode
            val text = (if (status in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.use { it.readText() } ?: ""
            val json: Any? = if (text.isBlank()) null else runCatching { JSONTokener(text).nextValue() }.getOrNull()
            if (status !in 200..299) {
                val o = json as? JSONObject
                val code = o?.optString("error_code").orEmpty().ifEmpty { o?.optString("code").orEmpty() }.ifEmpty { o?.optString("error").orEmpty() }
                val msg = o?.optString("msg").orEmpty().ifEmpty { o?.optString("message").orEmpty() }.ifEmpty { o?.optString("error_description").orEmpty() }
                throw friendly(status, code, msg, o?.optString("hint").orEmpty())
            }
            if (json == JSONObject.NULL) null else json
        } catch (e: IOException) {
            throw PasrError("Geen verbinding. Controleer je internet en probeer het opnieuw.")
        } finally {
            conn.disconnect()
        }
    }

    /** RPC die ook zonder account werkt; ingelogd als die gebruiker. */
    suspend fun publicRpc(name: String, body: JSONObject): Any? =
        post("rest/v1/rpc/$name", body, Account.tokenOrNull())

    suspend fun rpc(name: String, body: JSONObject): Any? =
        post("rest/v1/rpc/$name", body, Account.validToken())

    suspend fun function(name: String, body: JSONObject, signedIn: Boolean = false): JSONObject =
        (post("functions/v1/$name", body, if (signedIn) Account.validToken() else null, 30_000) as? JSONObject) ?: JSONObject()

    private fun friendly(status: Int, code: String, message: String, hint: String): PasrError {
        val s = "$code $message $hint"
        val text = when {
            code == "invalid_credentials" || (status == 400 && code == "invalid_grant") -> "E-mailadres of wachtwoord klopt niet."
            code == "email_not_confirmed" -> "Bevestig eerst je e-mailadres. Kijk in je inbox (en bij ongewenste mail)."
            code == "weak_password" -> "Kies een wachtwoord van minstens 8 tekens."
            code == "user_already_exists" || code == "email_exists" -> "Er is al een account met dit e-mailadres. Log in of vraag een nieuw wachtwoord aan."
            code == "email_address_invalid" || code == "validation_failed" -> "Dit e-mailadres klopt niet."
            status == 429 || code.startsWith("over_") || s.contains("rate_limited") -> "Te veel pogingen. Wacht een paar minuten en probeer het opnieuw."
            s.contains("P0002") && s.contains("not_found") -> "Deze stempelkaart bestaat niet (meer) of de zaak heeft hem nog niet gepubliceerd."
            s.contains("not_confirmed") -> "Bevestig eerst je e-mailadres."
            message.contains("permanent email") -> "Gebruik een vast e-mailadres; tijdelijke adressen werken niet."
            status == 404 -> "Deze functie is nog niet beschikbaar. Probeer het later opnieuw."
            else -> "Er ging iets mis. Probeer het opnieuw."
        }
        return PasrError(text, status, code, hint)
    }
}

@Serializable
data class Session(
    val accessToken: String,
    val refreshToken: String,
    val expiresAt: Long,
    val userID: String,
    val email: String,
    val firstName: String? = null,
)

/** Het optionele Pasr-account (e-mail en wachtwoord). De sessie blijft versleuteld op dit toestel. */
object Account {
    private val _session = MutableStateFlow<Session?>(null)
    val session: StateFlow<Session?> = _session.asStateFlow()
    val isSignedIn get() = _session.value != null

    fun init() {
        _session.value = Prefs.string("session")?.let { Crypto.decryptString(it) }
            ?.let { runCatching { PasrJson.decodeFromString<Session>(it) }.getOrNull() }
    }

    val deviceCountry: String?
        get() = Locale.getDefault().country.takeIf { it.length == 2 && it.all(Char::isLetter) }?.uppercase()

    fun cleanName(name: String) = name.replace(Regex("[<>]"), "").split(Regex("\\s+")).filter { it.isNotEmpty() }
        .joinToString(" ").take(40)

    /** true = meteen ingelogd, false = kijk in je inbox. */
    suspend fun signUp(firstName: String, email: String, password: String, honeypot: String, fillMs: Long): Boolean {
        val data = JSONObject().put("first_name", cleanName(firstName)).put("fill_ms", fillMs).put("app", "android")
        if (honeypot.isNotEmpty()) data.put("hp", honeypot)
        deviceCountry?.let { data.put("country", it) }
        val body = JSONObject().put("email", email.trim().lowercase()).put("password", password).put("data", data)
        val json = Api.post("auth/v1/signup?redirect_to=https%3A%2F%2Fpasr.nl%2Fbevestigen%2F", body) as? JSONObject
        if (json?.has("access_token") == true) { store(json); return true }
        return false
    }

    suspend fun signIn(email: String, password: String) {
        val json = Api.post("auth/v1/token?grant_type=password",
            JSONObject().put("email", email.trim().lowercase()).put("password", password)) as? JSONObject
        store(json ?: throw PasrError("Er ging iets mis. Probeer het opnieuw."))
    }

    suspend fun sendPasswordReset(email: String) {
        Api.post("auth/v1/recover?redirect_to=https%3A%2F%2Fpasr.nl%2Fbevestigen%2F", JSONObject().put("email", email.trim().lowercase()))
    }

    suspend fun resendConfirmation(email: String) {
        Api.post("auth/v1/resend", JSONObject().put("type", "signup").put("email", email.trim().lowercase()))
    }

    suspend fun signOut() {
        _session.value?.accessToken?.let { t -> runCatching { Api.post("auth/v1/logout?scope=local", JSONObject(), t) } }
        clear()
    }

    suspend fun deleteAccount() {
        Api.rpc("pasr_delete_account", JSONObject())
        clear()
    }

    fun clear() {
        _session.value?.userID?.let { Sync.forget(it) }
        _session.value = null
        Prefs.setString("session", null)
    }

    fun tokenOrNull(): String? = _session.value?.takeIf { it.expiresAt - nowMs() > 60_000 }?.accessToken

    suspend fun validToken(): String {
        val current = _session.value ?: throw PasrError("Je bent niet ingelogd.")
        if (current.expiresAt - nowMs() > 60_000) return current.accessToken
        try {
            val json = Api.post("auth/v1/token?grant_type=refresh_token", JSONObject().put("refresh_token", current.refreshToken)) as? JSONObject
            store(json ?: throw PasrError("Er ging iets mis."))
            return _session.value?.accessToken ?: current.accessToken
        } catch (e: PasrError) {
            if (e.status == 400 || e.status == 401) {
                clear()
                throw PasrError("Je bent uitgelogd. Log opnieuw in.")
            }
            throw e
        }
    }

    private fun store(json: JSONObject) {
        val user = json.optJSONObject("user") ?: throw PasrError("Er ging iets mis. Probeer het opnieuw.")
        val meta = user.optJSONObject("user_metadata")
        val s = Session(
            accessToken = json.getString("access_token"),
            refreshToken = json.getString("refresh_token"),
            expiresAt = nowMs() + json.optLong("expires_in", 3600) * 1000,
            userID = user.getString("id"),
            email = user.optString("email").ifEmpty { _session.value?.email.orEmpty() },
            firstName = meta?.optString("first_name")?.takeIf { it.isNotEmpty() } ?: _session.value?.firstName,
        )
        _session.value = s
        Prefs.setString("session", Crypto.encryptString(PasrJson.encodeToString(s)))
    }
}

fun JSONObject.str(vararg keys: String): String? {
    for (k in keys) { val v = opt(k); if (v is String && v.isNotBlank()) return v }
    return null
}

fun JSONObject.int(vararg keys: String): Int? {
    for (k in keys) {
        when (val v = opt(k)) {
            is Number -> return v.toInt()
            is String -> v.toIntOrNull()?.let { return it }
        }
    }
    return null
}

fun JSONArray.objects(): List<JSONObject> = (0 until length()).mapNotNull { optJSONObject(it) }
