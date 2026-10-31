import SwiftUI

/// The logo from a store's website, loaded on demand and cached. Shows nothing until it arrives,
/// and nothing at all when website logos are switched off in Settings.
struct StoreLogoView: View {
    let domain: String
    var height: CGFloat = 30
    @AppStorage(LogoService.settingKey) private var enabled = true
    @State private var data: Data?

    var body: some View {
        Group {
            if enabled, let data, let image = Image(data: data) {
                image.resizable().scaledToFit()
                    .frame(maxWidth: height * 2.4, maxHeight: height)
                    .clipShape(RoundedRectangle(cornerRadius: height * 0.24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: height * 0.24, style: .continuous)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .task(id: domain) {
            guard enabled else { return }
            if let cached = LogoService.cachedLogo(for: domain) { data = cached; return }
            let fetched = await LogoService.logo(for: domain)
            withAnimation(.easeOut(duration: 0.25)) { data = fetched }
        }
    }
}
