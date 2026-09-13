import Foundation
import Combine

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var results: [SpeedResult] = []
    @Published var settings = AppSettings() { didSet { saveSettings() } }
    @Published var storageError: String?
    private let directory: URL
    private var loading = true
    private struct Archive: Codable { var version = 1; var results: [SpeedResult] }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RJSpeedtest", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let settingsURL = self.directory.appendingPathComponent("settings.json")
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                settings = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: settingsURL))
                settings.connections = min(8, max(1, settings.connections))
                if ![256, 1024, 4096].contains(settings.budgetMB) { settings.budgetMB = 1024 }
            }
            let url = self.directory.appendingPathComponent("results.json")
            if FileManager.default.fileExists(atPath: url.path) {
                let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
                guard archive.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                results = archive.results.sorted { $0.date > $1.date }
            }
        } catch {
            // Preserve an unreadable file before any future save; never silently overwrite history.
            let url = self.directory.appendingPathComponent("results.json")
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.copyItem(at: url, to: self.directory.appendingPathComponent("recovery-\(UUID().uuidString).json"))
            }
            storageError = "Gespeicherte Daten konnten nicht vollständig geladen werden: \(error.localizedDescription)"
        }
        loading = false
    }

    var records: [NetworkRecord] { RecordBook.records(results) }
    func add(_ result: SpeedResult) { commit([result] + results) }
    func remove(_ id: UUID) { commit(results.filter { $0.id != id }) }
    func removeAll() { commit([]) }
    func updateNote(_ id: UUID, note: String) {
        var updated = results
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].note = note
        commit(updated)
    }
    private func commit(_ updated: [SpeedResult]) {
        do {
            let data = try JSONEncoder().encode(Archive(results: updated))
            try data.write(to: directory.appendingPathComponent("results.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
            results = updated
        } catch { storageError = "Änderung konnte nicht gespeichert werden: \(error.localizedDescription)" }
    }
    private func saveSettings() {
        guard !loading else { return }
        do {
            try JSONEncoder().encode(settings).write(to: directory.appendingPathComponent("settings.json"), options: .atomic)
        } catch { storageError = "Einstellungen konnten nicht gespeichert werden: \(error.localizedDescription)" }
    }
    func export(json: Bool) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(json ? "RJ-Speedtest-Verlauf.json" : "RJ-Speedtest-Verlauf.csv")
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(Archive(results: results)).write(to: url, options: .atomic)
        } else {
            var rows = ["Datum;Netz;Verbindung;Download_Mbit_s;Upload_Mbit_s;HTTP_Latenz_ms;Jitter_ms;Bytes;Breitengrad;Längengrad;Notiz"]
            let date = ISO8601DateFormatter()
            for r in results {
                let fields = [date.string(from: r.date), r.network.name, r.network.kind.rawValue,
                              String(r.download), String(r.upload), String(r.ping), String(r.jitter), String(r.totalBytes),
                              r.location.map { String($0.latitude) } ?? "", r.location.map { String($0.longitude) } ?? "", r.note]
                rows.append(fields.map(SpeedMath.csvField).joined(separator: ";"))
            }
            try ("\u{FEFF}" + rows.joined(separator: "\r\n")).write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }
}
