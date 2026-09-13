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
    func toggleFavorite(_ id: UUID) {
        var updated = results
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].favorite = !(updated[index].favorite ?? false)
        commit(updated)
    }
    func updateTags(_ id: UUID, text: String) {
        var updated = results
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        let tags = text.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)) }.filter { !$0.isEmpty }
        updated[index].tags = Array(Set(tags)).sorted().prefix(12).map { $0 }
        commit(updated)
    }
    func readImport(_ url: URL) throws -> [SpeedResult] {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 40_000_000 else { throw ImportIssue.invalid }
        let data = try Data(contentsOf: url)
        guard data.count <= 40_000_000 else { throw ImportIssue.invalid }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(Archive.self, from: data)
        guard archive.version == 1, archive.results.count <= 10_000,
              archive.results.allSatisfy({ $0.validForImport }) else { throw ImportIssue.invalid }
        var seen = Set(results.map(\.id))
        return archive.results.filter { seen.insert($0.id).inserted }
    }
    func mergeImport(_ incoming: [SpeedResult]) {
        var seen = Set(results.map(\.id))
        let added = incoming.filter { $0.validForImport && seen.insert($0.id).inserted }
        commit((results + added).sorted { $0.date > $1.date })
    }
    func renameNetwork(key: String, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        settings.networkNames[key] = name
        var updated = results
        for index in updated.indices where updated[index].network.recordKey == key {
            updated[index].network.name = name
        }
        commit(updated)
    }
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
