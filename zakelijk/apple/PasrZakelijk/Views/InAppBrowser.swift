import SwiftUI
#if os(iOS)
import SafariServices
#else
import WebKit
#endif

/// Een webpagina van pasr.nl in de app: op iOS Safari in de app (SFSafariViewController), op de Mac een venster met
/// WebKit en een knop om de pagina in je eigen browser te openen (daar werken downloads zoals altijd).
struct InAppBrowser: View {
    let url: URL

    var body: some View {
        #if os(iOS)
        SafariSheet(url: url).ignoresSafeArea()
        #else
        MacBrowserSheet(url: url)
        #endif
    }
}

#if os(iOS)
private struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let browser = SFSafariViewController(url: url)
        browser.preferredControlTintColor = UIColor(red: 0.42, green: 0.36, blue: 1, alpha: 1)
        return browser
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#else
private struct MacBrowserSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            MacWebView(url: url)
                .navigationTitle(Text(verbatim: url.host() ?? "pasr.nl"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Klaar") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        Button { openURL(url) } label: { Label("Open in browser", systemImage: "safari") }
                    }
                }
        }
        .frame(minWidth: 820, idealWidth: 980, minHeight: 640, idealHeight: 800)
    }
}

/// WKWebView in SwiftUI (Mac).
struct MacWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}
}
#endif
