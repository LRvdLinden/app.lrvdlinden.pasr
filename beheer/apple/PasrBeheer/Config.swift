import Foundation

/// Openbare instellingen van het Supabase-project Pasr (zelfde als beheer/web/config.js).
/// De publishable key is bedoeld om openbaar te zijn; geheimen staan alleen op de server.
enum Config {
    static let supabaseURL = "https://xcfuiszcfgkpbixqzrjb.supabase.co"
    static let publishableKey = "sb_publishable_wFRG_22hV_8FJUX1JcS8SQ_2JHxQlzw"

    static var isConfigured: Bool { !supabaseURL.isEmpty && !publishableKey.isEmpty }
    static var adminFunction: URL? { URL(string: supabaseURL + "/functions/v1/admin") }

    static let website = URL(string: "https://pasr.nl")!
    static let beheerSite = URL(string: "https://beheer.pasr.nl")!
    static let supabaseDashboard = URL(string: "https://supabase.com/dashboard/project/xcfuiszcfgkpbixqzrjb")!
}
