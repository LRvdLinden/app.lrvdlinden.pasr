import SwiftUI

/// A card that turns over around its vertical axis: the front (logo and name) first,
/// the back (barcode or QR code) once `angle` passes 90 degrees.
struct FlipCardView: View, Animatable {
    let appearance: CardAppearance
    var angle: Double
    var cornerRadius: CGFloat = 22

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    private var showingBack: Bool { angle.truncatingRemainder(dividingBy: 360) >= 90 }

    var body: some View {
        ZStack {
            CardFaceView(appearance: appearance, showsCode: false, cornerRadius: cornerRadius)
                .opacity(showingBack ? 0 : 1)
            CardFaceView(appearance: appearance, revealed: true, cornerRadius: cornerRadius)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(showingBack ? 1 : 0)
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}
