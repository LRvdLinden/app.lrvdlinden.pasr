import SwiftUI
import StoreKit

/// De beoordelingsvraag van de App Store ("Vind je Pasr leuk?"): één keer per apparaat, een paar uur na het eerste
/// gebruik, op een rustig moment (app net geopend, geen welkomstscherm, niet vergrendeld, minstens één kaart).
/// iOS bepaalt zelf of het venster echt verschijnt (hoogstens 3 keer per jaar en nooit in TestFlight-builds).
enum ReviewPrompt {
    static let firstUseKey = "pasr.review.firstUse"
    static let askedKey = "pasr.review.asked"
    /// Zo lang na het eerste gebruik.
    static let delay: TimeInterval = 4 * 3600

    static func noteFirstUse() {
        if UserDefaults.standard.object(forKey: firstUseKey) == nil {
            UserDefaults.standard.set(Date.now, forKey: firstUseKey)
        }
    }

    static var isDue: Bool {
        let d = UserDefaults.standard
        guard !d.bool(forKey: askedKey), let first = d.object(forKey: firstUseKey) as? Date else { return false }
        return Date.now.timeIntervalSince(first) >= delay
    }

    static func markAsked() { UserDefaults.standard.set(true, forKey: askedKey) }
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
