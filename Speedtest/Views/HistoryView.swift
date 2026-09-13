import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var filter = "Alle"
    @State private var selected: SpeedResult?
    @State private var deletion: SpeedResult?
    private var filtered: [SpeedResult] {
        store.results.filter {
            (filter == "Alle" || $0.network.kind.rawValue == filter) &&
            (query.isEmpty || $0.network.name.localizedCaseInsensitiveContains(query) || $0.note.localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                VStack(spacing: 0) {
                    Picker("Verbindung", selection: $filter) {
                        Text("Alle").tag("Alle"); Text("WLAN").tag("WLAN"); Text("Mobilfunk").tag("Mobilfunk")
                    }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 10)
                    if filtered.isEmpty {
                        EmptyState(symbol: "clock.arrow.circlepath", title: store.results.isEmpty ? "Dein erster Test wartet" : "Keine Treffer",
                                   message: store.results.isEmpty ? "Abgeschlossene Speedtests werden hier automatisch gespeichert." : "Ändere den Filter oder die Suche.")
                    } else {
                        List {
                            Section {
                                ForEach(filtered) { result in
                                    Button { selected = result } label: { ResultRow(result: result, unit: store.settings.unit) }
                                        .buttonStyle(.plain).listRowBackground(Color.clear)
                                        .swipeActions { Button("Löschen", role: .destructive) { deletion = result } }
                                }
                            } header: { Text("\(filtered.count) Messungen") }
                        }.listStyle(.plain).scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Dein Verlauf")
            .searchable(text: $query, prompt: "Netz oder Notiz suchen")
            .sheet(item: $selected) { ResultDetailView(resultID: $0.id) }
            .alert("Speedtest löschen?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                Button("Nein", role: .cancel) { deletion = nil }
                Button("Ja, löschen", role: .destructive) {
                    if let deletion { store.remove(deletion.id) }; deletion = nil
                }
            } message: { Text("Dieser Test wird aus Verlauf, Karte und Rekordwertung entfernt.") }
        }
    }
}

struct ResultRow: View {
    let result: SpeedResult
    let unit: SpeedUnit
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(result.network.name, systemImage: result.network.kind.symbol).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                if result.location != nil { Image(systemName: "mappin.circle.fill").foregroundStyle(.cyan) }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Label(unit.format(result.download), systemImage: "arrow.down").foregroundStyle(.cyan)
                Label(unit.format(result.upload), systemImage: "arrow.up").foregroundStyle(Palette.upload)
                Text(unit.rawValue).font(.caption).foregroundStyle(.secondary)
            }.font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            HStack {
                Text(result.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                Spacer()
                Text("\(SpeedMath.number(result.ping)) ms")
            }.font(.caption).foregroundStyle(.secondary)
            if !result.note.isEmpty { Label(result.note, systemImage: "note.text").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }.padding(.vertical, 10).accessibilityElement(children: .combine)
    }
}

struct RecordsView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if store.records.isEmpty {
                    EmptyState(symbol: "trophy", title: "Platz für Bestmarken",
                               message: "Starte einen Test über Mobilfunk oder ein benanntes WLAN. Jedes Netz bekommt seine eigenen Rekorde.")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Jedes Netz.\nDeine Bestleistung.").font(.system(size: 32, weight: .bold, design: .rounded))
                                Text("\(store.results.count) Tests · \(store.records.count) Netzprofile").font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical, 10)
                            ForEach(store.records) { record in
                                VStack(alignment: .leading, spacing: 18) {
                                    HStack {
                                        Image(systemName: "trophy.fill").foregroundStyle(.yellow).font(.title2)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(record.name).font(.headline)
                                            Label("\(record.count) Messungen", systemImage: record.kind.symbol).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    HStack(spacing: 20) {
                                        best("Download", record.download, .cyan)
                                        Divider()
                                        best("Upload", record.upload, Palette.upload)
                                    }.fixedSize(horizontal: false, vertical: true)
                                }.padding(22).glassPanel()
                            }
                            Text("Bestwerte werden aus den gespeicherten Tests berechnet. Gelöschte Messungen zählen nicht mehr. Gleiche SSIDs werden zusammengefasst; manuell benannte WLANs bilden eigene Profile. Mobilfunk ohne Profilname wird gemeinsam gewertet.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
                    }
                }
            }.navigationTitle("Deine Rekorde")
        }
    }
    private func best(_ label: String, _ speed: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(color)
            Text(store.settings.unit.format(speed)).font(.system(size: 30, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.5)
            Text(store.settings.unit.rawValue).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
