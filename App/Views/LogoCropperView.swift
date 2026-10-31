import SwiftUI

/// Drag a frame around the logo on a photo or screenshot of a card; that part becomes the logo.
struct LogoCropperView: View {
    let image: CGImage
    var onCrop: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Selection in normalised image coordinates (0...1, origin top-left).
    @State private var selection = CGRect(x: 0.06, y: 0.06, width: 0.4, height: 0.2)
    @State private var dragStart: CGRect?

    init?(imageData: Data, onCrop: @escaping (Data) -> Void) {
        guard let image = ImageTools.cgImage(from: imageData) else { return nil }
        self.image = image
        self.onCrop = onCrop
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Sleep het kader over het logo. Sleep de rechteronderhoek om het groter of kleiner te maken.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                GeometryReader { geo in
                    let frame = fitted(in: geo.size)
                    let sel = CGRect(x: frame.minX + selection.minX * frame.width,
                                     y: frame.minY + selection.minY * frame.height,
                                     width: selection.width * frame.width,
                                     height: selection.height * frame.height)
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)

                        Path { path in
                            path.addRect(frame)
                            path.addRect(sel)
                        }
                        .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)

                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(.white, lineWidth: 2)
                            .background(Color.white.opacity(0.001))
                            .frame(width: sel.width, height: sel.height)
                            .position(x: sel.midX, y: sel.midY)
                            .gesture(moveGesture(frame: frame))

                        Circle()
                            .fill(.white)
                            .frame(width: 28, height: 28)
                            .shadow(radius: 3)
                            .position(x: sel.maxX, y: sel.maxY)
                            .gesture(resizeGesture(frame: frame))
                    }
                }
                .padding(.horizontal, 12)

                if let preview = croppedImage {
                    HStack(spacing: 12) {
                        Text("Voorbeeld").font(.subheadline).foregroundStyle(.secondary)
                        Image(decorative: preview, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 76, maxHeight: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .padding(.bottom, 8)
                }
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Logo uitknippen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gebruik") {
                        if let preview = croppedImage, let png = ImageTools.png(preview, maxSide: 256) { onCrop(png) }
                        dismiss()
                    }
                }
            }
        }
    }

    private var croppedImage: CGImage? { ImageTools.crop(image, to: selection) }

    private func fitted(in size: CGSize) -> CGRect {
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        var width = size.width, height = size.width / aspect
        if height > size.height { height = size.height; width = height * aspect }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func moveGesture(frame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? selection
                dragStart = start
                var moved = start.offsetBy(dx: value.translation.width / frame.width,
                                           dy: value.translation.height / frame.height)
                moved.origin.x = min(max(0, moved.minX), 1 - moved.width)
                moved.origin.y = min(max(0, moved.minY), 1 - moved.height)
                selection = moved
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resizeGesture(frame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? selection
                dragStart = start
                var resized = start
                resized.size.width = min(max(0.05, start.width + value.translation.width / frame.width), 1 - start.minX)
                resized.size.height = min(max(0.03, start.height + value.translation.height / frame.height), 1 - start.minY)
                selection = resized
            }
            .onEnded { _ in dragStart = nil }
    }
}

/// Image data waiting to be cropped, for `.sheet(item:)`.
struct CropRequest: Identifiable {
    let id = UUID()
    let data: Data
    var target: UUID? = nil
}
