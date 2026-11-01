import SwiftUI

/// A store logo drawn cleanly on its card, the way SuperCards does it: no frame, no shadow.
/// Logos that ship with Pasr are see-through PNGs; `style` says whether to draw them in one colour
/// (for contrast) or on a small plate. Own logos (style nil) are shown as they are, softly rounded.
struct StoreLogoMark: View {
    let data: Data
    var style: StoreLogoStyle?
    var height: CGFloat
    var maxWidth: CGFloat? = nil

    var body: some View {
        if let image = Image(data: data) {
            let width = maxWidth ?? height * 3
            if let style, !style.opaque {
                let mark = Group {
                    if let tint = style.tint {
                        image.resizable().renderingMode(.template).scaledToFit().foregroundStyle(Color(hex: tint))
                    } else {
                        image.resizable().scaledToFit()
                    }
                }
                .frame(maxWidth: width, maxHeight: height)
                if let plate = style.plate {
                    mark.padding(.horizontal, height * 0.22).padding(.vertical, height * 0.14)
                        .frame(maxHeight: height)
                        .background(Color(hex: plate), in: RoundedRectangle(cornerRadius: height * 0.24, style: .continuous))
                } else {
                    mark
                }
            } else {
                // Artwork that fills its square (or the user's own logo): a neat rounded icon.
                image.resizable().scaledToFit()
                    .frame(maxWidth: width, maxHeight: height)
                    .clipShape(RoundedRectangle(cornerRadius: height * 0.22, style: .continuous))
            }
        }
    }
}
