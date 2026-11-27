package app.lrvdlinden.pasrzakelijk.data

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.lrvdlinden.pasrzakelijk.core.Prefs

/** De zaken van de ingelogde gebruiker en welke er gekozen is (zaakkiezer bovenin). */
object BusinessStore {
    var businesses by mutableStateOf<List<Business>>(emptyList())
        private set
    var loaded by mutableStateOf(false)
        private set
    var loading by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
    /** Uitnodigingscode uit een link (pasrzakelijk://uitnodiging#code of pasr.nl/zakelijk/uitnodiging/#code). */
    var pendingInvite by mutableStateOf<String?>(null)

    var selectedID by mutableStateOf("")
        private set

    fun restore() { selectedID = Prefs.string("business.selected") }

    val current: Business? get() = businesses.firstOrNull { it.id == selectedID } ?: businesses.firstOrNull()

    fun select(id: String) {
        selectedID = id
        Prefs.putString("business.selected", id)
    }

    suspend fun load() {
        if (!Account.isSignedIn) return
        loading = true
        try {
            businesses = BusinessApi.me().sortedWith(compareBy({ if (it.role == BusinessRole.owner) 0 else 1 }, { it.name.lowercase() }))
            if (businesses.none { it.id == selectedID }) select(businesses.firstOrNull()?.id ?: "")
            error = null
        } catch (e: Exception) {
            error = e.message
        } finally {
            loading = false
            loaded = true
        }
    }

    fun reset() {
        businesses = emptyList()
        loaded = false
        error = null
        select("")
    }

    /** Alleen voor voorbeelden (screenshots). */
    fun demo(list: List<Business>) {
        businesses = list
        loaded = true
        selectedID = list.firstOrNull()?.id ?: ""
    }

    /** Een link uit de browser, berichten of de camera. */
    /** Kent de app deze link zelf (uitnodiging voor medewerkers)? */
    fun isAppLink(uri: Uri): Boolean {
        val host = uri.host ?: ""
        val path = uri.path ?: ""
        return (uri.scheme == "pasrzakelijk" && (host == "uitnodiging" || path.contains("uitnodiging")))
            || (host.endsWith("pasr.nl") && path.contains("/zakelijk/uitnodiging"))
    }

    fun handle(uri: Uri?) {
        uri ?: return
        if (!isAppLink(uri)) return
        // uitnodiging voor een gezamenlijke actie: https://pasr.nl/zakelijk/uitnodiging/?t=TOKEN
        CommunityRouter.token(uri)?.let { CommunityRouter.pendingToken = it; return }
        val code = (uri.fragment ?: runCatching { uri.getQueryParameter("code") }.getOrNull())?.trim()
        if (!code.isNullOrEmpty() && code.length <= 80) pendingInvite = code
    }
}
