package app.lrvdlinden.pasrzakelijk.data

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray

/**
 * Uitnodigingen voor gezamenlijke acties (zelfde opzet als CommunityRouter op iOS): wat er vanuit een melding of link
 * geopend moet worden, en hoeveel openstaande uitnodigingen de zaak heeft (badge bij Acties en Samenwerken).
 */
object CommunityRouter {
    /** Pushtypes die naar Samenwerken gaan (payload `type` met `campaign`). */
    val pushTypes = setOf("community_invite", "community_invite_answered", "community_active", "community_removed")

    data class Focus(
        val kind: String,
        val campaign: String?,
        val notice: String? = null,
        val failed: Boolean = false,
        val stamp: Long = System.nanoTime(),
    )

    /** Wat Samenwerken moet openen (melding of geaccepteerde link). */
    var focus by mutableStateOf<Focus?>(null)
    /** Token uit https://pasr.nl/zakelijk/uitnodiging/?t=TOKEN (nog niet bevestigd). */
    var pendingToken by mutableStateOf<String?>(null)
    /** Openstaande uitnodigingen voor de gekozen zaak. */
    var inviteCount by mutableIntStateOf(0)

    fun route(type: String, campaign: String?) {
        if (type !in pushTypes) return
        focus = Focus(type, campaign?.takeIf { it.isNotBlank() })
    }

    suspend fun refreshCount(business: Business) {
        if (!business.isOwner) { inviteCount = 0; return }
        val result = runCatching {
            Account.rpc("pasr_business_community_my_invites", org.json.JSONObject().put("p_business", business.id))
        }.getOrNull() ?: return
        inviteCount = (result as? JSONArray)?.length() ?: 0
    }

    /** Token uit een uitnodigingslink, of null als dit geen link voor een gezamenlijke actie is. */
    fun token(uri: Uri): String? =
        runCatching { uri.getQueryParameter("t") }.getOrNull()?.trim()?.takeIf { it.isNotEmpty() && it.length <= 200 }
}
