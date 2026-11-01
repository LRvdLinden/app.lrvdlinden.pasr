import SwiftUI

/// A store's logo for the store picker: straight from the app for known stores, otherwise fetched
/// from the store's website and cached. Shows nothing when logos are switched off in Settings.
struct StoreLogoView: View {
    let domain: String
    var height: CGFloat = 30
    var maxWidth: CGFloat? = nil
    @AppStorage(LogoService.settingKey) private var enabled = true
    @State private var data: Data?

    init(domain: String, height: CGFloat = 30, maxWidth: CGFloat? = nil) {
        self.domain = domain
        self.height = height
        self.maxWidth = maxWidth
        _data = State(initialValue: LogoService.bundledLogo(for: domain))
    }

    var body: some View {
        Group {
            if enabled, let data {
                StoreLogoMark(data: data, style: StoreLogoStyles.style(for: domain), height: height, maxWidth: maxWidth)
                    .transition(.opacity)
            }
        }
        .task(id: domain) {
            guard enabled, data == nil else { return }
            if let cached = LogoService.cachedLogo(for: domain) { data = cached; return }
            let fetched = await LogoService.logo(for: domain)
            withAnimation(.easeOut(duration: 0.25)) { data = fetched }
        }
    }
}
