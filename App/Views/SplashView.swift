import SwiftUI

/// Opening animation: three cards rise and fan into the Pasr mark, then the wordmark appears.
struct SplashView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardsIn = false
    @State private var fanned = false
    @State private var wordmark = false
    @State private var glow = false

    private let cards: [(Color, Double, CGFloat)] = [
        (Brand.mint, -14, -22),
        (Brand.iris, -4, -6),
        (Brand.coral, 7, 10),
    ]

    var body: some View {
        ZStack {
            Brand.ink.ignoresSafeArea()
            RadialGradient(colors: [Brand.iris.opacity(glow ? 0.35 : 0.0), .clear],
                           center: .center, startRadius: 10, endRadius: 360)
                .ignoresSafeArea()
                .blur(radius: 20)

            VStack(spacing: 34) {
                ZStack {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, item in
                        SplashCard(color: item.0, showsCode: index == cards.count - 1)
                            .frame(width: 150, height: 150 / Brand.cardAspect)
                            .rotationEffect(.degrees(fanned ? item.1 : 0))
                            .offset(x: fanned ? item.2 * 1.4 : 0, y: cardsIn ? CGFloat(index) * 14 - 14 : 420)
                            .opacity(cardsIn ? 1 : 0)
                            .animation(.spring(response: 0.62, dampingFraction: 0.78).delay(Double(index) * 0.08), value: cardsIn)
                            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: fanned)
                    }
                }
                .frame(height: 170)

                Text("pasr")
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .tracking(-1.5)
                    .foregroundStyle(Brand.gradient)
                    .opacity(wordmark ? 1 : 0)
                    .scaleEffect(wordmark ? 1 : 0.86)
                    .blur(radius: wordmark ? 0 : 8)
            }
        }
        .task { await run() }
        .accessibilityLabel(Text("Pasr"))
    }

    @MainActor
    private func run() async {
        if reduceMotion {
            cardsIn = true; fanned = true; wordmark = true
            try? await Task.sleep(for: .milliseconds(600))
            onFinish()
            return
        }
        cardsIn = true
        withAnimation(.easeOut(duration: 1.2)) { glow = true }
        try? await Task.sleep(for: .milliseconds(420))
        fanned = true
        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { wordmark = true }
        try? await Task.sleep(for: .milliseconds(900))
        onFinish()
    }
}

private struct SplashCard: View {
    let color: Color
    var showsCode = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.95), color], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .topLeading) {
                Capsule().fill(.white.opacity(0.5)).frame(width: 46, height: 7).padding(14)
            }
            .overlay(alignment: .bottom) {
                if showsCode {
                    HStack(spacing: 2.5) {
                        ForEach(0..<15, id: \.self) { i in
                            Rectangle().fill(.white.opacity(0.85))
                                .frame(width: [3.0, 1.5, 2.0, 1.0, 3.0, 2.0, 1.5][i % 7])
                        }
                    }
                    .frame(height: 22)
                    .padding(.bottom, 14)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
    }
}
