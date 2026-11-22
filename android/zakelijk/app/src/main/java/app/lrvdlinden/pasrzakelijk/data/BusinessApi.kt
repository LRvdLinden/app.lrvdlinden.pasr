package app.lrvdlinden.pasrzakelijk.data

import android.net.Uri
import android.os.Build
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.core.LogoImage
import org.json.JSONArray
import org.json.JSONObject

/** Alle databasefuncties van Pasr Zakelijk (supabase/schema.sql, blok "zakelijk 1.0"); exact dezelfde als iOS. */
object BusinessApi {
    private fun obj(vararg pairs: Pair<String, Any?>) = JSONObject().apply {
        for ((k, v) in pairs) put(k, v ?: JSONObject.NULL)
    }

    private fun orNull(value: String?): Any = value?.takeIf { it.isNotEmpty() } ?: JSONObject.NULL

    /** Alle zaken waar je eigenaar of medewerker van bent. */
    suspend fun me(): List<Business> {
        val json = Account.rpc("pasr_business_me", JSONObject())
        if (json is JSONArray) return json.objects().mapNotNull { Business.from(it) }
        val j = J.of(json) ?: return emptyList()
        val many = j.array("businesses")
        if (many.isNotEmpty()) return many.mapNotNull { Business.from(it) }
        if (j.obj("business") != null) Business.from(j)?.let { return listOf(it) }   // oude vorm: alleen je eigen zaak
        return emptyList()
    }

    suspend fun register(name: String, city: String, website: String?, note: String?) {
        Account.rpc("pasr_business_register", obj("p_name" to name, "p_city" to city, "p_website" to orNull(website), "p_note" to orNull(note)))
    }

    // Kaarten (eigenaar)

    suspend fun saveCard(card: BusinessCard, business: Business, logoChanged: Boolean): BusinessCard? {
        val p = obj(
            "name" to card.name, "reward" to card.reward, "color" to card.color.uppercase(),
            "stamps_total" to card.stampsTotal, "published" to card.published, "business_id" to business.id,
        )
        if (card.id.isNotEmpty()) p.put("id", card.id)
        card.textColor?.let { p.put("text_color", it) }
        if (logoChanged || card.id.isEmpty()) p.put("logo", orNull(card.logo))
        val json = Account.rpc("pasr_business_card_save", obj("p_card" to p))
        return J.of(json)?.let { BusinessCard.from(it) }
    }

    suspend fun deleteCard(id: String) {
        Account.rpc("pasr_business_card_delete", obj("p_card" to id))
    }

    suspend fun members(card: String): Pair<Int, List<MemberRow>> {
        val json = Account.rpc("pasr_business_members_list", obj("p_card" to card, "p_limit" to 200))
        val j = J.of(json) ?: return 0 to emptyList()
        val rows = j.array("members").mapIndexed { i, m -> MemberRow.from(m, i) }
        return (j.int("total") ?: rows.size) to rows
    }

    data class Brand(
        val name: String?,
        val logo: String?,
        val color: String?,
        val textColor: String?,
        val source: String?,
        val serverDomain: String?,
    ) {
        /** "kapsalon-anna.nl" (van de server, anders uit de bron-URL). */
        val domain: String?
            get() {
                serverDomain?.let { return it.removePrefix("www.") }
                val host = source?.let { runCatching { Uri.parse(it).host }.getOrNull() } ?: return null
                return host.removePrefix("www.")
            }
    }

    /**
     * Huisstijl van de website van de zaak (Edge Function business-brand): naam, logo, kaartkleur, tekstkleur.
     * Lukt het niet, dan null (nooit een blokkerende fout).
     */
    suspend fun brand(business: String, url: String? = null): Brand? {
        val body = obj("business_id" to business)
        if (!url.isNullOrEmpty()) body.put("url", url)
        val json = runCatching { Account.function("business-brand", body) }.getOrNull()
        val j = J.of(json) ?: return null
        val b = j.obj("brand") ?: j
        val logo = b.string("logo")?.let { LogoImage.bitmap(it) }?.let { LogoImage.encode(it) }
        val brand = Brand(
            name = b.string("name", "site_name"), logo = logo,
            color = b.string("color", "theme_color")?.let(::hex), textColor = b.string("text_color")?.let(::hex),
            source = b.string("source_url", "url", "source"), serverDomain = b.string("domain"),
        )
        if (brand.logo == null && brand.color == null && brand.name == null) return null
        return brand
    }

    fun hex(value: String): String? {
        var s = value.trim().uppercase()
        if (!s.startsWith("#")) s = "#$s"
        if (s.length == 4) s = "#" + s.drop(1).map { "$it$it" }.joinToString("")
        return if (Regex("^#[0-9A-F]{6}$").matches(s)) s else null
    }

    // Scannen (eigenaar en medewerkers)

    suspend fun scan(code: String): ScanResult {
        val json = Account.rpc("pasr_business_scan", obj("p_code" to code))
        return ScanResult.from(json, code)
            ?: throw ApiError(L("Deze code is niet bekend. Laat de klant de kaart opnieuw tonen of typ de code over."))
    }

    suspend fun stamp(code: String, amount: Int): ScanResult? =
        ScanResult.from(Account.rpc("pasr_business_stamp", obj("p_code" to code, "p_amount" to amount, "p_device" to deviceName)), code)

    suspend fun redeem(code: String): ScanResult? =
        ScanResult.from(Account.rpc("pasr_business_redeem", obj("p_code" to code, "p_device" to deviceName)), code)

    suspend fun undo(event: String, code: String): ScanResult? =
        ScanResult.from(Account.rpc("pasr_business_undo", obj("p_event" to event, "p_device" to deviceName)), code)

    // Overzicht

    suspend fun stats(business: String, days: Int): Pair<List<DayStat>, Int?> {
        val json = Account.rpc("pasr_business_stats", obj("p_business" to business, "p_days" to days))
        if (json is JSONArray) return json.objects().mapNotNull { DayStat.from(it) } to null
        val j = J.of(json)
        return (j?.array("days", "stats")?.mapNotNull { DayStat.from(it) } ?: emptyList()) to j?.obj("totals")?.int("members")
    }

    suspend fun log(business: String, limit: Int = 200): List<LogEvent> {
        val json = Account.rpc("pasr_business_log", obj("p_business" to business, "p_limit" to limit))
        if (json is JSONArray) return json.objects().map { LogEvent.from(it) }
        return J.of(json)?.array("events", "log")?.map { LogEvent.from(it) } ?: emptyList()
    }

    // Medewerkers (eigenaar)

    suspend fun staff(business: String): List<StaffMember> {
        val json = Account.rpc("pasr_business_staff_list", obj("p_business" to business))
        if (json is JSONArray) return json.objects().mapNotNull { StaffMember.from(it) }
        return J.of(json)?.array("staff", "members")?.mapNotNull { StaffMember.from(it) } ?: emptyList()
    }

    suspend fun invite(business: String, name: String, email: String): StaffInvite {
        val json = Account.rpc("pasr_business_staff_invite", obj("p_business" to business, "p_name" to name, "p_email" to orNull(email)))
        return StaffInvite.from(json) ?: throw ApiError(L("Er ging iets mis. Probeer het opnieuw."))
    }

    data class InviteInfo(val business: String, val city: String, val role: BusinessRole)

    /** Naam van de zaak bij een uitnodigingscode (mag zonder inloggen). null als de code niet (meer) geldt. */
    suspend fun inviteInfo(code: String): InviteInfo? {
        val json = runCatching { Account.rpcAnon("pasr_business_staff_invite_info", obj("p_code" to code)) }.getOrNull()
        val j = J.of(json) ?: return null
        if (j.string("status") != "ok") return null
        val name = j.string("business") ?: return null
        return InviteInfo(name, j.string("city") ?: "", BusinessRole.of(j.string("role"), BusinessRole.staff))
    }

    /** Uitnodiging accepteren; geeft het id van de zaak terug (als de server dat meestuurt). */
    suspend fun accept(code: String): String? {
        val json = Account.rpc("pasr_business_staff_accept", obj("p_code" to code))
        val j = J.of(json) ?: return json as? String
        return j.obj("business")?.string("id") ?: j.string("business_id", "business")
    }

    suspend fun revoke(staff: String) {
        Account.rpc("pasr_business_staff_revoke", obj("p_staff" to staff))
    }

    data class Settings(
        val cooldownMinutes: Int,
        val maxPerScan: Int,
        val listed: Boolean,
        val address: String,
        val lat: Double?,
        val lng: Double?,
    )

    suspend fun saveSettings(business: String, s: Settings) {
        val settings = obj(
            "cooldown_minutes" to s.cooldownMinutes, "max_per_scan" to s.maxPerScan, "listed" to s.listed,
            "address" to s.address, "lat" to s.lat, "lng" to s.lng,
        )
        Account.rpc("pasr_business_settings_save", obj("p_business" to business, "p_settings" to settings))
    }

    /** Korte naam van dit toestel voor het logboek ("Android-telefoon", "Android-tablet"); geen persoonlijke naam. */
    var deviceName: String = "Android"
        internal set

    fun setDevice(isTablet: Boolean) {
        deviceName = if (isTablet) "Android-tablet" else "Android-telefoon"
        if (Build.FINGERPRINT?.contains("generic") == true) deviceName = "Emulator"
    }
}

/** Klantcode uit wat de camera of het toetsenbord oplevert: "PZ…", of een link met de code erin. */
object MemberCode {
    fun extract(text: String): String? {
        val t = text.trim()
        val upper = t.uppercase().replace(" ", "").replace("-", "")
        Regex("PZ[A-HJ-NP-Z2-9]{10,40}").find(upper)?.let { return it.value }
        // link met ?code= / ?lid= / #code
        if (Regex("^[a-zA-Z][a-zA-Z0-9+.-]*:").containsMatchIn(t)) {
            val uri = runCatching { Uri.parse(t) }.getOrNull() ?: return null
            val names = setOf("code", "lid", "member", "m")
            runCatching { uri.queryParameterNames }.getOrNull()?.firstOrNull { it.lowercase() in names }
                ?.let { uri.getQueryParameter(it) }?.let { plain(it) }?.let { return it }
            uri.fragment?.let { plain(it) }?.let { return it }
            return null
        }
        return plain(upper)
    }

    private fun plain(s: String): String? {
        val u = s.uppercase()
        if (u.length !in 12..48 || !Regex("^[A-Z0-9]+$").matches(u)) return null
        return u
    }
}
