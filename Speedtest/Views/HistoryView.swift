import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var filter = "Alle"
    @State private var selected: SpeedResult?
    @State private var deletion: SpeedResult?
    @State private var favoritesOnly = false
    @State private var sort = "Neueste"
    @State private var days = 0
    @State private var compare = false
    private var filtered: [SpeedResult] {
        let cutoff = days == 0 ? Date.distantPast : Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let values = store.results.filter {
            (filter == "Alle" || $0.network.kind.rawValue == filter) &&
            (!favoritesOnly || $0.favorite == true) && $0.date >= cutoff &&
            (query.isEmpty || $0.searchText.localizedCaseInsensitiveContains(query))
        }
        switch sort {
        case "Download": return values.sorted { $0.download > $1.download }
        case "Upload": return values.sorted { $0.upload > $1.upload }
        case "Niedrigster Ping": return values.sorted { $0.ping < $1.ping }
        default: return values.sorted { $0.date > $1.date }
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
                                        .swipeActions(edge: .leading) {
                                            Button { store.toggleFavorite(result.id) } label: {
                                                Label(result.favorite == true ? "Entfernen" : "Favorit", systemImage: "star.fill")
                                            }.tint(.orange)
                                        }
                                        .swipeActions { Button("Löschen", role: .destructive) { deletion = result } }
                                }
                            } header: { Text("\(filtered.count) Messungen") }
                        }.listStyle(.plain).scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Dein Verlauf")
            .searchable(text: $query, prompt: "Netz, Ort, Server, Tag oder Notiz")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { compare = true } label: { Label("Vergleichen", systemImage: "arrow.left.arrow.right") }
                        .disabled(store.results.count < 2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Nur Favoriten", isOn: $favoritesOnly)
                        Picker("Sortierung", selection: $sort) {
                            ForEach(["Neueste", "Download", "Upload", "Niedrigster Ping"], id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Zeitraum", selection: $days) {
                            Text("Alle Zeiten").tag(0); Text("7 Tage").tag(7); Text("30 Tage").tag(30); Text("90 Tage").tag(90)
                        }
                    } label: { Image(systemName: favoritesOnly || days != 0 || sort != "Neueste" ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") }
                }
            }
            .sheet(isPresented: $compare) { ComparisonSelectionView() }
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
                if QualityProfile(result).available {
                    Text("\(QualityProfile(result).points) P").font(.system(size: 10, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.cyan.opacity(0.12), in: Capsule()).foregroundStyle(.cyan)
                        .accessibilityLabel("RJ Score \(QualityProfile(result).points) von 100")
                }
                if result.favorite == true { Image(systemName: "star.fill").foregroundStyle(.yellow) }
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
            if let place = result.placeLabel { Label(place, systemImage: "mappin.and.ellipse").font(.caption.weight(.semibold)).foregroundStyle(.cyan) }
            if let tags = result.tags, !tags.isEmpty {
                Text(tags.map { "#" + $0 }.joined(separator: "  ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if !result.note.isEmpty { Label(result.note, systemImage: "note.text").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }.padding(.vertical, 10).accessibilityElement(children: .combine)
    }
}

struct RecordsView: View {
    @Environment(\.dismiss) private var dismiss
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
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
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
