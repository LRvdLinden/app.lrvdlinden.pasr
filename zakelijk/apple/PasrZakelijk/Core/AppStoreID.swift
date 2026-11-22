import Foundation

/// Apple ID van Pasr Zakelijk in App Store Connect (App-informatie › Apple ID, alleen cijfers).
/// Nog leeg zolang de app niet in App Store Connect staat; dan is "Beoordeel Pasr Zakelijk" in Instellingen verborgen.
/// De beoordelingsvraag in de app (requestReview) werkt ook zonder dit ID.
enum AppStoreID {
    static let zakelijk = ""

    /// https://apps.apple.com/nl/app/id<ID>?action=write-review, of nil zolang het ID leeg is.
    static var reviewURL: URL? {
        let id = zakelijk.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/nl/app/id\(id)?action=write-review")
    }
}
