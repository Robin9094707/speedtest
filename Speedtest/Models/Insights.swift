import Foundation

enum ImportIssue: LocalizedError {
    case invalid
    var errorDescription: String? { "Diese Datei ist kein gültiger RJ-Speedtest-Export oder überschreitet das Importlimit (40 MB / 10.000 Tests)." }
}

extension SpeedResult {
    var validForImport: Bool {
        let rates = [download, upload, ping, jitter, duration]
        guard rates.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1_000_000_000 }),
              downloadBytes >= 0, uploadBytes >= 0, downloadBytes <= 1_000_000_000_000, uploadBytes <= 1_000_000_000_000,
              (1...8).contains(connections), date.timeIntervalSince1970.isFinite,
              date.timeIntervalSince1970 >= 0, date.timeIntervalSince1970 < 4_200_000_000,
              network.name.count <= 500, note.count <= 50_000, server.count <= 1000,
              (network.recordKey ?? "").count <= 1000, mode.count <= 100, (serverID ?? "").count <= 1000,
              (budgetMB ?? 0) >= 0, (budgetMB ?? 0) <= 100_000,
              (tags ?? []).count <= 12, (tags ?? []).allSatisfy({ $0.count <= 40 }),
              (placeLabel ?? "").count <= 100, (recoveryAttempts ?? 0) >= 0, (recoveryAttempts ?? 0) <= 100 else { return false }
        for samples in [downloadSamples, uploadSamples] {
            guard samples.count <= 2000, Set(samples.map(\.seconds)).count == samples.count,
                  samples.allSatisfy({ $0.mbps.isFinite && $0.mbps >= 0 && $0.mbps <= 1_000_000_000 && $0.seconds.isFinite && $0.seconds >= 0 && $0.seconds <= 3600 }) else { return false }
        }
        if let location {
            guard location.latitude.isFinite, location.longitude.isFinite, location.accuracy.isFinite,
                  (-90...90).contains(location.latitude), (-180...180).contains(location.longitude),
                  (0...1_000_000).contains(location.accuracy), location.timestamp.timeIntervalSince1970.isFinite else { return false }
        }
        return true
    }
    func sameServer(as other: SpeedResult) -> Bool {
        if let serverID, let otherID = other.serverID { return serverID == otherID }
        return server == other.server
    }
    var searchText: String { [network.name, server, note, placeLabel ?? "", (tags ?? []).joined(separator: " ")].joined(separator: " ") }
    var shortLabel: String { "\(placeLabel ?? network.name) · \(date.formatted(date: .abbreviated, time: .shortened))" }
}

enum InsightMath {
    static func median(_ values: [Double]) -> Double { SpeedMath.median(values.filter { $0.isFinite }) }
    static func change(from old: Double, to new: Double) -> String {
        guard old > 0 else { return "Keine Prozentbasis" }
        let value = (new - old) / old * 100
        return "\(value > 0 ? "+" : "")\(SpeedMath.number(value)) %"
    }
    static func transferTime(gigabytes: Double, mbps: Double) -> String {
        guard mbps > 0, mbps.isFinite else { return "Nicht berechenbar" }
        let seconds = gigabytes * 8000 / mbps
        if seconds < 60 { return "ca. \(Int(ceil(seconds))) Sekunden" }
        if seconds < 3600 { return "ca. \(Int(ceil(seconds / 60))) Minuten" }
        if seconds < 86400 { return "ca. \(SpeedMath.number(seconds / 3600)) Stunden" }
        return "ca. \(SpeedMath.number(seconds / 86400)) Tage"
    }
}
