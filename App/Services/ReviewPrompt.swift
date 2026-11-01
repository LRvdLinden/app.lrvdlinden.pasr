import SwiftUI
import StoreKit

/// De beoordelingsvraag van de App Store ("Vind je Pasr leuk?"): de eerste keer een paar uur na het eerste gebruik,
/// daarna hoogstens één keer per week, op een rustig moment (app net geopend, geen welkomstscherm, niet vergrendeld,
/// minstens één kaart).
///
/// Apple vertelt een app niet of iemand op een ster heeft getikt, en een eigen sterrenvenster mag niet (richtlijn 5.6.1).
/// iOS regelt het zelf: wie Pasr al heeft beoordeeld, krijgt het venster niet meer, en iOS toont het hoogstens
/// 3 keer per jaar (nooit in TestFlight-builds). Pasr vraagt dus elke week; iOS laat het venster alleen zien als het mag.
enum ReviewPrompt {
    static let firstUseKey = "pasr.review.firstUse"
    static let lastAskedKey = "pasr.review.lastAsked"
    /// Eerste keer: zo lang na het eerste gebruik.
    static let firstDelay: TimeInterval = 4 * 3600
    /// Daarna: zo lang tussen twee keer vragen.
    static let interval: TimeInterval = 7 * 86_400

    static func noteFirstUse() {
        if UserDefaults.standard.object(forKey: firstUseKey) == nil {
            UserDefaults.standard.set(Date.now, forKey: firstUseKey)
        }
    }

    static var isDue: Bool {
        let d = UserDefaults.standard
        guard let first = d.object(forKey: firstUseKey) as? Date, Date.now.timeIntervalSince(first) >= firstDelay else { return false }
        guard let last = d.object(forKey: lastAskedKey) as? Date else { return true }
        return Date.now.timeIntervalSince(last) >= interval
    }

    static func markAsked() { UserDefaults.standard.set(Date.now, forKey: lastAskedKey) }
}

private struct ReviewPromptModifier: ViewModifier {
    var ready: Bool
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { ReviewPrompt.noteFirstUse() }
            .task(id: "\(ready)|\(scenePhase == .active)") {
                guard ready, scenePhase == .active, ReviewPrompt.isDue else { return }
                // even wachten, zodat de vraag niet over het openen of een kaart heen valt
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, ready, ReviewPrompt.isDue else { return }
                ReviewPrompt.markAsked()
                requestReview()
            }
    }
}

extension View {
    /// `ready`: de app staat rustig open (geen splash, geen welkomstscherm, niet vergrendeld, er is een kaart).
    func reviewPrompt(ready: Bool) -> some View { modifier(ReviewPromptModifier(ready: ready)) }
}
