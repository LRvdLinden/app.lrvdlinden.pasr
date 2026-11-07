import Foundation
import SwiftData
import Observation

/// Gedeelde Pasr: een groep van maximaal 6 accounts die samen kaarten bijhouden (zoals een gedeelde groep in
/// Wachtwoorden of de gedeelde bibliotheek in Foto's). Iedereen in de groep mag alles: kaarten toevoegen, wijzigen
/// en verwijderen, mensen uitnodigen of verwijderen en de naam wijzigen. Je zit in maximaal 2 groepen.
/// Uitnodigen gaat per e-mailadres; wie nog geen account heeft maakt er een met dat adres en ziet dan de uitnodiging.
@MainActor
@Observable
final class GroupService {
    static let shared = GroupService()

    struct Member: Identifiable, Equatable {
        var id: String
        var email: String
        var firstName: String?
        var isMe: Bool
        var isCreator: Bool
        var displayName: String { firstName?.isEmpty == false ? firstName! : email }
    }

    struct SentInvite: Identifiable, Equatable {
        var id: String
        var email: String
    }

    struct Group: Identifiable, Equatable {
        var id: UUID
        var name: String
        var members: [Member]
        var invites: [SentInvite]
        var cards: Int
        /// Leden plus openstaande uitnodigingen: samen maximaal `maxMembers`.
        var seatsUsed: Int { members.count + invites.count }
    }

    /// Een uitnodiging voor mij.
    struct Invite: Identifiable, Equatable {
        var id: String
        var groupID: UUID
        var groupName: String
        var from: String
        var members: Int
    }

    private(set) var groups: [Group] = []
    private(set) var invites: [Invite] = []
    private(set) var maxGroups = 2
    private(set) var maxMembers = 6
    private(set) var loaded = false
    var lastError: String?

    private var account: AccountService { .shared }
    private var syncing = false

    func group(_ id: UUID) -> Group? { groups.first { $0.id == id } }
    var canCreate: Bool { groups.count < maxGroups }

    // MARK: Ophalen

    @discardableResult
    func refresh() async -> Bool {
        guard account.isSignedIn else { reset(); return false }
        do {
            guard let json = try await account.rpc("pasr_groups", body: [:]) as? [String: Any] else { return false }
            apply(json)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func reset() {
        groups = []
        invites = []
        loaded = false
    }

    private func apply(_ json: [String: Any]) {
        if let limits = json["limits"] as? [String: Any] {
            maxGroups = limits["groups"] as? Int ?? maxGroups
            maxMembers = limits["members"] as? Int ?? maxMembers
        }
        groups = (json["groups"] as? [[String: Any]] ?? []).compactMap { g in
            guard let id = (g["id"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            let members = (g["members"] as? [[String: Any]] ?? []).map { m in
                Member(id: m["user_id"] as? String ?? UUID().uuidString, email: m["email"] as? String ?? "",
                       firstName: m["first_name"] as? String, isMe: m["me"] as? Bool ?? false,
                       isCreator: m["creator"] as? Bool ?? false)
            }
            let invites = (g["invites"] as? [[String: Any]] ?? []).map { i in
                SentInvite(id: i["id"] as? String ?? "", email: i["email"] as? String ?? "")
            }
            return Group(id: id, name: g["name"] as? String ?? "", members: members, invites: invites,
                         cards: g["cards"] as? Int ?? 0)
        }
        invites = (json["invites"] as? [[String: Any]] ?? []).compactMap { i in
            guard let id = i["id"] as? String, let group = (i["group_id"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            return Invite(id: id, groupID: group, groupName: i["group_name"] as? String ?? "",
                          from: i["from"] as? String ?? "", members: i["members"] as? Int ?? 1)
        }
        loaded = true
    }

    // MARK: Beheren (iedereen in de groep mag alles)

    func create(name: String) async throws {
        _ = try await account.rpc("pasr_group_create", body: ["p_name": name])
        await refresh()
    }

    func rename(_ group: UUID, to name: String) async throws {
        _ = try await account.rpc("pasr_group_rename", body: ["p_group": group.uuidString, "p_name": name])
        await refresh()
    }

    /// Maakt de uitnodiging en stuurt de mail. Geeft terug of de mail is verstuurd.
    func invite(_ email: String, to group: UUID) async throws -> Bool {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result = try await account.function("group-invite", body: ["group": group.uuidString, "email": address])
        await refresh()
        return result["mailed"] as? Bool ?? false
    }

    func cancelInvite(_ invite: String) async throws {
        _ = try await account.rpc("pasr_group_cancel_invite", body: ["p_invite": invite])
        await refresh()
    }

    func respond(_ invite: Invite, accept: Bool, in context: ModelContext) async throws {
        _ = try await account.rpc("pasr_invite_respond", body: ["p_invite": invite.id, "p_accept": accept])
        invites.removeAll { $0.id == invite.id }
        if accept { await sync(in: context) } else { await refresh() }
    }

    /// Iemand uit de groep halen. Zonder `member`: zelf de groep verlaten. Met `keepCopies` blijven de kaarten
    /// als privékaarten op je apparaten staan (de anderen houden de gedeelde kaarten gewoon).
    func remove(_ member: Member? = nil, from group: UUID, keepCopies: Bool = false, in context: ModelContext) async throws {
        var body: [String: Any] = ["p_group": group.uuidString]
        if let member { body["p_user"] = member.id } else { body["p_user"] = NSNull() }
        if member == nil, keepCopies {
            let all = (try? context.fetch(FetchDescriptor<Card>())) ?? []
            for card in all where card.groupID == group && card.deletedAt == nil {
                context.insert(card.duplicate(in: nil))
            }
            try? context.save()
        }
        _ = try await account.rpc("pasr_group_remove", body: body)
        await sync(in: context)
    }

    // MARK: Kaarten

    /// Een kaart naar een andere plek (privé of een gedeelde Pasr): een kopie met een nieuw id op de nieuwe plek,
    /// het origineel gaat weg op de oude plek (dat verwijderen synchroniseert mee).
    @discardableResult
    static func move(_ card: Card, to group: UUID?, in context: ModelContext) -> Card {
        guard card.groupID != group else { return card }
        let copy = card.duplicate(in: group)
        context.insert(copy)
        card.deletedAt = .now
        try? context.save()
        return copy
    }

    private func sinceKey(_ user: String, _ group: UUID) -> String { "pasr.gsync.since.\(user).\(group.uuidString)" }
    private func pushedKey(_ user: String, _ group: UUID) -> String { "pasr.gsync.pushed.\(user).\(group.uuidString)" }

    /// Groepen en uitnodigingen ophalen, dan per groep de kaarten heen en weer (nieuwste wijziging wint).
    /// Kaarten van een groep waar je niet meer in zit verdwijnen van dit apparaat.
    func sync(in context: ModelContext) async {
        guard let user = account.session?.userID, !syncing else { return }
        syncing = true
        defer { syncing = false }
        guard await refresh() else { return }
        let ids = Set(groups.map(\.id))

        var all = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let gone = all.filter { $0.groupID.map { !ids.contains($0) } ?? false }
        if !gone.isEmpty {
            for card in gone { context.delete(card) }
            for group in Set(gone.compactMap(\.groupID)) {
                UserDefaults.standard.removeObject(forKey: sinceKey(user, group))
                UserDefaults.standard.removeObject(forKey: pushedKey(user, group))
            }
            try? context.save()
            all = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        }

        for group in groups {
            let started = Date.now
            let pushedAt = UserDefaults.standard.double(forKey: pushedKey(user, group.id))
            let pushed = pushedAt > 0 ? Date(timeIntervalSince1970: pushedAt) : .distantPast
            let changes = CardSync.rows(all.filter { $0.groupID == group.id && CardSync.changedAt($0) > pushed })
            var body: [String: Any] = ["p_group": group.id.uuidString, "changes": changes]
            body["since"] = UserDefaults.standard.string(forKey: sinceKey(user, group.id)) ?? NSNull()
            do {
                guard let result = try await account.rpc("pasr_group_sync", body: body) as? [String: Any] else { continue }
                CardSync.apply(result["cards"] as? [[String: Any]] ?? [], to: all, in: context, group: group.id)
                if let now = result["now"] as? String { UserDefaults.standard.set(now, forKey: sinceKey(user, group.id)) }
                UserDefaults.standard.set(started.timeIntervalSince1970, forKey: pushedKey(user, group.id))
                all = (try? context.fetch(FetchDescriptor<Card>())) ?? []
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}

extension Card {
    /// Dezelfde kaart met een nieuw id, voor een andere plek (nil = privé).
    func duplicate(in group: UUID?) -> Card {
        let c = Card(storeName: storeName, number: number, format: format, kind: kind, colorHex: colorHex)
        c.groupID = group
        c.templateID = templateID
        c.note = note
        c.isFavorite = isFavorite
        c.useCount = useCount
        c.lastUsed = lastUsed
        c.createdAt = createdAt
        c.updatedAt = .now
        c.balance = balance
        c.currencyCode = currencyCode
        c.pin = pin
        c.expiresAt = expiresAt
        c.website = website
        c.placesData = placesData
        c.logoFromWebsite = logoFromWebsite
        c.isLocked = isLocked
        c.logoData = logoData
        c.frontPhoto = frontPhoto
        c.backPhoto = backPhoto
        c.codeImage = codeImage
        return c
    }
}
