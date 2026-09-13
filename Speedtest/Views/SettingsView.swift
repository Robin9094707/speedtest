import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var engine: SpeedtestEngine
    @EnvironmentObject private var location: LocationService
    @State private var deleteAll = false
    @State private var shareURL: URL?
    @State private var exportError: String?
    @State private var showShare = false

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

                Section("Dein Look") {
                    Picker("Einheit", selection: $store.settings.unit) { ForEach(SpeedUnit.allCases) { Text($0.rawValue).tag($0) } }
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
                    Toggle("Standorte zu Tests speichern", isOn: $store.settings.locationEnabled)
                        .onChange(of: store.settings.locationEnabled) { _, enabled in location.activate(enabled: enabled) }
                        .disabled(engine.isRunning)
                    Label(location.message, systemImage: "location").font(.subheadline).foregroundStyle(.secondary)
                    Button("Standortfreigabe in iOS öffnen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } header: { Text("Standort & Datenschutz") } footer: {
                    Text("Standorte, Notizen und Netzprofile werden nur auf diesem Gerät gespeichert. Es gibt kein Konto, keine Werbung und kein Tracking-SDK. Messanfragen gehen an Cloudflare; Karten werden von Apple bereitgestellt. Diese Dienste erhalten technisch erforderliche Verbindungsdaten. Standort ausschalten entfernt keine früher gespeicherten Orte.")
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

                Section("Über RJ Speedtest") {
                    LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                    LabeledContent("Entwickelt für", value: "Robin Juhas")
                    Link("Quellcode & Builds", destination: URL(string: "https://github.com/Robin9094707/speedtest")!)
                    Link("Cloudflare-Messendpunkte", destination: URL(string: "https://github.com/cloudflare/speedtest")!)
                    Link("Cloudflare-Datenschutz", destination: URL(string: "https://www.cloudflare.com/privacypolicy/")!)
                    Text("Natives Liquid Glass unter iOS 26 oder neuer; Material-Oberfläche unter iOS 17–18. Die Skala wächst automatisch über 1.000 Mbit/s hinaus. HTTP-Ping ist keine ICMP-Messung. Öffentliche Messendpunkte haben keine Verfügbarkeitsgarantie.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einstellungen")
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
