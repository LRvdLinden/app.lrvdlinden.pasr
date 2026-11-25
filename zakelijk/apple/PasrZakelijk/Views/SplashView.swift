import SwiftUI

/// Openingsanimatie zoals in Pasr: drie kaarten komen omhoog en waaieren uit, de groene stempel van het
/// Pasr Zakelijk-icoon springt erop, daarna verschijnt "pasr ZAKELIJK". Kort (± 1,5 s) en wacht nooit op het netwerk.
struct SplashView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardsIn = false
    @State private var fanned = false
    @State private var badge = false
    @State private var wordmark = false
    @State private var glow = false

    private static let night = Color(hex: "#0A0B10")
    private static let cardAspect: CGFloat = 1.586
    private let cards: [(Color, Double, CGFloat)] = [
        (Theme.mint, -14, -22),
        (Theme.iris, -4, -6),
        (Theme.coral, 7, 10),
    ]

    var body: some View {
        ZStack {
            Self.night.ignoresSafeArea()
            RadialGradient(colors: [Theme.iris.opacity(glow ? 0.35 : 0.0), .clear],
                           center: .center, startRadius: 10, endRadius: 360)
                .ignoresSafeArea()
                .blur(radius: 20)

            VStack(spacing: 34) {
                ZStack {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, item in
                        SplashCard(color: item.0, showsCode: index == cards.count - 1)
                            .frame(width: 150, height: 150 / Self.cardAspect)
                            .rotationEffect(.degrees(fanned ? item.1 : 0))
                            .offset(x: fanned ? item.2 * 1.4 : 0, y: cardsIn ? CGFloat(index) * 14 - 14 : 420)
                            .opacity(cardsIn ? 1 : 0)
                            .animation(.spring(response: 0.62, dampingFraction: 0.78).delay(Double(index) * 0.08), value: cardsIn)
                            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: fanned)
                    }
                    Image("SplashStamp")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .frame(width: 66, height: 66)
                        .background(Theme.mint, in: Circle())
                        .overlay(Circle().strokeBorder(Self.night, lineWidth: 5))
                        .offset(x: 70, y: 44)
                        .scaleEffect(badge ? 1 : 0.2)
                        .opacity(badge ? 1 : 0)
                }
                .frame(height: 170)

                HStack(alignment: .center, spacing: 10) {
                    Text(verbatim: "pasr")
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .tracking(-1.5)
                        .foregroundStyle(Theme.gradient)
                    Text("ZAKELIJK")
                        .font(.system(size: 15, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.mint)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .overlay(Capsule().strokeBorder(Theme.mint.opacity(0.6)))
                }
                .opacity(wordmark ? 1 : 0)
                .scaleEffect(wordmark ? 1 : 0.86)
                .blur(radius: wordmark ? 0 : 8)
            }
        }
        .task { await run() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Pasr Zakelijk"))
    }

    @MainActor
    private func run() async {
        if reduceMotion {
            cardsIn = true; fanned = true; badge = true; wordmark = true
            try? await Task.sleep(for: .milliseconds(600))
            onFinish()
            return
        }
        cardsIn = true
        withAnimation(.easeOut(duration: 1.2)) { glow = true }
        try? await Task.sleep(for: .milliseconds(420))
        fanned = true
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { badge = true }
        try? await Task.sleep(for: .milliseconds(160))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { wordmark = true }
        try? await Task.sleep(for: .milliseconds(800))
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
