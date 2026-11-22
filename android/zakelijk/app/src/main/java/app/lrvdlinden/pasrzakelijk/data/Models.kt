package app.lrvdlinden.pasrzakelijk.data

import java.util.Date
import java.util.UUID

enum class BusinessRole { owner, staff;
    companion object { fun of(s: String?, fallback: BusinessRole = owner) = entries.firstOrNull { it.name == s?.lowercase() } ?: fallback }
}

enum class BusinessStatus { pending, approved, blocked;
    companion object { fun of(s: String?) = entries.firstOrNull { it.name == s?.lowercase() } ?: pending }
}

/** Een stempelkaart van de zaak. */
data class BusinessCard(
    val id: String = "",
    val name: String = "",
    val logo: String? = null,
    val color: String = "#6A5CFF",
    /** Tekstkleur op de kaart ("#FFFFFF"/"#000000"); null = automatisch op contrast. */
    val textColor: String? = null,
    val stampsTotal: Int = 10,
    val reward: String = "",
    val published: Boolean = false,
    val members: Int = 0,
    val stamps: Int = 0,
    val rewards: Int = 0,
) {
    /** Link en QR-code waarmee klanten zich aanmelden. */
    val joinURL: String get() = "https://pasr.nl/zakelijk/kaart/#$id"

    companion object {
        fun from(j: J): BusinessCard? {
            val id = j.string("id", "card_id") ?: return null
            return BusinessCard(
                id = id, name = j.string("name") ?: "", logo = j.string("logo"), color = j.string("color") ?: "#6A5CFF",
                textColor = j.string("text_color"), stampsTotal = j.int("stamps_total") ?: 10, reward = j.string("reward") ?: "",
                published = j.bool("published") ?: false, members = j.int("members", "members_count") ?: 0,
                stamps = j.int("stamps") ?: 0, rewards = j.int("rewards") ?: 0,
            )
        }
    }
}

/** Een zaak waar je eigenaar of medewerker van bent. */
data class Business(
    val id: String,
    val name: String,
    val city: String = "",
    val email: String = "",
    val website: String? = null,
    val note: String? = null,
    val status: BusinessStatus = BusinessStatus.pending,
    val role: BusinessRole = BusinessRole.owner,
    val cooldownMinutes: Int = 5,
    val maxPerScan: Int = 10,
    /** Vindbaar in de lijst met stempelkaarten in Pasr (standaard aan), met adres en plek voor "In de buurt". */
    val listed: Boolean = true,
    val address: String = "",
    val lat: Double? = null,
    val lng: Double? = null,
    val cards: List<BusinessCard> = emptyList(),
) {
    val isOwner get() = role == BusinessRole.owner
    val isApproved get() = status == BusinessStatus.approved

    companion object {
        /** Leest zowel {business:{…}, cards:[…], role} als een platte zaak met role en cards. */
        fun from(j: J, fallbackRole: BusinessRole = BusinessRole.owner): Business? {
            val b = j.obj("business") ?: j
            val id = b.string("id", "business_id") ?: return null
            val settings = j.obj("settings") ?: b.obj("settings")
            val list = j.array("cards").ifEmpty { b.array("cards") }
            return Business(
                id = id,
                name = b.string("name", "business_name") ?: "",
                city = b.string("city") ?: "",
                email = b.string("email") ?: "",
                website = b.string("website"),
                note = b.string("note"),
                status = BusinessStatus.of(b.string("status") ?: j.string("status")),
                role = BusinessRole.of(j.string("role") ?: b.string("role"), fallbackRole),
                cooldownMinutes = j.int("cooldown_minutes") ?: b.int("cooldown_minutes") ?: settings?.int("cooldown_minutes") ?: 5,
                maxPerScan = j.int("max_per_scan") ?: b.int("max_per_scan") ?: settings?.int("max_per_scan") ?: 10,
                listed = j.bool("listed") ?: b.bool("listed") ?: settings?.bool("listed") ?: true,
                address = j.string("address") ?: b.string("address") ?: settings?.string("address") ?: "",
                lat = j.double("lat") ?: b.double("lat"),
                lng = j.double("lng") ?: b.double("lng"),
                cards = list.mapNotNull { BusinessCard.from(it) },
            )
        }
    }
}

/** Wat de scanner over een klantcode weet. */
data class ScanResult(
    val code: String,
    val suffix: String,
    val business: String?,
    val cardName: String,
    val color: String,
    val textColor: String?,
    val logo: String?,
    val stampsTotal: Int,
    val reward: String,
    val stamps: Int,
    val rewardsRedeemed: Int,
    val lastStampAt: Date?,
    val cooldownUntil: Date?,
    /** Id van het laatste stempel/inwisseling dat nog ongedaan kan (bij scannen) of van de actie die je net deed. */
    val undoEventID: String?,
    val maxPerScan: Int?,
    val canRedeem: Boolean?,
) {
    val isFull get() = canRedeem ?: (stamps >= stampsTotal)

    companion object {
        fun from(any: Any?, code: String): ScanResult? {
            val j = J.of(any) ?: return null
            val status = j.string("status")
            if (status != null && status != "ok" && !j.has("card") && !j.has("stamps")) return null
            val card = j.obj("card")
            var undo = if (j.has("can_undo_event_id")) j.string("can_undo_event_id") else j.string("event_id")
            if (j.has("undone")) undo = j.string("can_undo_event_id")
            return ScanResult(
                code = code,
                suffix = j.string("member_code_suffix", "suffix") ?: (j.string("member_code") ?: code).takeLast(4),
                business = card?.string("business") ?: j.string("business", "business_name"),
                cardName = card?.string("name") ?: j.string("name", "card_name") ?: "",
                color = card?.string("color") ?: j.string("color") ?: "#6A5CFF",
                textColor = card?.string("text_color"),
                logo = card?.string("logo") ?: j.string("logo"),
                stampsTotal = card?.int("stamps_total") ?: j.int("stamps_total") ?: 10,
                reward = card?.string("reward") ?: j.string("reward") ?: "",
                stamps = j.int("stamps", "stamps_count") ?: 0,
                rewardsRedeemed = j.int("rewards_redeemed") ?: 0,
                lastStampAt = j.date("last_stamp_at"),
                cooldownUntil = j.date("cooldown_until"),
                undoEventID = undo,
                maxPerScan = j.int("max_per_scan"),
                canRedeem = j.bool("can_redeem"),
            )
        }
    }
}

/** Medewerker (of eigenaar) van een zaak. */
data class StaffMember(
    val id: String,
    val name: String,
    val email: String,
    val role: BusinessRole,
    val createdAt: Date?,
    val revoked: Boolean,
    val pending: Boolean,
    val expired: Boolean,
) {
    companion object {
        fun from(j: J): StaffMember? {
            val id = j.string("id", "staff_id") ?: return null
            return StaffMember(
                id = id, name = j.string("name") ?: "", email = j.string("email", "invited_email") ?: "",
                role = BusinessRole.of(j.string("role") ?: "staff", BusinessRole.staff), createdAt = j.date("created_at"),
                revoked = j.bool("revoked") ?: j.has("revoked_at"), pending = j.bool("pending") ?: false,
                expired = j.bool("expired") ?: false,
            )
        }
    }
}

/** Uitnodiging: code en link om te delen. */
data class StaffInvite(val code: String, val link: String) {
    companion object {
        fun from(any: Any?): StaffInvite? {
            val j = J.of(any) ?: return null
            val code = j.string("invite_code", "code") ?: return null
            return StaffInvite(code, j.string("link", "url") ?: "https://pasr.nl/zakelijk/uitnodiging/#$code")
        }
    }
}

/** Eén regel uit het logboek. */
data class LogEvent(
    val id: String,
    val kind: String,
    val amount: Int,
    val at: Date?,
    val who: String,
    val card: String,
    val member: String,
    val device: String?,
    val byRole: String,
    val undone: Boolean,
) {
    companion object {
        fun from(j: J) = LogEvent(
            id = j.string("id", "event_id") ?: UUID.randomUUID().toString(),
            kind = (j.string("kind", "type") ?: "").lowercase(),
            amount = j.int("amount") ?: 1,
            at = j.date("at", "created_at"),
            who = j.string("by_name", "who", "staff_name", "by_email", "email") ?: "",
            card = j.string("card", "card_name") ?: (j.obj("card")?.string("name") ?: ""),
            member = j.string("member_suffix", "member_code_suffix", "member", "code") ?: "",
            device = j.string("device"),
            byRole = j.string("by_role") ?: "",
            undone = j.bool("undone") ?: false,
        )
    }
}

/** Cijfers van één dag. */
data class DayStat(val day: Date, val stamps: Int = 0, val rewards: Int = 0, val joins: Int = 0) {
    companion object {
        fun from(j: J): DayStat? {
            val day = j.date("day", "date") ?: return null
            return DayStat(day, j.int("stamps") ?: 0, j.int("rewards", "redeems") ?: 0, j.int("joins", "new_members", "members") ?: 0)
        }
    }
}

/** Lid van een kaart (alleen de laatste tekens van de code). */
data class MemberRow(
    val id: String,
    val code: String,
    val stamps: Int,
    val rewards: Int,
    val createdAt: Date?,
    val lastStampAt: Date?,
    val app: Boolean,
) {
    companion object {
        fun from(j: J, index: Int): MemberRow {
            val code = j.string("code", "member_code_suffix") ?: "…"
            return MemberRow("$index-$code", code, j.int("stamps_count", "stamps") ?: 0, j.int("rewards_redeemed", "rewards") ?: 0,
                j.date("created_at"), j.date("last_stamp_at"), j.bool("app") ?: false)
        }
    }
}
