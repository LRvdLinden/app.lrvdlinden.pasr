import SwiftUI
import StoreKit

/// De beoordelingsvraag van de App Store: de eerste keer 4 uur na het eerste gebruik op dit apparaat, daarna
/// hoogstens één keer per week, alleen op een rustig moment (een paar seconden na openen, ingelogd, geen sheet open,
/// niet midden in het scannen). iOS beslist zelf of het venster echt verschijnt.
enum ReviewPrompter {
    private static let firstUseKey = "review.firstUseDate"
    private static let lastAskKey = "review.lastRequestDate"
    static let firstDelay: TimeInterval = 4 * 60 * 60
    static let interval: TimeInterval = 7 * 24 * 60 * 60

    static func registerUse(now: Date = .now) {
        let d = UserDefaults.standard
        if d.object(forKey: firstUseKey) == nil { d.set(now, forKey: firstUseKey) }
    }

    static func isEligible(now: Date = .now) -> Bool {
        let d = UserDefaults.standard
        guard let first = d.object(forKey: firstUseKey) as? Date, now.timeIntervalSince(first) >= firstDelay else { return false }
        if let last = d.object(forKey: lastAskKey) as? Date, now.timeIntervalSince(last) < interval { return false }
        return true
    }

    static func markRequested(now: Date = .now) {
        UserDefaults.standard.set(now, forKey: lastAskKey)
    }
}

struct ReviewPromptModifier: ViewModifier {
    let isCalm: Bool
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear { ReviewPrompter.registerUse() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { schedule() } else { task?.cancel() }
            }
            .onChange(of: isCalm) { _, calm in
                if calm { schedule() } else { task?.cancel() }
            }
            .task { schedule() }
    }

    private func schedule() {
        task?.cancel()
        guard isCalm, ReviewPrompter.isEligible() else { return }
        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, isCalm, scenePhase == .active, ReviewPrompter.isEligible() else { return }
            ReviewPrompter.markRequested()
            requestReview()
        }
    }
}

extension View {
    /// Hang aan de root-view: `isCalm` is false zolang je niet bent ingelogd, een sheet open staat of je scant.
    func reviewPrompt(isCalm: Bool) -> some View {
        modifier(ReviewPromptModifier(isCalm: isCalm))
    }
}
