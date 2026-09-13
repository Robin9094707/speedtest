import SwiftUI

struct ServerSelectionView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var engine: SpeedtestEngine
    @Environment(\.dismiss) private var dismiss
    @StateObject private var directory = ServerDirectory()
    @State private var search = ""
    private var choices: [MeasurementServer] {
        var all = [MeasurementServer.cloudflare]
        let selected = store.settings.measurementServer
        if selected.id != MeasurementServer.cloudflare.id { all.append(selected) }
        all += directory.servers.filter { server in !all.contains { $0.id == server.id } }
        return all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Wähle möglichst einen Server in deiner Nähe. Bei HTTP 403 oder einer Serverpause kannst du hier einen anderen Anbieter auswählen.")
                    Text("Die Betreiber erhalten deine IP-Adresse. Standorte, Notizen und gespeicherte Ergebnisse werden nicht übertragen. Andere Server können andere Geschwindigkeiten ergeben.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        Task { await directory.refresh() }
                    } label: {
                        HStack {
                            Label("Öffentliche Server laden", systemImage: "arrow.clockwise")
                            Spacer()
                            if directory.loading { ProgressView() }
                        }
                    }.disabled(directory.loading)
                    if let message = directory.message { Text(message).font(.caption).foregroundStyle(.orange) }
                } footer: {
                    Text("Liste von LibreSpeed · ausschließlich HTTPS. Manche gelisteten Server unterstützen HTTPS möglicherweise nicht. Es werden keine Geschwindigkeitstests im Hintergrund gestartet.")
                }
                Section("WLAN-Erkennung") {
                    Text("Die App fragt das verbundene WLAN über Apples WLAN-Schnittstellen ab und merkt sich eigene Namen pro verfügbarer Kennung. Gleichnamige WLANs werden als ein Netz behandelt; Mesh-Zugangspunkte bleiben so zusammen.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Standortfreigabe mit genauer Position und „Access WiFi Information“ im Signierungsprofil sind normalerweise nötig. „Lokales Netzwerk“ allein gibt keinen WLAN-Namen frei. Ohne WLAN-Kennung bleibt die Zuordnung manuell.")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Gespeicherte eigene Namen", value: String(store.settings.networkNames.count))
                }

                Section("Messserver") {
                    ForEach(choices) { server in
                        Button {
                            guard !engine.isRunning else { return }
                            store.settings.measurementServer = server
                            engine.errorMessage = nil
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(server.name).foregroundStyle(.primary)
                                    Text(server.id).font(.caption).foregroundStyle(.secondary)
                                    if let until = engine.cooldown(for: server), until > Date() {
                                        Text("Pause bis \(until.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                if server.id == store.settings.measurementServer.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                            }
                        }.disabled(engine.isRunning)
                    }
                }
            }
            .navigationTitle("Messserver")
            .searchable(text: $search, prompt: "Ort oder Anbieter suchen")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var engine: SpeedtestEngine
    @EnvironmentObject private var location: LocationService
    @State private var deleteAll = false
    @State private var shareURL: URL?
    @State private var exportError: String?
    @State private var showShare = false
    @State private var showNews = false
    @State private var showServers = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Testdauer", selection: $store.settings.mode) {
                        ForEach(TestMode.allCases) { Text("\($0.rawValue) · \(Int($0.seconds)) s je Richtung").tag($0) }
                    }
                    Picker("Parallele Verbindungen", selection: $store.settings.connections) {
                        ForEach([1, 2, 4, 6, 8], id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Datenlimit pro Test", selection: $store.settings.budgetMB) {
                        Text("256 MB").tag(256); Text("1 GB").tag(1024); Text("4 GB").tag(4096)
                    }
                    Toggle("Vor Mobilfunktest fragen", isOn: $store.settings.confirmCellular)
                    Toggle("Display beim Test wach halten", isOn: $store.settings.keepAwake)
                } header: { Text("Messung") } footer: {
                    Text("Ein Test misst erst Download, dann Upload. Je Richtung gilt die halbe Datenmenge. Bei Erreichen des Limits endet die Phase früher. 1 GB entspricht hier 1.024 MB Nutzdaten; Protokolldaten kommen hinzu. Mehrere Verbindungen können schnelle Anschlüsse besser auslasten.")
                }.disabled(engine.isRunning)

                Section("WLAN-Erkennung") {
                    Text("Die App fragt das verbundene WLAN über Apples WLAN-Schnittstellen ab und merkt sich eigene Namen pro verfügbarer Kennung. Gleichnamige WLANs werden als ein Netz behandelt; Mesh-Zugangspunkte bleiben so zusammen.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Standortfreigabe mit genauer Position und „Access WiFi Information“ im Signierungsprofil sind normalerweise nötig. „Lokales Netzwerk“ allein gibt keinen WLAN-Namen frei. Ohne WLAN-Kennung bleibt die Zuordnung manuell.")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Gespeicherte eigene Namen", value: String(store.settings.networkNames.count))
                }

                Section("Messserver") {
                    Button { showServers = true } label: {
                        LabeledContent("Server wechseln", value: store.settings.measurementServer.name)
                    }.disabled(engine.isRunning)
                    Text("Bei einer Ablehnung oder Pause kannst du einen anderen Anbieter auswählen. Ein Test nutzt durchgehend denselben Server.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Dein Look") {
                    Picker("Einheit", selection: $store.settings.unit) { ForEach(SpeedUnit.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Tacho-Skala", selection: $store.settings.gaugeScale) {
                        ForEach(GaugeScale.allCases) { Text($0.label).tag($0) }
                    }.disabled(engine.isRunning)
                    Picker("Erscheinungsbild", selection: $store.settings.appearance) {
                        ForEach(["System", "Dunkel", "Hell"], id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Akzentfarbe", selection: $store.settings.accent) {
                        ForEach(["Polarlicht", "Ozean", "Violett", "Sonnenuntergang"], id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Animationen", isOn: $store.settings.animations)
                    Toggle("Haptisches Feedback", isOn: $store.settings.haptics)
                }

                Section {
                    Toggle("Speedtest fühlen", isOn: $store.settings.liveHaptics)
                        .disabled(!store.settings.haptics)
                    Slider(value: $store.settings.hapticStrength, in: 0.2...1, step: 0.05) {
                        Text("Haptik-Stärke")
                    } minimumValueLabel: { Image(systemName: "waveform.path") }
                      maximumValueLabel: { Image(systemName: "waveform") }
                        .disabled(!store.settings.haptics || !store.settings.liveHaptics)
                    LabeledContent("Stärke", value: "\(Int((store.settings.hapticStrength * 100).rounded())) %")
                } header: { Text("Live-Haptik") } footer: {
                    Text("Je näher die Geschwindigkeit am Skalenende liegt, desto kräftiger und schneller pulsiert dein iPhone. Oberhalb der Skala bleibt die Haptik am Maximum; die Zahl zeigt weiterhin die echte Geschwindigkeit. Die Wirkung hängt vom Gerät und den iOS-Haptikeinstellungen ab.")
                }

                Section {
                    Toggle("Standorte zu Tests speichern", isOn: $store.settings.locationEnabled)
                        .onChange(of: store.settings.locationEnabled) { _, enabled in location.activate(enabled: enabled) }
                        .disabled(engine.isRunning)
                    Label(location.message, systemImage: "location").font(.subheadline).foregroundStyle(.secondary)
                    Button("Standortfreigabe in iOS öffnen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } header: { Text("Standort & Datenschutz") } footer: {
                    Text("Standorte, Notizen und Netzprofile werden nur auf diesem Gerät gespeichert. Es gibt kein Konto, keine Werbung und kein Tracking-SDK. Messanfragen gehen an den gewählten Anbieter; die Serverliste kommt von LibreSpeed; Karten werden von Apple bereitgestellt. Diese Dienste erhalten technisch erforderliche Verbindungsdaten. Standort ausschalten entfernt keine früher gespeicherten Orte.")
                }

                Section {
                    LabeledContent("Gespeicherte Tests", value: String(store.results.count))
                    Button { export(json: false) } label: { Label("Verlauf als CSV exportieren", systemImage: "tablecells") }
                        .disabled(store.results.isEmpty)
                    Button { export(json: true) } label: { Label("Verlauf als JSON exportieren", systemImage: "square.and.arrow.up") }
                        .disabled(store.results.isEmpty)
                    Button("Alle Messungen löschen", role: .destructive) { deleteAll = true }
                        .disabled(store.results.isEmpty || engine.isRunning)
                } header: { Text("Deine Daten") } footer: { Text("Exporte enthalten auch gespeicherte Standorte und Notizen. Teile sie nur, wenn du diese Angaben weitergeben möchtest.") }

                Section("Version 2.0") {
                    Button("Alle Neuerungen ansehen") { showNews = true }
                    NavigationLink("JSON-Verlauf wiederherstellen") { ImportView() }.disabled(engine.isRunning)
                }

                Section("Über RJ Speedtest") {
                    LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                    LabeledContent("Entwickelt für", value: "Robin Juhas")
                    Link("Quellcode & Builds", destination: URL(string: "https://github.com/Robin9094707/speedtest")!)
                    Link("LibreSpeed & Serververzeichnis", destination: URL(string: "https://github.com/librespeed/speedtest-cli")!)
                    Link("Cloudflare-Messendpunkte", destination: URL(string: "https://github.com/cloudflare/speedtest")!)
                    Link("Cloudflare-Datenschutz", destination: URL(string: "https://www.cloudflare.com/privacypolicy/")!)
                    Text("Natives Liquid Glass unter iOS 26 oder neuer; Material-Oberfläche unter iOS 17–18. Die Skala wächst automatisch über 1.000 Mbit/s hinaus. HTTP-Ping ist keine ICMP-Messung. Öffentliche Messendpunkte haben keine Verfügbarkeitsgarantie.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einstellungen")
            .sheet(isPresented: $showNews) { VersionTwoView() }
            .sheet(isPresented: $showServers) { ServerSelectionView() }
            .alert("Alle Messungen löschen?", isPresented: $deleteAll) {
                Button("Abbrechen", role: .cancel) {}
                Button("Alles löschen", role: .destructive) { store.removeAll() }
            } message: { Text("Verlauf, gespeicherte Orte, Notizen und Rekorde werden gelöscht. Exportiere deine Daten vorher, wenn du sie behalten möchtest.") }
            .sheet(isPresented: $showShare) { if let shareURL { ShareSheet(items: [shareURL]) } }
            .alert("Export fehlgeschlagen", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: { Text(exportError ?? "") }
        }
    }
    private func export(json: Bool) {
        do { shareURL = try store.export(json: json); showShare = true }
        catch { exportError = error.localizedDescription }
    }
}
