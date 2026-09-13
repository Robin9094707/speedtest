import SwiftUI

struct RouterLabView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var engine: SpeedtestEngine
    @EnvironmentObject private var network: NetworkService
    @EnvironmentObject private var location: LocationService
    @AppStorage("routerStudyID") private var studyID = ""
    @State private var place = "Fenster"
    @State private var cellularPrompt = false
    @State private var selected: SpeedResult?
    private var sessionResults: [SpeedResult] {
        store.results.filter { $0.experimentID?.uuidString == studyID }.sorted { $0.date < $1.date }
    }
    private var settingsMatch: Bool {
        guard let baseline = sessionResults.first else { return true }
        let sameServer = baseline.serverID.map { $0 == store.settings.measurementServer.id } ?? (baseline.server == store.settings.measurementServer.name)
        return sameServer && (baseline.budgetMB == nil || baseline.budgetMB == store.settings.budgetMB) && baseline.mode == store.settings.mode.rawValue && baseline.connections == store.settings.connections
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("DEIN ROUTER-LABOR", systemImage: "wifi.router").font(.caption.bold()).tracking(2).foregroundStyle(.cyan)
                    Text("Welcher Platz\nholt mehr heraus?").font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("1. Stelle deinen Router an einen Platz.\n2. Warte auf eine stabile Verbindung.\n3. Benenne den Platz und starte einen Test.\n4. Wiederhole das an weiteren Plätzen.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Halte das iPhone relativ zum Router möglichst gleich. Gleicher Server, gleiches Profil, ähnliche Tageszeit. Jeder Start überträgt bis ca. \(store.settings.budgetMB) MB; drei Tests entsprechend bis ca. \(store.settings.budgetMB * 3) MB.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Platz benennen", text: $place).font(.title3.weight(.semibold)).disabled(engine.isRunning)
                        .onChange(of: place) { _, value in if value.count > 100 { place = String(value.prefix(100)) } }
                    HStack {
                        ForEach(["Fenster", "Regal", "Flur"], id: \.self) { name in
                            Button(name) { place = name }.buttonStyle(.bordered).disabled(engine.isRunning)
                        }
                    }
                    Label(network.identity(alias: "", names: store.settings.networkNames).name, systemImage: network.kind.symbol)
                        .font(.subheadline)
                    Text("\(store.settings.measurementServer.name) · \(store.settings.mode.rawValue) · \(store.settings.connections) Streams")
                        .font(.caption).foregroundStyle(.secondary)
                    if !settingsMatch {
                        Text("Server, Datenlimit oder Messprofil wurden seit dem ersten Test geändert. Stelle dieselben Einstellungen wieder her oder beginne eine neue Runde.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { clock in
                        let remaining = max(0, engine.cooldown(for: store.settings.measurementServer)?.timeIntervalSince(clock.date) ?? 0)
                        Button {
                            if engine.isRunning { engine.cancel() }
                            else if network.kind == .cellular && store.settings.confirmCellular { cellularPrompt = true }
                            else { start() }
                        } label: {
                            Label(engine.isRunning ? "Test stoppen" : remaining > 0 ? "Messserver pausiert" : "Diesen Platz messen", systemImage: engine.isRunning ? "stop.fill" : "bolt.fill")
                                .font(.headline).frame(maxWidth: .infinity).padding(18)
                        }.buttonStyle(PrimaryGlassButton())
                            .disabled(!engine.isRunning && (!network.connected || place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !settingsMatch || remaining > 0))
                    }
                    if engine.isRunning {
                        Text("\(engine.phase.rawValue) · \(SpeedMath.number(engine.liveSpeed)) Mbit/s").font(.title3.bold()).monospacedDigit()
                        ProgressView(value: engine.progress)
                    }
                    if let message = engine.recoveryMessage { Text(message).font(.caption).foregroundStyle(.orange) }
                    if let error = engine.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
                }.padding(20).glassPanel()
                if !sessionResults.isEmpty { results }
                HStack {
                    Button("Neue Runde") { studyID = UUID().uuidString }.disabled(engine.isRunning || sessionResults.isEmpty)
                    Spacer()
                    Menu("Frühere Runden") {
                        ForEach(previousStudies, id: \.self) { id in
                            let values = store.results.filter { $0.experimentID?.uuidString == id }
                            Button("\(values.last?.date.formatted(date: .abbreviated, time: .shortened) ?? "Runde") · \(values.count) Tests") { studyID = id }
                        }
                    }.disabled(engine.isRunning || previousStudies.isEmpty)
                }.font(.subheadline)
                Text("Runden und Platznamen bleiben im Verlauf gespeichert. Es starten keine Tests automatisch. Die beste Einzelmessung ist eine Momentaufnahme – miss wichtige Plätze zur Absicherung mehrfach.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(AmbientBackground()).navigationTitle("Router-Standorte").navigationBarTitleDisplayMode(.inline)
            .onAppear { if UUID(uuidString: studyID) == nil { studyID = UUID().uuidString } }
            .sheet(item: $selected) { ResultDetailView(resultID: $0.id) }
            .alert("Über Mobilfunk messen?", isPresented: $cellularPrompt) {
                Button("Abbrechen", role: .cancel) {}
                Button("Test starten") { start() }
            } message: { Text("Dieser einzelne Test überträgt bis ca. \(store.settings.budgetMB) MB Nutzdaten.") }
    }
    private var previousStudies: [String] {
        var seen = Set<String>()
        return store.results.compactMap { $0.experimentID?.uuidString }.filter { seen.insert($0).inserted }
    }
    private var results: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Diese Runde · \(sessionResults.count) Messungen").font(.headline)
            if sessionResults.count >= 2, let best = sessionResults.max(by: { $0.download < $1.download }) {
                Label("Höchster Download: \(best.placeLabel ?? "Platz")", systemImage: "trophy.fill").foregroundStyle(.yellow).font(.subheadline.weight(.semibold))
            }
            ForEach(sessionResults.reversed()) { result in
                Button { selected = result } label: { ResultRow(result: result, unit: store.settings.unit) }.buttonStyle(.plain)
                Divider()
            }
            if let last = sessionResults.last {
                QualityCard(result: last).id(last.id)
            }
            if sessionResults.count >= 2, let first = sessionResults.first, let last = sessionResults.last {
                NavigationLink { ComparisonDetailView(a: first, b: last) } label: {
                    Label("Ersten und letzten Platz vergleichen", systemImage: "arrow.left.arrow.right")
                }
            }
        }.padding(20).glassPanel()
    }
    private func start() {
        guard network.connected, settingsMatch, let id = UUID(uuidString: studyID) else { return }
        let name = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        engine.start(store: store, network: network.identity(alias: "", names: store.settings.networkNames), location: location, placeLabel: name, experimentID: id)
    }
}
