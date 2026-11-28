import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Bouwstenen voor Mail: adresveld, Markdown-editor, bijlagen, voorbeeld (WKWebView zonder JavaScript), testmail.

/// Veld voor één of meer adressen (plakken met komma, spatie of regel), met teller en markering van ongeldige adressen.
struct MailAddressField: View {
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    @Binding var text: String
    var maxCount = MailLimits.recipients

    var body: some View {
        let list = MailAddressList.parse(text)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                counter(list)
            }
            TextField(prompt, text: $text, axis: .vertical)
                .lineLimit(1...6)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
                .padding(8)
                .background(Theme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(list.invalid.isEmpty ? Color.clear : Theme.coral, lineWidth: 1.5))
            if !list.invalid.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.coral)
                    Text("Ongeldig:").foregroundStyle(Theme.coral)
                    + Text(verbatim: " " + list.invalid.prefix(8).joined(separator: ", ") + (list.invalid.count > 8 ? " …" : ""))
                        .foregroundStyle(Theme.coral)
                }
                .font(.caption)
            }
            if list.duplicates > 0 {
                Text("\(list.duplicates) dubbele adressen genegeerd").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func counter(_ list: MailAddressList) -> some View {
        let n = list.valid.count
        HStack(spacing: 4) {
            if n == 0 && list.invalid.isEmpty {
                Text("geen adressen").foregroundStyle(Theme.muted)
            } else if n == 1 {
                Text("1 adres").foregroundStyle(Theme.mint)
            } else {
                Text("\(n) adressen").foregroundStyle(n > maxCount ? Theme.coral : Theme.mint)
            }
            if !list.invalid.isEmpty {
                Text("· \(list.invalid.count) ongeldig").foregroundStyle(Theme.coral)
            }
        }
        .font(.caption.monospacedDigit())
    }
}

/// Markdown-editor met werkbalk. Een knop voegt de opmaak toe aan het einde van de tekst.
struct MailBodyEditor: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    tool("Kop", "## Kop", block: true)
                    tool("Vet", "**vet**")
                    tool("Cursief", "*cursief*")
                    tool("Lijst", "- Punt", block: true)
                    tool("Citaat", "> Citaat", block: true)
                    tool("Link", "[tekst](https://)")
                    tool("Knop", "[[Knoptekst|https://pasr.nl]]", block: true)
                    tool("Afbeelding", "![omschrijving](https://)", block: true)
                    tool("Lijn", "---", block: true)
                    tool("Voornaam", "{{voornaam}}")
                }
            }
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 220)
                .padding(8)
                .background(Theme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .autocorrectionDisabled()
            Text(verbatim: String(localized: "Markdown: **vet**, *cursief*, lijsten, > citaat, [tekst](https://…), knop [[Knoptekst|https://…]] en afbeelding ![](https://…). Andere HTML wordt niet gebruikt. {{voornaam}} wordt de voornaam van de ontvanger."))
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func tool(_ title: LocalizedStringKey, _ snippet: String, block: Bool = false) -> some View {
        Button { insert(snippet, block: block) } label: { Text(title).font(.caption.weight(.semibold)) }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func insert(_ snippet: String, block: Bool) {
        var t = text
        if !t.isEmpty {
            if block {
                if !t.hasSuffix("\n\n") { t += t.hasSuffix("\n") ? "\n" : "\n\n" }
            } else if let last = t.last, !last.isWhitespace {
                t += " "
            }
        }
        text = t + snippet
    }
}

/// Bijlagen kiezen (bestanden of foto's), samen hoogstens 20 MB.
struct MailAttachmentsRows: View {
    @Binding var attachments: [MailDraftAttachment]
    @State private var photos: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var message: String?

    private var total: Int { attachments.reduce(0) { $0 + $1.data.count } }

    var body: some View {
        Group {
            ForEach(attachments) { a in
                HStack {
                    Image(systemName: "paperclip").foregroundStyle(Theme.muted)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: a.name).lineLimit(1)
                        Text(verbatim: Self.size(a.data.count)).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button(role: .destructive) { attachments.removeAll { $0.id == a.id } } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Bijlage verwijderen")
                }
            }
            HStack {
                Button { importing = true } label: { Label("Bestand", systemImage: "doc.badge.plus") }
                PhotosPicker(selection: $photos, maxSelectionCount: 10, matching: .images) { Label("Foto", systemImage: "photo") }
                Spacer()
                Text(verbatim: Self.size(total) + " / 20 MB").font(.caption.monospacedDigit())
                    .foregroundStyle(total > MailLimits.attachmentBytes ? Theme.coral : Theme.muted)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if let message { Text(message).font(.caption).foregroundStyle(Theme.coral) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size <= MailLimits.attachmentBytes, let data = try? Data(contentsOf: url) else {
                    message = String(localized: "Dit bestand is te groot of kan niet worden gelezen."); continue
                }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                add(data, name: url.lastPathComponent, type: mime)
            }
        }
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for (i, item) in items.enumerated() {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        message = String(localized: "Deze foto kan niet worden geladen."); continue
                    }
                    let ut = item.supportedContentTypes.first
                    let ext = ut?.preferredFilenameExtension ?? "jpg"
                    add(data, name: "foto-\(attachments.count + i + 1).\(ext)", type: ut?.preferredMIMEType ?? "image/jpeg")
                }
                photos = []
            }
        }
    }

    private func add(_ data: Data, name: String, type: String) {
        if total + data.count > MailLimits.attachmentBytes {
            message = String(localized: "De bijlagen zijn samen te groot (maximaal 20 MB).")
            return
        }
        message = nil
        attachments.append(MailDraftAttachment(name: name, type: type, data: data))
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// Live voorbeeld: dezelfde renderer als bij het versturen (`mail_preview`), in een webweergave zonder JavaScript.
struct MailPreviewSection: View {
    let markdown: String
    let brand: MailBrand
    let subject: String
    @EnvironmentObject private var session: Session
    @State private var html: String?
    @State private var error: String?
    @State private var loading = false
    @State private var dark = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Weergave", selection: $dark) {
                Text("Licht").tag(false)
                Text("Donker").tag(true)
            }
            .pickerStyle(.segmented)
            ZStack {
                if let html, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MailHTMLView(html: html, dark: dark)
                } else {
                    Text("Het voorbeeld verschijnt zodra je iets schrijft.")
                        .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding()
                }
                if loading { ProgressView().padding(8).background(.ultraThinMaterial, in: Capsule()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(8) }
            }
            .frame(height: 460)
            .frame(maxWidth: .infinity)
            .background(dark ? Color(hex: 0x111111) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let error { Text(error).font(.caption).foregroundStyle(Theme.coral) }
        }
        .task(id: "\(brand.rawValue)|\(subject)|\(markdown)") { await load() }
    }

    private func load() async {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { html = nil; error = nil; return }
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled else { return }
        loading = true
        defer { loading = false }
        do {
            let r = try await session.call("mail_preview", ["body_md": markdown, "brand": brand.rawValue, "subject": subject], as: MailPreviewResponse.self)
            html = r.html
            error = nil
        } catch is CancellationError {
        } catch let e as APIError where e.isUnauthorized {
        } catch { self.error = error.mailText }
    }
}

/// Testmail naar één adres (het adres wordt niet bewaard of gelogd).
struct MailTestRow: View {
    @Binding var address: String
    let markdown: String
    let brand: MailBrand
    let subject: String
    @EnvironmentObject private var session: Session
    @State private var sending = false
    @State private var state: String?
    @State private var good = true

    private var addr: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var ready: Bool {
        MailAddressList.isValid(addr) && !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !subject.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Testadres (jijzelf)", text: $address)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
            Button {
                Task { await send() }
            } label: {
                HStack { if sending { ProgressView() }; Label("Testmail sturen", systemImage: "paperplane") }
            }
            .disabled(sending || !ready)
            if let state { Text(state).font(.caption).foregroundStyle(good ? Theme.mint : Theme.coral) }
            if !ready {
                Text("Vul een geldig testadres, een onderwerp en een bericht in.").font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private func send() async {
        guard !sending else { return }
        sending = true; state = nil
        defer { sending = false }
        do {
            try await session.call("mail_test", ["body_md": markdown, "brand": brand.rawValue,
                                                 "subject": subject.trimmingCharacters(in: .whitespaces), "to": addr])
            good = true
            state = String(localized: "Testmail verstuurd. Hij komt zo binnen.")
        } catch is CancellationError {
        } catch { good = false; state = error.mailText }
    }
}

// MARK: - WKWebView zonder JavaScript

/// Weergave van mail-HTML: geen JavaScript, geen navigatie (links openen niet), niets blijft bewaard.
final class MailWebDelegate: NSObject, WKNavigationDelegate {
    var lastHTML: String?

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
    }
}

func makeMailWebConfiguration() -> WKWebViewConfiguration {
    let c = WKWebViewConfiguration()
    c.defaultWebpagePreferences.allowsContentJavaScript = false
    c.websiteDataStore = .nonPersistent()
    return c
}

#if canImport(UIKit)
struct MailHTMLView: UIViewRepresentable {
    let html: String
    var dark = false

    func makeCoordinator() -> MailWebDelegate { MailWebDelegate() }

    func makeUIView(context: Context) -> WKWebView {
        let v = WKWebView(frame: .zero, configuration: makeMailWebConfiguration())
        v.navigationDelegate = context.coordinator
        v.isOpaque = false
        v.backgroundColor = .clear
        v.scrollView.backgroundColor = .clear
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {
        v.overrideUserInterfaceStyle = dark ? .dark : .light
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            v.loadHTMLString(html, baseURL: nil)
        }
    }
}
#else
struct MailHTMLView: NSViewRepresentable {
    let html: String
    var dark = false

    func makeCoordinator() -> MailWebDelegate { MailWebDelegate() }

    func makeNSView(context: Context) -> WKWebView {
        let v = WKWebView(frame: .zero, configuration: makeMailWebConfiguration())
        v.navigationDelegate = context.coordinator
        return v
    }

    func updateNSView(_ v: WKWebView, context: Context) {
        v.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            v.loadHTMLString(html, baseURL: nil)
        }
    }
}
#endif
