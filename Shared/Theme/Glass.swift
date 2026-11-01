import SwiftUI

/// Liquid Glass on iOS/watchOS 26, a regular look on older systems (Pasr runs from iOS 17 / watchOS 10).
extension View {
    @ViewBuilder
    func pasrGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, watchOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }

    @ViewBuilder
    func pasrGlass(in shape: some Shape = Capsule()) -> some View {
        if #available(iOS 26.0, watchOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
