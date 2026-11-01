import SwiftUI
import UniformTypeIdentifiers

/// Zoals Homey Insights: bronnen aanvinken (links op iPad en Mac, op de iPhone via een blad), één gedeelde periode,
/// grafieken onder elkaar met een gedeelde kruisdraad, en de zichtbare reeksen als CSV delen.
struct InsightsView: View {
    @EnvironmentObject private var session: Session
    @AppStorage("insights.sources") private var sourcesRaw = "accounts,signups,wallet"
    @AppStorage("insights.range") private var rangeRaw = 30
    @State private var offset = 0
    @State private var stats: Stats?
    @State private var error: String?
    @State private var selection: Date?
    @State private var showSources = false
    @State private var loading = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var wide: Bool { sizeClass == .regular }
    #else
    private let wide = true
    #endif

    private var sources: [Metric] {
        let set = Set(sourcesRaw.split(separator: ",").map(String.init))
        return Metric.allCases.filter { set.contains($0.rawValue) }
    }
    private var range: StatsRange { StatsRange(rawValue: rangeRaw) ?? .month }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                if wide {
                    CardBox { sourceList }.frame(width: 250)
                }
                VStack(alignment: .leading, spacing: 12) {
                    CardBox(padding: 12) {
                        RangeBar(stats: stats, range: Binding(get: { range }, set: { rangeRaw = $0.rawValue }), offset: $offset)
                    }
                    if let error {
                        Text(error).font(.subheadline).foregroundStyle(Theme.coral)
                    }
                    if sources.isEmpty {
                        CardBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Geen bronnen gekozen").font(.headline)
                                Text("Kies één of meer bronnen om ze hier te vergelijken.").foregroundStyle(Theme.muted)
                                Button("Bronnen kiezen") { showSources = true }
                            }
                        }
                    }
                    if let stats {
                        let points = insightPoints(stats, range: range)
                        ForEach(sources) { m in
                            CardBox {
                                InsightPanel(metric: m, points: points, range: range, selection: $selection, height: wide ? 210 : 170)
                            }
                        }
                        .opacity(loading ? 0.5 : 1)
                    } else if error == nil {
                        ForEach(sources) { _ in
                            RoundedRectangle(cornerRadius: 16).fill(Theme.card).frame(height: 240)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .navigationTitle("Insights")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let csv { ShareLink(item: csv, preview: SharePreview(csv.fileName)) { Label("CSV", systemImage: "square.and.arrow.up") } }
                if !wide { Button { showSources = true } label: { Label("Bronnen", systemImage: "checklist") } }
                Button { Task { await load() } } label: { Label("Vernieuwen", systemImage: "arrow.clockwise") }
            }
        }
        .sheet(isPresented: $showSources) {
            NavigationStack {
                Form { sourceList }
                    .navigationTitle("Bronnen")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { showSources = false } } }
            }
            .presentationDetents([.medium, .large])
            .preferredColorScheme(.dark)
        }
        .refreshable { await load() }
        .task(id: "\(rangeRaw)|\(offset)|\(session.refreshTick)") { await load() }
        .onChange(of: rangeRaw) { _, _ in selection = nil }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bronnen").font(.headline)
            Text("Vink aan wat je wilt vergelijken. Alle grafieken volgen dezelfde periode.")
                .font(.caption).foregroundStyle(Theme.muted).padding(.bottom, 8)
            ForEach(Metric.allCases) { m in
                let on = sources.contains(m)
                Button {
                    let set = on ? Set(sources).subtracting([m]) : Set(sources + [m])
                    sourcesRaw = Metric.allCases.filter { set.contains($0) }.map(\.rawValue).joined(separator: ",")
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: on ? "checkmark.square.fill" : "square")
                            .font(.title3).foregroundStyle(on ? Theme.iris2 : Theme.muted)
                        Swatch(metric: m).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.title).font(.subheadline.weight(.semibold))
                            Text(m.detail).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var csv: InsightsCSV? {
        guard let stats, !sources.isEmpty else { return nil }
        var lines = [(["dag"] + sources.map(\.title)).joined(separator: ";")]
        for d in stats.per_day {
            lines.append(([d.day] + sources.map { d.value($0).map(String.init) ?? "" }).joined(separator: ";"))
        }
        return InsightsCSV(text: lines.joined(separator: "\n"), fileName: "pasr-insights-\(stats.range.from)-\(stats.range.to).csv")
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let s = try await session.call("stats", ["days": rangeRaw, "offset": offset], as: Stats.self)
            withAnimation(.snappy) { stats = s }
            error = nil
        } catch is CancellationError {
        } catch let e as APIError where e.isUnauthorized {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// CSV om te delen (Numbers, Excel).
struct InsightsCSV: Transferable {
    let text: String
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { csv in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(csv.fileName)
            try ("\u{FEFF}" + csv.text).write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
