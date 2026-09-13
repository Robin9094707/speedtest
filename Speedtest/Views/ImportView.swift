import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var engine: SpeedtestEngine
    @State private var picking = false
    @State private var incoming: [SpeedResult] = []
    @State private var message: String?
    @State private var loaded = false
    var body: some View {
        Form {
            Section {
                Label("Deine Messungen zurückholen", systemImage: "square.and.arrow.down").font(.headline)
                Text("Wähle einen zuvor mit RJ Speedtest erstellten JSON-Export. Bereits vorhandene Messungen bleiben erhalten; identische Test-IDs werden übersprungen. Einstellungen werden nicht verändert.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("JSON-Datei auswählen") { picking = true }.disabled(engine.isRunning)
            }
            if loaded {
                Section("Vorschau") {
                    LabeledContent("Neue Messungen", value: String(incoming.count))
                    LabeledContent("Davon mit Standort", value: String(incoming.filter { $0.location != nil }.count))
                    LabeledContent("Davon Favoriten", value: String(incoming.filter { $0.favorite == true }.count))
                    Button("\(incoming.count) Messungen hinzufügen") {
                        let before = store.results.count
                        store.mergeImport(incoming)
                        let added = store.results.count - before
                        if added > 0 { incoming = []; loaded = false; message = "\(added) Messungen wurden wiederhergestellt." }
                        else { message = store.storageError ?? "Alle Messungen sind bereits vorhanden." }
                    }.disabled(incoming.isEmpty || engine.isRunning)
                }
            }
            if let message { Section { Text(message).font(.subheadline) } }
            Section {
                Text("Die Datei wird lokal gelesen. Maximal 40 MB und 10.000 Tests je Import. Favoriten, Tags, Notizen, Router-Runden und gespeicherte Orte werden mit übernommen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Verlauf wiederherstellen").navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
                do {
                    incoming = try store.readImport(result.get())
                    loaded = true
                    message = incoming.isEmpty ? "Keine neuen Messungen: Die Datei ist leer oder alle Test-IDs sind bereits vorhanden." : nil
                } catch { incoming = []; loaded = false; message = "Import nicht möglich: \(error.localizedDescription)" }
            }
    }
}
