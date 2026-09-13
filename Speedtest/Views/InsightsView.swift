import SwiftUI
import Charts

struct InsightsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var networkKey = "all"
    @State private var days = 30
    @State private var compare = false
    @State private var records = false
    private var filtered: [SpeedResult] {
        let cutoff = days == 0 ? Date.distantPast : Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return store.results.filter { $0.date >= cutoff && (networkKey == "all" || $0.network.recordKey == networkKey) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Verstehen. Vergleichen.\nBesser aufstellen.")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Dein Werkzeugkasten für echte Netz-Messungen.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    tools
                    filters
                    if filtered.isEmpty {
                        EmptyState(symbol: "chart.xyaxis.line", title: "Noch keine Messwerte", message: "Starte einen Test oder ändere Netz und Zeitraum.")
                    } else {
                        summary
                        QualityInsightsCard(results: filtered)
                        trend
                        networkOverview
                    }
                }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }.background(AmbientBackground()).navigationTitle("Einblicke")
                .sheet(isPresented: $compare) { ComparisonSelectionView() }
                .sheet(isPresented: $records) { RecordsView() }
        }
    }
    private var tools: some View {
        VStack(spacing: 12) {
            NavigationLink { RouterLabView() } label: {
                ToolLabel(title: "Router-Standort finden", subtitle: "Fenster, Regal oder Flur: direkt vergleichen", symbol: "wifi.router")
            }
            Button { compare = true } label: {
                ToolLabel(title: "A / B vergleichen", subtitle: "Zwei Messungen, alle Unterschiede", symbol: "arrow.left.arrow.right")
            }
            NavigationLink { TransferCalculatorView() } label: {
                ToolLabel(title: "Wie lange dauert der Download?", subtitle: "Transferzeiten mit deinen Messwerten", symbol: "shippingbox")
            }
            Button { records = true } label: {
                ToolLabel(title: "Deine Rekorde", subtitle: "Bestmarken für jedes Netz", symbol: "trophy")
            }
        }.buttonStyle(.plain)
    }
    private var filters: some View {
        VStack {
            Picker("Netz", selection: $networkKey) {
                Text("Alle Netze").tag("all")
                ForEach(store.records) { Text($0.name).tag($0.id) }
            }
            Picker("Zeitraum", selection: $days) {
                Text("7 Tage").tag(7); Text("30 Tage").tag(30); Text("90 Tage").tag(90); Text("Alles").tag(0)
            }.pickerStyle(.segmented)
        }.padding(16).glassPanel()
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Dein typisches Tempo").font(.headline); Spacer(); Text("\(filtered.count) Tests").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 12) {
                MetricTile(title: "Download-Median", symbol: "arrow.down", value: store.settings.unit.format(InsightMath.median(filtered.map(\.download))), unit: store.settings.unit.rawValue, color: .cyan)
                MetricTile(title: "Upload-Median", symbol: "arrow.up", value: store.settings.unit.format(InsightMath.median(filtered.map(\.upload))), unit: store.settings.unit.rawValue, color: Palette.upload)
            }
            HStack {
                Label("\(SpeedMath.number(InsightMath.median(filtered.map(\.ping)))) ms Median", systemImage: "timer")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: filtered.reduce(Int64(0)) { $0 + $1.totalBytes }, countStyle: .decimal))
            }.font(.caption).foregroundStyle(.secondary)
            Text("Der Median ist der mittlere Messwert und reagiert weniger auf Ausreißer. Datenverbrauch zählt nur gespeicherte Tests inklusive ihrer Wiederholungen; abgebrochene Tests und Protokolldaten fehlen.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var trend: some View {
        let values = Array(filtered.sorted { $0.date < $1.date }.suffix(200))
        return VStack(alignment: .leading, spacing: 14) {
            Text("Geschwindigkeit über die Zeit").font(.headline)
            Chart(values) { result in
                PointMark(x: .value("Datum", result.date), y: .value("Mbit/s", result.download))
                    .foregroundStyle(by: .value("Richtung", "Download"))
                PointMark(x: .value("Datum", result.date), y: .value("Mbit/s", result.upload))
                    .foregroundStyle(by: .value("Richtung", "Upload"))
            }
            .chartForegroundStyleScale(["Download": Color.cyan, "Upload": Palette.upload])
            .chartYScale(domain: .automatic(includesZero: true))
            .frame(height: 210)
            Text("Die letzten \(values.count) Messungen im Filter · Mbit/s. Jeder Punkt ist ein abgeschlossener Test.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).glassPanel()
    }
    private var networkOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Netze im Überblick").font(.headline)
            ForEach(store.records.filter { record in filtered.contains { $0.network.recordKey == record.id } }) { record in
                let values = filtered.filter { $0.network.recordKey == record.id }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Label(record.name, systemImage: record.kind.symbol).font(.subheadline.weight(.semibold)); Spacer(); Text("\(values.count) Tests").font(.caption) }
                    Text("Median ↓ \(SpeedMath.number(InsightMath.median(values.map(\.download)))) · ↑ \(SpeedMath.number(InsightMath.median(values.map(\.upload)))) Mbit/s")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Download-Spanne: \(SpeedMath.number(values.map(\.download).min() ?? 0))–\(SpeedMath.number(values.map(\.download).max() ?? 0)) Mbit/s")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Divider()
            }
            Text("Messungen können von verschiedenen Servern stammen. Für einen gezielten Vergleich nutze A / B und achte auf denselben Server.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).glassPanel()
    }
}

struct ToolLabel: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.cyan).frame(width: 40)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(18).glassPanel(radius: 22)
    }
}

struct TransferCalculatorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedID: UUID?
    @State private var gigabytes = 10.0
    private var result: SpeedResult? { store.results.first { $0.id == selectedID } ?? store.results.first }
    var body: some View {
        Form {
            if let result {
                Section("Messwert als Grundlage") {
                    Picker("Messung", selection: $selectedID) {
                        Text("Neuester Test").tag(nil as UUID?)
                        ForEach(store.results.prefix(100)) { Text($0.shortLabel).tag(Optional($0.id)) }
                    }
                    Text("↓ \(SpeedMath.number(result.download)) · ↑ \(SpeedMath.number(result.upload)) Mbit/s")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Dateigröße") {
                    LabeledContent("Größe", value: "\(Int(gigabytes)) GB")
                    Slider(value: $gigabytes, in: 1...200, step: 1)
                    HStack {
                        ForEach([1, 10, 50, 100, 200], id: \.self) { size in
                            Button("\(size) GB") { gigabytes = Double(size) }.buttonStyle(.bordered).font(.caption)
                        }
                    }
                }
                Section("Geschätzte Transferzeit") {
                    LabeledContent("Download", value: InsightMath.transferTime(gigabytes: gigabytes, mbps: result.download))
                    LabeledContent("Upload", value: InsightMath.transferTime(gigabytes: gigabytes, mbps: result.upload))
                }
                Section {
                    Text("Rechenwert bei konstantem Tempo. 1 GB = 1.000.000.000 Bytes. Gegenstelle, WLAN-Schwankungen und Protokollaufwand können echte Transfers verlängern. Der Rechner lädt keine Testdaten herunter.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("Starte zuerst einen Speedtest. Anschließend rechnet die App mit deiner gemessenen Geschwindigkeit.") }
        }.navigationTitle("Transferzeit").navigationBarTitleDisplayMode(.inline)
    }
}
