import SwiftUI
import WebKit
import UniformTypeIdentifiers
#if os(iOS)
import Photos
#else
import AppKit
#endif

/// Centraal promotiemateriaal voor stempelkaarten, coupons en actiecodes.
struct BusinessPromotionHub: View {
    let business: Business
    @State private var products: [PromoProduct] = []
    @State private var selection: String = ""
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Kies eerst de actieve stempelkaart, kortingscoupon of actiecode. Maak daarna social posts, stories, webban­ners of flyers in Licht en Donker.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if loading { ProgressView("Zakelijke acties laden…") }
                if let error { Text(error).foregroundStyle(Theme.coral) }
                Section("Promotiemateriaal voor") {
                    ForEach(products) { product in
                        NavigationLink {
                            PromoNativePreview(product: product)
                        } label: {
                            HStack {
                                Image(systemName: product.icon).foregroundStyle(Theme.iris)
                                VStack(alignment: .leading) {
                                    Text(product.title)
                                    Text(product.typeTitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !loading && products.isEmpty {
                        Text("Maak eerst een stempelkaart, kortingscoupon of actiecode.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    #if os(macOS)
                    Label("PNG-afbeeldingen en ZIP-bestanden bewaar je via het bewaarvenster, standaard in Downloads.", systemImage: "square.and.arrow.down")
                        .font(.footnote).foregroundStyle(.secondary)
                    #else
                    Label("PNG-afbeeldingen worden opgeslagen in Foto’s. Een ZIP kun je via de bestandskiezer bewaren in Downloads.", systemImage: "square.and.arrow.down")
                        .font(.footnote).foregroundStyle(.secondary)
                    #endif
                }
            }
            .navigationTitle("Promotiemateriaal")
            .toolbar { BusinessPicker() }
            .refreshable { await load() }
            .task(id: business.id) { await load() }
        }
    }

    @MainActor private func load() async {
        loading = true
        defer { loading = false }
        products = business.cards.map { card in
            PromoProduct(id: "card:\(card.id)", kind: "card", title: card.name, business: business.name,
                         fields: ["kind": "card", "id": card.id, "name": card.name, "business": business.name,
                                  "color": card.color, "reward": card.reward, "stamps_total": card.stampsTotal,
                                  "published": card.published, "logo": card.logo ?? "",
                                  "join_url": card.joinURL.absoluteString])
        }
        async let coupons = Account.shared.rpc("pasr_business_coupon_list", ["p_business": business.id])
        async let codes = Account.shared.rpc("pasr_business_promo_list", ["p_business": business.id])
        do {
            let couponData = try await coupons
            if let rows = couponData as? [[String: Any]] {
                for row in rows {
                    guard let id = row["id"] as? String else { continue }
                    var fields = row
                    fields["kind"] = "coupon"
                    fields["business"] = business.name
                    fields["color"] = "#6A5CFF"
                    products.append(PromoProduct(id: "coupon:\(id)", kind: "coupon",
                        title: row["title"] as? String ?? "Kortingscoupon", business: business.name, fields: fields))
                }
            }
        } catch { self.error = "Kortingscoupons konden niet worden geladen: \(error.localizedDescription)" }
        do {
            let codeData = try await codes
            if let rows = codeData as? [[String: Any]] {
                for row in rows {
                    guard let id = row["id"] as? String else { continue }
                    var fields = row
                    fields["kind"] = "code"
                    fields["business"] = business.name
                    fields["color"] = "#6A5CFF"
                    products.append(PromoProduct(id: "code:\(id)", kind: "code",
                        title: row["title"] as? String ?? "Actiecode", business: business.name, fields: fields))
                }
            }
        } catch { self.error = "Actiecodes konden niet worden geladen: \(error.localizedDescription)" }
    }
}

struct PromoProduct: Identifiable {
    let id: String
    let kind: String
    let title: String
    let business: String
    let fields: [String: Any]
    var typeTitle: String {
        switch kind { case "card": "Stempelkaart"; case "coupon": "Kortingscoupon"; default: "Actiecode" }
    }
    var icon: String {
        switch kind { case "card": "rectangle.stack"; case "coupon": "ticket"; default: "number" }
    }
}

/// Gebruikt dezelfde Canvas-ontwerpen als pasr.nl, maar exporteert daadwerkelijk naar iOS.
struct PromoNativePreview: View {
    let product: PromoProduct
    var body: some View {
        PromoWebContainer(product: product)
            .navigationTitle(product.title)
            .inlineTitle()
            .background(Theme.bg)
    }
}

#if os(iOS)
private typealias PromoRepresentable = UIViewRepresentable
#else
private typealias PromoRepresentable = NSViewRepresentable
#endif

private struct PromoWebContainer: PromoRepresentable {
    let product: PromoProduct

    func makeCoordinator() -> Coordinator { Coordinator(product: product) }

    private func makeBrowser(_ context: Context) -> WKWebView {
        let content = WKUserContentController()
        content.add(context.coordinator, name: "pasrExport")
        let config = WKWebViewConfiguration()
        config.userContentController = content
        let browser = WKWebView(frame: .zero, configuration: config)
        context.coordinator.browser = browser
        browser.navigationDelegate = context.coordinator
        #if os(iOS)
        browser.isOpaque = false
        browser.backgroundColor = UIColor.systemBackground
        #endif
        browser.load(URLRequest(url: URL(string: "https://pasr.nl/zakelijk/flyer/")!))
        return browser
    }

    #if os(iOS)
    func makeUIView(context: Context) -> WKWebView { makeBrowser(context) }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    #else
    func makeNSView(context: Context) -> WKWebView { makeBrowser(context) }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    #endif

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let product: PromoProduct
        weak var browser: WKWebView?
        private var received = Data()
        private var outputName = ""
        private var mime = ""
        private var expectedBytes = 0

        init(product: PromoProduct) { self.product = product }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView.url?.host == "pasr.nl",
                  let payload = try? JSONSerialization.data(withJSONObject: product.fields, options: [.fragmentsAllowed]),
                  let json = String(data: payload, encoding: .utf8) else { return }
            let script = "if(window.PasrPromo){document.getElementById('zk-flyer').innerHTML='';window.PasrPromo.mount(document.getElementById('zk-flyer'),\(json));}"
            webView.evaluateJavaScript(script)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.request.url?.host == "pasr.nl" ? .allow : .cancel)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.securityOrigin.host == "pasr.nl",
                  let body = message.body as? [String: Any],
                  let operation = body["operation"] as? String else { return }
            switch operation {
            case "begin":
                let name = (body["name"] as? String ?? "").components(separatedBy: "/").last ?? ""
                let mime = body["mime"] as? String ?? ""
                let length = body["length"] as? Int ?? 0
                guard length > 0 && length < 75_000_000,
                      name.count < 140 && name.hasPrefix("Pasr-"),
                      mime == "image/png" || mime == "application/zip" else { return }
                self.outputName = name
                self.mime = mime
                self.expectedBytes = length
                received = Data(capacity: length)
            case "chunk":
                guard expectedBytes > 0, let b64 = body["data"] as? String,
                      let chunk = Data(base64Encoded: b64),
                      received.count + chunk.count <= expectedBytes else { return }
                received.append(chunk)
            case "end":
                guard expectedBytes > 0, received.count == expectedBytes else { return }
                let bytes = received, filename = outputName, type = mime
                received = Data();expectedBytes = 0
                #if os(iOS)
                if type == "image/png" {
                    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                        guard status == .authorized || status == .limited,
                              let image = UIImage(data: bytes) else { return }
                        PHPhotoLibrary.shared().performChanges {
                            PHAssetChangeRequest.creationRequestForAsset(from: image)
                        }
                    }
                } else {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                    guard (try? bytes.write(to: url, options: .atomic)) != nil else { return }
                    DispatchQueue.main.async {
                        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
                        var top = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                            .flatMap { $0.windows }.first(where: { $0.isKeyWindow })?.rootViewController
                        while let presented = top?.presentedViewController { top = presented }
                        top?.present(picker, animated: true)
                    }
                }
                #else
                // Mac: PNG of ZIP bewaren waar je wilt (standaard Downloads), via het bewaarvenster
                DispatchQueue.main.async {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = filename
                    panel.allowedContentTypes = [type == "image/png" ? UTType.png : UTType.zip]
                    panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    panel.begin { response in
                        guard response == .OK, let url = panel.url else { return }
                        try? bytes.write(to: url, options: .atomic)
                    }
                }
                #endif
            default: break
            }
        }
    }
}
