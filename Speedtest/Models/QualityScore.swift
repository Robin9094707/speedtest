import Foundation

enum CelebrationStyle: String, Codable, CaseIterable, Identifiable {
    case goodTests = "Gute Tests & Rekorde"
    case records = "Nur Netzrekorde"
    case off = "Aus"
    var id: String { rawValue }
}

enum QualityUseCase: String, CaseIterable, Identifiable {
    case gaming = "Gaming", streaming = "Streaming", calls = "Videoanrufe", download = "Downloads", upload = "Uploads"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .gaming: return "gamecontroller.fill"
        case .streaming: return "play.tv.fill"
        case .calls: return "video.fill"
        case .download: return "arrow.down.circle.fill"
        case .upload: return "arrow.up.circle.fill"
        }
    }
    var weight: Double {
        switch self { case .gaming: return 0.3; case .streaming, .calls: return 0.2; case .download, .upload: return 0.15 }
    }
}

struct QualityRating: Identifiable {
    let category: QualityUseCase
    let value: Double
    let explanation: String
    let formula: String
    var id: QualityUseCase { category }
    var label: String {
        if value >= 9 { return "Ausgezeichnet" }
        if value >= 7.5 { return "Stark" }
        if value >= 5.5 { return "Solide" }
        if value >= 3.5 { return "Ausbaufähig" }
        return "Eingeschränkt"
    }
}

// RJ heuristic v1. These scores are app-defined estimates, never measurements
// of a game server, packet loss, loaded latency or a streaming service.
struct QualityProfile {
    static let method = "RJ-Modell 1"
    let ratings: [QualityRating]
    let available: Bool
    var points: Int { available ? Int((ratings.reduce(0) { $0 + $1.value * $1.category.weight } * 10).rounded()) : 0 }
    var title: String {
        if !available { return "Keine vollständige Messbasis" }
        if points >= 90 { return "Ausgezeichnetes Ergebnis" }
        if points >= 75 { return "Starkes Ergebnis" }
        if points >= 55 { return "Solides Ergebnis" }
        if points >= 35 { return "Da geht noch mehr" }
        return "Verbindung eingeschränkt"
    }
    init(_ result: SpeedResult) {
        available = [result.download, result.upload, result.ping, result.jitter, result.duration].allSatisfy { $0.isFinite && $0 >= 0 }
            && result.downloadBytes > 0 && result.uploadBytes > 0 && result.duration > 0
        guard available else { ratings = []; return }
        let down = result.download, up = result.upload
        let latency = Self.curve(result.ping, [(0, 10), (20, 10), (50, 8), (100, 5), (200, 2), (300, 1)])
        let jitter = Self.curve(result.jitter, [(0, 10), (3, 10), (10, 8), (25, 5), (60, 2), (100, 1)])
        let gameCapacity = 1 + 9 * min(1, min(down / 10, up / 3))
        let callsCapacity = 1 + 9 * min(1, min(down / 10, up / 5))
        let streaming = Self.curve(down, [(0, 1), (2, 2), (5, 4), (10, 6), (25, 8), (50, 10)])
        let download = Self.curve(down, [(0, 1), (5, 2), (10, 3), (25, 5), (50, 6), (100, 7), (250, 9), (500, 10)])
        let upload = Self.curve(up, [(0, 1), (1, 2), (3, 3), (5, 4), (10, 6), (25, 8), (50, 9), (100, 10)])
        ratings = [
            QualityRating(category: .gaming, value: min(gameCapacity, 0.65 * latency + 0.25 * jitter + 0.1 * gameCapacity),
                explanation: "HTTP-Ping und Jitter zählen am stärksten. Mehr Downloadtempo allein macht Gaming nicht besser.",
                formula: "65 % Ping + 25 % Jitter + 10 % Bandbreitenreserve. Reserve = 1 + 9 × min(1, Download/10, Upload/3); sie begrenzt den Gaming-Score. Raten in Mbit/s."),
            QualityRating(category: .streaming, value: min(streaming, 0.9 * streaming + 0.1 * jitter),
                explanation: "Die Downloadrate gibt die Richtung vor. Der Wert ist keine Zusage für eine bestimmte Auflösung oder Anzahl Streams.",
                formula: "90 % Download-Punkte + 10 % Jitter-Punkte, höchstens die Download-Punkte. Download-Kurve: 0/2/5/10/25/50 Mbit/s → 1/2/4/6/8/10."),
            QualityRating(category: .calls, value: min(callsCapacity, 0.6 * callsCapacity + 0.25 * latency + 0.15 * jitter),
                explanation: "Videoanrufe brauchen beide Richtungen. Ein schwacher Upload begrenzt die Einschätzung.",
                formula: "60 % Reserve + 25 % Ping + 15 % Jitter; höchstens die Reserve. Reserve = 1 + 9 × min(1, Download/10, Upload/5), Raten in Mbit/s."),
            QualityRating(category: .download, value: download,
                explanation: "Bewertet die gemessene Downloadrate für große Dateien. Der tatsächliche Downloadserver kann langsamer sein.",
                formula: "Download-Kurve: 0/5/10/25/50/100/250/500 Mbit/s → 1/2/3/5/6/7/9/10 Punkte."),
            QualityRating(category: .upload, value: upload,
                explanation: "Bewertet die Uploadrate für Dateien und Cloud-Backups. Die Gegenstelle kann das Tempo begrenzen.",
                formula: "Upload-Kurve: 0/1/3/5/10/25/50/100 Mbit/s → 1/2/3/4/6/8/9/10 Punkte.")
        ]
    }
    private static func curve(_ value: Double, _ knots: [(Double, Double)]) -> Double {
        for index in 1..<knots.count where value <= knots[index].0 {
            let a = knots[index - 1], b = knots[index]
            let fraction = max(0, min(1, (value - a.0) / (b.0 - a.0)))
            return a.1 + fraction * (b.1 - a.1)
        }
        return knots.last?.1 ?? 1
    }
}
