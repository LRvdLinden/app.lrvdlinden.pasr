import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Kleine laag tussen iOS en macOS, zodat de schermen van Pasr Zakelijk in beide apps (iPhone/iPad en de native Mac-app)
// dezelfde code gebruiken. Alleen wat op de Mac anders heet of niet bestaat staat hier.

#if os(macOS)
/// Op de Mac is een afbeelding een NSImage; de gedeelde code noemt hem UIImage.
typealias UIImage = NSImage
typealias UIColor = NSColor

extension Image {
    init(uiImage: NSImage) { self.init(nsImage: uiImage) }
}

extension NSImage {
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Het CGImage achter deze afbeelding (eerste representatie).
    var cgImageValue: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    func pngData() -> Data? {
        guard let cg = cgImageValue else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let cg = cgImageValue else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}

/// Klembord zoals op iOS (`UIPasteboard.general.string = …`), op de Mac via NSPasteboard.
final class UIPasteboard {
    static let general = UIPasteboard()

    var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            NSPasteboard.general.clearContents()
            if let newValue { NSPasteboard.general.setString(newValue, forType: .string) }
        }
    }

    var url: URL? {
        get { string.flatMap(URL.init(string:)) }
        set {
            NSPasteboard.general.clearContents()
            if let newValue {
                NSPasteboard.general.writeObjects([newValue as NSURL])
                NSPasteboard.general.setString(newValue.absoluteString, forType: .string)
            }
        }
    }
}
#endif

/// Welk platform deze build is (voor teksten en kleine verschillen in gedeelde schermen).
enum AppPlatform {
    #if os(macOS)
    static let isMac = true
    #else
    static let isMac = false
    #endif
}

/// Soort toetsenbord voor een tekstveld (alleen iOS; op de Mac is er één toetsenbord).
enum KeyboardKind {
    case email, url, number, decimal
}

/// Hoofdletters bij typen (alleen iOS).
enum CapitalizationKind {
    case never, characters, sentences, words
}

extension View {
    /// Kleine titel in de navigatiebalk (iOS); op de Mac staat de titel in de vensterbalk.
    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder func keyboard(_ kind: KeyboardKind) -> some View {
        #if os(iOS)
        switch kind {
        case .email: keyboardType(.emailAddress)
        case .url: keyboardType(.URL)
        case .number: keyboardType(.numberPad)
        case .decimal: keyboardType(.decimalPad)
        }
        #else
        self
        #endif
    }

    @ViewBuilder func capitalization(_ kind: CapitalizationKind) -> some View {
        #if os(iOS)
        switch kind {
        case .never: textInputAutocapitalization(.never)
        case .characters: textInputAutocapitalization(.characters)
        case .sentences: textInputAutocapitalization(.sentences)
        case .words: textInputAutocapitalization(.words)
        }
        #else
        self
        #endif
    }

    /// Op de Mac krijgt een sheet een prettige vaste maat (op iOS doet dit niets).
    @ViewBuilder func macSheetFrame(minWidth: CGFloat = 520, minHeight: CGFloat = 560) -> some View {
        #if os(macOS)
        frame(minWidth: minWidth, idealWidth: max(minWidth, 600), minHeight: minHeight, idealHeight: max(minHeight, 720))
            .formStyle(.grouped)
            // een sheet is nooit een paneel: anders erft hij "ingebed" van het paneel eronder en mist hij Klaar
            .environment(\.isEmbeddedPane, false)
        #else
        self
        #endif
    }

    /// Alle formulieren gegroepeerd op de Mac (zoals Systeeminstellingen): secties als kaarten, label links en
    /// het veld rechts in dezelfde rij, een leesbare breedte en scrollen binnen het paneel. De standaard Mac-stijl
    /// (`.columns`) zet labels in een kolom links die wordt afgesneden en scrolt niet. Op iOS doet dit niets.
    /// Wordt bovenaan elk venster en elke sheet gezet; de stijl geldt via de omgeving voor elke Form daaronder.
    @ViewBuilder func pasrFormStyle() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }

    /// Contextmenu (rechtermuisknop) alleen op de Mac, als alternatief voor een veegactie op iOS.
    func macContextMenu<Items: View>(@ViewBuilder _ items: () -> Items) -> some View {
        modifier(MacContextMenu(items: items()))
    }

    /// Op de Mac bestaat trekken-om-te-verversen niet: dan een Ververs-knop (⌘R) in de werkbalk. Op iOS niets.
    func macRefreshButton(_ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(MacRefreshButton(action: action))
    }
}

private struct MacContextMenu<Items: View>: ViewModifier {
    let items: Items

    func body(content: Content) -> some View {
        #if os(macOS)
        content.contextMenu { items }
        #else
        content
        #endif
    }
}

private struct MacRefreshButton: ViewModifier {
    let action: @MainActor () async -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await action() } } label: { Label("Ververs", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: .command)
                    .help(Text("Ververs"))
            }
        }
        #else
        content
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Links in de navigatiebalk (iOS) of bij de navigatie in de vensterbalk (Mac).
    static var barLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    /// Rechts in de navigatiebalk (iOS) of bij de acties in de vensterbalk (Mac).
    static var barTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

/// Of een scherm in een venster/paneel van de Mac-app staat in plaats van in een sheet (dan geen "Klaar"-knop).
private struct EmbeddedPaneKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isEmbeddedPane: Bool {
        get { self[EmbeddedPaneKey.self] }
        set { self[EmbeddedPaneKey.self] = newValue }
    }
}

/// "Klaar" in een sheet; verborgen als hetzelfde scherm als paneel in de Mac-app staat.
struct DoneButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isEmbeddedPane) private var embedded

    var body: some View {
        if !embedded {
            Button("Klaar") { dismiss() }
        }
    }
}

/// Openen van de systeeminstellingen (camera-toegang).
enum SystemSettings {
    static var cameraPrivacyURL: URL? {
        #if os(iOS)
        URL(string: UIApplication.openSettingsURLString)
        #else
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
        #endif
    }
}

/// Korte naam van het apparaat voor het logboek en de apparatenlijst ("iPhone", "iPad", "Mac").
enum DeviceInfo {
    static var model: String {
        #if os(macOS)
        "Mac"
        #elseif targetEnvironment(simulator)
        "Simulator"
        #else
        UIDevice.current.model
        #endif
    }

    static var osLine: String {
        #if os(macOS)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #else
        return "iOS \(UIDevice.current.systemVersion)"
        #endif
    }
}
