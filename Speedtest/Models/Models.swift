import Foundation

enum ConnectionKind: String, Codable, CaseIterable, Identifiable {
    case wifi = "WLAN", cellular = "Mobilfunk", wired = "Ethernet", other = "Unbekannt"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .wired: return "cable.connector"
        case .other: return "network"
        }
    }
}

struct NetworkIdentity: Codable, Equatable {
    var kind: ConnectionKind
    var name: String
    // nil deliberately keeps unidentified Wi-Fi networks out of shared records.
    var recordKey: String?

    static func make(kind: ConnectionKind, ssid: String?, alias: String) -> Self {
        let label = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let wifi = ssid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch kind {
        case .wifi:
            if !wifi.isEmpty { return .init(kind: kind, name: wifi, recordKey: "wifi:ssid:\(wifi)") }
            if !label.isEmpty { return .init(kind: kind, name: label, recordKey: "wifi:manual:\(label)") }
            return .init(kind: kind, name: "WLAN ohne Namen", recordKey: nil)
        case .cellular:
            return .init(kind: kind, name: label.isEmpty ? "Mobilfunk" : label,
                         recordKey: label.isEmpty ? "cellular:all" : "cellular:manual:\(label)")
        default:
            return .init(kind: kind, name: label.isEmpty ? kind.rawValue : label,
                         recordKey: label.isEmpty ? nil : "\(kind.rawValue):\(label)")
        }
    }
}

struct TestLocation: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date
}

struct SpeedSample: Codable, Identifiable, Equatable, Sendable {
    let seconds: Double
    let mbps: Double
    var id: Double { seconds }
}

struct SpeedResult: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var network: NetworkIdentity
    var download: Double
    var upload: Double
    var ping: Double
    var jitter: Double
    var downloadBytes: Int64
    var uploadBytes: Int64
    var duration: Double
    var location: TestLocation?
    var downloadSamples: [SpeedSample]
    var uploadSamples: [SpeedSample]
    var note = ""
    var server = "Cloudflare Edge"
    var mode: String
    var connections: Int
    var recoveryAttempts: Int? = nil
    var favorite: Bool? = nil
    var tags: [String]? = nil
    var placeLabel: String? = nil
    var experimentID: UUID? = nil
    var budgetMB: Int? = nil
    var serverID: String? = nil
    var totalBytes: Int64 { downloadBytes + uploadBytes }
}

enum TestMode: String, Codable, CaseIterable, Identifiable {
    case quick = "Kurz", balanced = "Standard", thorough = "Ausführlich"
    var id: String { rawValue }
    var seconds: Double {
        switch self { case .quick: return 6; case .balanced: return 10; case .thorough: return 15 }
    }
}

enum SpeedUnit: String, Codable, CaseIterable, Identifiable {
    case megabits = "Mbit/s", megabytes = "MB/s"
    var id: String { rawValue }
    func convert(_ mbps: Double) -> Double { self == .megabytes ? mbps / 8 : mbps }
    func format(_ mbps: Double) -> String { SpeedMath.number(convert(mbps)) }
}

enum GaugeScale: Int, Codable, CaseIterable, Identifiable {
    case automatic = 0, hundred = 100, twoFifty = 250, threeHundred = 300
    case fiveHundred = 500, thousand = 1000, twoThousandFiveHundred = 2500
    var id: Int { rawValue }
    var initialMaximum: Double { self == .automatic ? 1000 : Double(rawValue) }
    var label: String { self == .automatic ? "Automatisch (ab 1.000)" : "\(rawValue) Mbit/s" }
}

struct MeasurementServer: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var downloadURL: URL
    var uploadURL: URL
    var pingURL: URL
    var libreSpeed: Bool
    // Share cooldowns across paths belonging to the same server.
    var id: String { downloadURL.host?.lowercased() ?? downloadURL.absoluteString }
    static let cloudflare = MeasurementServer(name: "Cloudflare Edge",
        downloadURL: URL(string: "https://speed.cloudflare.com/__down")!,
        uploadURL: URL(string: "https://speed.cloudflare.com/__up")!,
        pingURL: URL(string: "https://speed.cloudflare.com/__down")!, libreSpeed: false)

    func requestURL(upload: Bool = false, ping: Bool = false, bytes: Int = 0) -> URL {
        var parts = URLComponents(url: ping ? pingURL : upload ? uploadURL : downloadURL, resolvingAgainstBaseURL: false)!
        var query = parts.queryItems ?? []
        query.removeAll { ["r", "bytes", "ckSize"].contains($0.name) }
        query.append(URLQueryItem(name: "r", value: UUID().uuidString))
        if !upload && (!ping || !libreSpeed) {
            query.append(URLQueryItem(name: libreSpeed ? "ckSize" : "bytes",
                                      value: String(libreSpeed ? bytes / 1_048_576 : bytes)))
        }
        parts.queryItems = query
        return parts.url!
    }
}

struct AppSettings: Codable, Equatable {
    var mode: TestMode = .balanced
    var connections = 4
    var budgetMB = 1024
    var unit: SpeedUnit = .megabits
    var appearance = "Dunkel"
    var accent = "Polarlicht"
    var haptics = true
    var animations = true
    var locationEnabled = true
    var confirmCellular = true
    var keepAwake = true
    var gaugeScale: GaugeScale = .automatic
    var liveHaptics = true
    var hapticStrength = 0.7
    var celebrationStyle: CelebrationStyle = .goodTests
    var dashboardScore = true
    var networkNames: [String: String] = [:]
    var measurementServer: MeasurementServer = .cloudflare

    init() {}
    // New preferences must not invalidate settings or history from earlier IPAs.
    private enum CodingKeys: String, CodingKey {
        case mode, connections, budgetMB, unit, appearance, accent, haptics, animations
        case locationEnabled, confirmCellular, keepAwake, gaugeScale, liveHaptics, hapticStrength
        case measurementServer, networkNames, celebrationStyle, dashboardScore
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(TestMode.self, forKey: .mode) ?? .balanced
        connections = try c.decodeIfPresent(Int.self, forKey: .connections) ?? 4
        budgetMB = try c.decodeIfPresent(Int.self, forKey: .budgetMB) ?? 1024
        unit = try c.decodeIfPresent(SpeedUnit.self, forKey: .unit) ?? .megabits
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? "Dunkel"
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? "Polarlicht"
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        animations = try c.decodeIfPresent(Bool.self, forKey: .animations) ?? true
        locationEnabled = try c.decodeIfPresent(Bool.self, forKey: .locationEnabled) ?? true
        confirmCellular = try c.decodeIfPresent(Bool.self, forKey: .confirmCellular) ?? true
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
        gaugeScale = try c.decodeIfPresent(GaugeScale.self, forKey: .gaugeScale) ?? .automatic
        liveHaptics = try c.decodeIfPresent(Bool.self, forKey: .liveHaptics) ?? true
        hapticStrength = min(1, max(0.2, try c.decodeIfPresent(Double.self, forKey: .hapticStrength) ?? 0.7))
        celebrationStyle = try c.decodeIfPresent(CelebrationStyle.self, forKey: .celebrationStyle) ?? .goodTests
        dashboardScore = try c.decodeIfPresent(Bool.self, forKey: .dashboardScore) ?? true
        networkNames = try c.decodeIfPresent([String: String].self, forKey: .networkNames) ?? [:]
        measurementServer = try c.decodeIfPresent(MeasurementServer.self, forKey: .measurementServer) ?? .cloudflare
    }
}

enum SpeedMath {
    static func mbps(bytes: Int64, seconds: Double) -> Double {
        guard seconds > 0, seconds.isFinite, bytes >= 0 else { return 0 }
        return Double(bytes) * 8 / seconds / 1_000_000
    }
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let m = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[m - 1] + sorted[m]) / 2 : sorted[m]
    }
    static func jitter(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        return zip(values.dropFirst(), values).map { abs($0 - $1) }.reduce(0, +) / Double(values.count - 1)
    }
    static func gaugeMaximum(_ value: Double) -> Double {
        guard value.isFinite, value > 1000 else { return 1000 }
        for ceiling in [2500.0, 5000, 10000, 25000, 50000, 100000] where value <= ceiling { return ceiling }
        return ceil(value / 100000) * 100000
    }
    static func number(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "de_DE")).precision(.fractionLength(value < 100 ? 1 : 0)))
    }
    static func csvField(_ value: String) -> String {
        // Prevent formula interpretation when the export is opened in a spreadsheet.
        let dangerous = ["=", "+", "-", "@", "\t", "\r", "\n"]
        let safe = dangerous.contains(where: { value.hasPrefix($0) }) ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

struct NetworkRecord: Identifiable {
    let id: String
    let name: String
    let kind: ConnectionKind
    let download: Double
    let upload: Double
    let count: Int
}

enum RecordBook {
    static func records(_ results: [SpeedResult]) -> [NetworkRecord] {
        let eligible = results.filter { $0.network.recordKey != nil }
        return Dictionary(grouping: eligible, by: { $0.network.recordKey! }).map { key, values in
            NetworkRecord(id: key, name: values[0].network.name, kind: values[0].network.kind,
                          download: values.map(\.download).max() ?? 0,
                          upload: values.map(\.upload).max() ?? 0, count: values.count)
        }.sorted { $0.download > $1.download }
    }
    static func achievements(for result: SpeedResult, previous: [SpeedResult]) -> [String] {
        guard let key = result.network.recordKey else { return [] }
        let matching = previous.filter { $0.network.recordKey == key }
        guard !matching.isEmpty else { return ["Erste Bestmarke für \(result.network.name)"] }
        var awards: [String] = []
        if result.download > (matching.map(\.download).max() ?? 0) { awards.append("Neuer Download-Rekord") }
        if result.upload > (matching.map(\.upload).max() ?? 0) { awards.append("Neuer Upload-Rekord") }
        return awards
    }
}
