#if os(iOS)
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WatchConnectivity

/// Sends the cards straight to the paired Apple Watch whenever they change. iCloud syncs too,
/// but on the Watch that can take a long time; this way new cards are there within seconds.
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    private var lastFile: URL {
        URL.applicationSupportDirectory.appending(path: "watch-cards.json")
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Call with the current cards; sends only when something the Watch shows has changed.
    @MainActor
    func send(_ cards: [Card], order: CardOrder = .az, distances: [UUID: Double] = [:]) {
        // tickets voor hetzelfde evenement op dezelfde dag naast elkaar (TicketGroups.swift), elk met zijn eigen code
        let list = cards.filter { $0.deletedAt == nil && !$0.isTemporary }.ordered(order, distances: distances)
            .stackItems().flatMap(\.cards)
            .enumerated().map { i, card in
                var w = WatchCard(card)
                w.rank = order == .az ? nil : i
                w.cover = Self.watchCover(for: card)
                return w
            }
        guard let data = WatchPayload.encode(list) else { return }
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? data.write(to: lastFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        push(list, data: data)
    }

    /// Het kaartontwerp verkleind voor de Watch (320 px breed, JPEG), per winkel en versie onthouden.
    nonisolated(unsafe) private static var coverCache: [String: Data] = [:]

    @MainActor
    private static func watchCover(for card: Card) -> Data? {
        guard let id = card.templateID?.lowercased(), let data = card.storeCover else { return nil }
        let key = id + "|" + (RemoteStores.coverVersion(for: id) ?? "")
        if let cached = coverCache[key] { return cached }
        guard let image = ImageTools.cgImage(from: data, maxSide: 320) else { return nil }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        coverCache[key] = output as Data
        return output as Data
    }

    private func push(_ list: [WatchCard], data: Data) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        // 1. Without images, through the application context: arrives first.
        if let small = WatchPayload.encode(list.map(\.withoutImages)), small.count < 60_000 {
            try? session.updateApplicationContext(["cards": small, "sent": Date.now.timeIntervalSince1970])
        }
        // 2. Everything, with logos and codes, as a file. Only the newest one matters.
        for transfer in session.outstandingFileTransfers { transfer.cancel() }
        let file = FileManager.default.temporaryDirectory.appending(path: "pasr-cards-\(UUID().uuidString).json")
        if (try? data.write(to: file)) != nil {
            session.transferFile(file, metadata: ["kind": "cards"])
        }
    }

    private func resendLast() {
        guard let data = try? Data(contentsOf: lastFile), let list = WatchPayload.decode(data) else { return }
        push(list, data: data)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if state == .activated { resendLast() }
    }

    /// The Watch app asks for the cards when it opens.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["request"] as? String == "cards" { resendLast() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler([:])
        if message["request"] as? String == "cards" { resendLast() }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        if session.isPaired, session.isWatchAppInstalled { resendLast() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
#endif
