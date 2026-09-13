import Foundation
import Combine
import UIKit

@MainActor
final class ServerDirectory: ObservableObject {
    @Published private(set) var servers: [MeasurementServer] = {
        guard let data = UserDefaults.standard.data(forKey: "libreSpeedDirectory"),
              let values = try? JSONDecoder().decode([MeasurementServer].self, from: data) else { return [] }
        return values
    }()
    @Published private(set) var loading = false
    @Published private(set) var message: String?
    private struct Entry: Decodable {
        let name: String
        let server: String
        let dlURL: String
        let ulURL: String
        let pingURL: String
        var measurementServer: MeasurementServer? {
            guard var base = URLComponents(string: server.hasPrefix("//") ? "https:" + server : server),
                  ["http", "https"].contains(base.scheme?.lowercased() ?? ""),
                  base.host != nil, base.user == nil, base.password == nil else { return nil }
            base.scheme = "https"
            if !base.path.hasSuffix("/") { base.path += "/" }
            guard let url = base.url else { return nil }
            func endpoint(_ path: String) -> URL? {
                guard let value = URL(string: path, relativeTo: url)?.absoluteURL,
                      value.scheme == "https", value.host == url.host, value.port == url.port,
                      value.user == nil, value.password == nil else { return nil }
                return value
            }
            guard let down = endpoint(dlURL), let up = endpoint(ulURL), let ping = endpoint(pingURL) else { return nil }
            return MeasurementServer(name: name, downloadURL: down, uploadURL: up, pingURL: ping, libreSpeed: true)
        }
    }
    func refresh() async {
        guard !loading else { return }
        loading = true; message = nil
        defer { loading = false }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        do {
            let url = URL(string: "https://librespeed.org/backend-servers/servers.php")!
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw MeasurementError.responseError(response as? HTTPURLResponse)
            }
            let entries = try JSONDecoder().decode([Entry].self, from: data)
            var seen = Set<String>()
            let values = entries.compactMap(\.measurementServer).filter { seen.insert($0.id).inserted }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            guard !values.isEmpty else { throw MeasurementError.noData }
            try Task.checkCancellation()
            servers = values
            UserDefaults.standard.set(try JSONEncoder().encode(values), forKey: "libreSpeedDirectory")
        } catch {
            if !Task.isCancelled { message = "Serverliste konnte nicht geladen werden: \(error.localizedDescription) Gespeicherte Server bleiben auswählbar." }
        }
    }
}

enum TestPhase: String {
    case idle = "Bereit", latency = "Latenz messen", download = "Download", upload = "Upload", complete = "Abgeschlossen", cancelled = "Abgebrochen", failed = "Test fehlgeschlagen"
    var running: Bool { self == .latency || self == .download || self == .upload }
}

enum MeasurementError: LocalizedError {
    case server(Int), noData, networkChanged, background
    case retryLater(Int, Double), unexpectedResponse, retryBudget
    var errorDescription: String? {
        switch self {
        case .server(403): return "Dieser Messserver lehnt den Zugriff ab (HTTP 403). Wähle unter „Messserver wechseln“ einen anderen Anbieter. Die genaue Ursache teilt der Server nicht mit."
        case .server(let status): return "Der Messserver antwortet mit HTTP \(status). Du kannst einen anderen Messserver wählen oder es später erneut versuchen."
        case .retryLater(let status, let delay): return "Der Messserver meldet HTTP \(status). Frühestens in \(ceil(delay).formatted(.number.precision(.fractionLength(0)))) Sekunden erneut versuchen."
        case .unexpectedResponse: return "Die Antwort enthält keine gültigen Testdaten. Prüfe eine mögliche WLAN-Anmeldeseite, einen VPN oder Netzwerkfilter."
        case .retryBudget: return "Für einen neuen Messversuch reicht das verbleibende Datenlimit nicht. Wähle ein höheres Limit oder starte später erneut."
        case .noData: return "Zu wenige bestätigte Daten für eine zuverlässige Messung. Versuche einen längeren Test."
        case .networkChanged: return "Die Netzwerkverbindung hat sich geändert. Starte im gewünschten Netz erneut."
        case .background: return "Der Test wurde beim Verlassen der App beendet. Bitte halte die App für die Messung geöffnet."
        }
    }
    static func responseError(_ response: HTTPURLResponse?) -> MeasurementError {
        let status = response?.statusCode ?? 0
        if let header = response?.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = Double(header), seconds.isFinite {
                return .retryLater(status, max(0, seconds))
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            if let date = formatter.date(from: header) {
                return .retryLater(status, max(0, date.timeIntervalSinceNow))
            }
        }
        return .server(status)
    }
}

struct TransferProgress: Sendable {
    let elapsed: Double
    let mbps: Double
    let bytes: Int64
}

struct TransferResult: Sendable {
    let mbps: Double
    let bytes: Int64
    let samples: [SpeedSample]
    var retries = 0
}

// All mutable transport state is confined to queue, including delegate callbacks,
// cancellation, the deadline timer and continuation completion.
final class TransferMeter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "de.robinjuhas.speedtest.transfer", qos: .userInitiated)
    private let server: MeasurementServer
    private let upload: Bool
    private let seconds: Double
    private let streams: Int
    private let budget: Int64
    private let cellularAllowed: Bool
    private let sessionProtocols: [AnyClass]?
    private let progress: @Sendable (TransferProgress) -> Void
    private var session: URLSession?
    private var timer: DispatchSourceTimer?
    private var continuation: CheckedContinuation<TransferResult, Error>?
    private var cancelled = false
    private var finished = false
    private var start = 0.0
    private var lastTime = 0.0
    private var baselineTime = 0.0
    private var baselineBytes: Int64 = 0
    private var lastBytes: Int64 = 0
    private var bytes: Int64 = 0
    private var wireBytes: Int64 = 0
    private var reserved: Int64 = 0
    private var completedRequests = 0
    private var samples: [SpeedSample] = []
    private var tasks: [Int: (size: Int, start: Double)] = [:]
    private var nextUploadSize = 128 * 1024
    private var nextDownloadSize = 25_000_000
    private var payload = Data()

    init(upload: Bool, seconds: Double, streams: Int, budget: Int64, cellularAllowed: Bool, sessionProtocols: [AnyClass]? = nil, server: MeasurementServer = .cloudflare,
         progress: @escaping @Sendable (TransferProgress) -> Void) {
        self.server = server
        self.upload = upload; self.seconds = seconds; self.streams = streams
        self.budget = budget; self.cellularAllowed = cellularAllowed; self.progress = progress
        self.sessionProtocols = sessionProtocols
    }

    func run() async throws -> TransferResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.continuation = continuation
                    if self.cancelled { self.finish(error: CancellationError()); return }
                    self.begin()
                }
            }
        } onCancel: {
            self.queue.async {
                self.cancelled = true
                if self.continuation != nil { self.finish(error: CancellationError()) }
            }
        }
    }

    func consumption() async -> (bytes: Int64, reserved: Int64) {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: (self.wireBytes, self.reserved)) }
        }
    }

    private func begin() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpMaximumConnectionsPerHost = streams
        config.timeoutIntervalForRequest = seconds + 4
        config.timeoutIntervalForResource = seconds + 5
        config.waitsForConnectivity = false
        config.allowsCellularAccess = cellularAllowed
        if let sessionProtocols { config.protocolClasses = sessionProtocols }
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.underlyingQueue = queue
        session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        if upload {
            // Random, non-personal payload; no local user data is uploaded.
            var generator = SystemRandomNumberGenerator()
            let words = (0..<(4 * 1024 * 1024 / 8)).map { _ in UInt64.random(in: .min ... .max, using: &generator) }
            payload = words.withUnsafeBytes { Data($0) }
        }
        start = ProcessInfo.processInfo.systemUptime
        lastTime = start
        for _ in 0..<streams { spawn() }
        let ticker = DispatchSource.makeTimerSource(queue: queue)
        ticker.schedule(deadline: .now() + 0.2, repeating: 0.2)
        ticker.setEventHandler { [weak self] in self?.tick() }
        timer = ticker
        ticker.resume()
    }

    private func spawn() {
        guard !finished, ProcessInfo.processInfo.systemUptime - start < seconds,
              reserved < budget, let session else { return }
        var count = Int(min(Int64(upload ? nextUploadSize : nextDownloadSize), budget - reserved))
        if !upload && server.libreSpeed { count = (count / 1_048_576) * 1_048_576 }
        guard count > 0 else { return }
        reserved += Int64(count)
        var request = URLRequest(url: server.requestURL(upload: upload, bytes: count))
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let task: URLSessionTask
        if upload {
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            task = session.uploadTask(with: request, from: Data(payload.prefix(count)))
        } else { task = session.dataTask(with: request) }
        tasks[task.taskIdentifier] = (count, ProcessInfo.processInfo.systemUptime)
        task.resume()
    }

    private func tick() {
        guard !finished else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - start
        let speed = SpeedMath.mbps(bytes: bytes - lastBytes, seconds: now - lastTime)
        samples.append(SpeedSample(seconds: elapsed, mbps: speed))
        progress(TransferProgress(elapsed: elapsed, mbps: speed, bytes: wireBytes))
        lastTime = now; lastBytes = bytes
        if baselineTime == 0 && elapsed >= 0.8 && bytes > 0 {
            baselineTime = now; baselineBytes = bytes
        }
        if elapsed >= seconds { finish() }
    }

    private func finish(error: Error? = nil) {
        guard !finished, let continuation else { return }
        finished = true
        self.continuation = nil
        timer?.cancel(); timer = nil
        session?.invalidateAndCancel(); session = nil
        let end = ProcessInfo.processInfo.systemUptime
        if let error { continuation.resume(throwing: error); return }
        guard bytes > 0, !upload || completedRequests > 0 else {
            continuation.resume(throwing: MeasurementError.noData); return
        }
        let useWarmup = baselineTime > 0 && end - baselineTime > 0.5 && bytes > baselineBytes
        let measured = useWarmup ? bytes - baselineBytes : bytes
        let duration = useWarmup ? end - baselineTime : end - start
        let final = SpeedMath.mbps(bytes: measured, seconds: duration)
        if samples.isEmpty { samples = [SpeedSample(seconds: end - start, mbps: final)] }
        continuation.resume(returning: TransferResult(mbps: final, bytes: wireBytes, samples: samples))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard !finished else { completionHandler(.cancel); return }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            completionHandler(.cancel)
            finish(error: MeasurementError.responseError(response as? HTTPURLResponse)); return
        }
        if !upload && response.mimeType?.lowercased() == "text/html" {
            completionHandler(.cancel); finish(error: MeasurementError.unexpectedResponse); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished, !upload else { return }
        bytes += Int64(data.count)
        wireBytes += Int64(data.count)
        // Intentionally discard chunks instead of retaining large downloads.
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard !finished, upload else { return }
        wireBytes += bytesSent
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished, let info = tasks.removeValue(forKey: task.taskIdentifier) else { return }
        if let error { finish(error: error); return }
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { finish(error: MeasurementError.responseError(task.response as? HTTPURLResponse)); return }
        completedRequests += 1
        if upload {
            // Final upload bandwidth counts only payload acknowledged by a successful HTTP response.
            bytes += Int64(info.size)
            let elapsed = max(0.05, ProcessInfo.processInfo.systemUptime - info.start)
            nextUploadSize = min(4 * 1024 * 1024, max(64 * 1024, Int(Double(info.size) / elapsed * 0.6)))
        } else {
            // Fast lines use larger chunks, reducing HTTP request pressure.
            let elapsed = max(0.05, ProcessInfo.processInfo.systemUptime - info.start)
            nextDownloadSize = min(100_000_000, max(5_000_000, Int(Double(info.size) / elapsed * 0.8)))
        }
        spawn()
        if tasks.isEmpty { finish() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Captive portals and redirects must not become plausible speed results.
        completionHandler(nil)
        finish(error: MeasurementError.server(response.statusCode))
    }
}

@MainActor
final class SpeedtestEngine: ObservableObject {
    @Published private(set) var phase: TestPhase = .idle
    @Published private(set) var liveSpeed = 0.0
    @Published private(set) var progress = 0.0
    @Published private(set) var download: Double?
    @Published private(set) var upload: Double?
    @Published private(set) var ping: Double?
    @Published private(set) var jitter: Double?
    @Published private(set) var transferred: Int64 = 0
    @Published private(set) var samples: [SpeedSample] = []
    @Published private(set) var result: SpeedResult?
    @Published private(set) var awards: [String] = []
    @Published var errorMessage: String?
    @Published private(set) var recoveryMessage: String?
    @Published private(set) var gaugeMaximum = 1000.0
    @Published private(set) var serverCooldowns: [String: Date] = {
        var values = UserDefaults.standard.dictionary(forKey: "measurementServerCooldowns") as? [String: Date] ?? [:]
        if let legacy = UserDefaults.standard.object(forKey: "serverRetryAfter") as? Date {
            let key = MeasurementServer.cloudflare.id
            values[key] = max(values[key] ?? .distantPast, legacy)
        }
        return values
    }()
    private var activeServer: MeasurementServer = .cloudflare
    func cooldown(for server: MeasurementServer) -> Date? { serverCooldowns[server.id] }
    private var task: Task<Void, Never>?
    private var hapticTask: Task<Void, Never>?
    private var activeAttempt: UUID?
    private var selectedScale: GaugeScale = .automatic
    private var runID = UUID()
    // Display-only smoothing: recorded samples and final results stay untouched.
    private var displayWindow: [(end: Double, duration: Double, speed: Double)] = []
    private var lastDisplayTime = 0.0
    var isRunning: Bool { phase.running }

    func start(store: AppStore, network: NetworkIdentity, location: LocationService, placeLabel: String? = nil, experimentID: UUID? = nil) {
        guard !isRunning else { return }
        if let until = cooldown(for: store.settings.measurementServer), until > Date() {
            errorMessage = "Dieser Messserver braucht eine Pause. Du kannst einen anderen Messserver wählen oder den Countdown abwarten."
            return
        }
        let config = store.settings
        activeServer = config.measurementServer
        selectedScale = config.gaugeScale
        gaugeMaximum = selectedScale.initialMaximum
        recoveryMessage = nil
        resetDisplay()
        phase = .latency; liveSpeed = 0; progress = 0; download = nil; upload = nil
        ping = nil; jitter = nil; transferred = 0; samples = []; result = nil; awards = []; errorMessage = nil
        let id = UUID(); runID = id
        UIApplication.shared.isIdleTimerDisabled = config.keepAwake
        location.refresh()
        startLiveHaptics(store: store)
        task = Task {
            let started = Date()
            do {
                let latencies = try await latencyWithRecovery(cellularAllowed: network.kind == .cellular)
                try Task.checkCancellation()
                ping = SpeedMath.median(latencies); jitter = SpeedMath.jitter(latencies)
                let position = config.locationEnabled ? location.snapshot() : nil
                let budget = Int64(config.budgetMB) * 1_000_000 / 2
                phase = .download
                let down = try await measureDirection(uploading: false, config: config, budget: budget,
                    cellularAllowed: network.kind == .cellular, id: id, priorBytes: 0)
                try Task.checkCancellation()
                download = down.mbps; phase = .upload; samples = []; liveSpeed = 0
                resetDisplay()
                let up = try await measureDirection(uploading: true, config: config, budget: budget,
                    cellularAllowed: network.kind == .cellular, id: id, priorBytes: down.bytes)
                try Task.checkCancellation()
                upload = up.mbps
                let completed = SpeedResult(date: started, network: network, download: down.mbps, upload: up.mbps,
                    ping: ping ?? 0, jitter: jitter ?? 0, downloadBytes: down.bytes, uploadBytes: up.bytes,
                    duration: Date().timeIntervalSince(started), location: position,
                    downloadSamples: down.samples, uploadSamples: up.samples,
                    server: config.measurementServer.name, mode: config.mode.rawValue, connections: config.connections, recoveryAttempts: down.retries + up.retries, placeLabel: placeLabel, experimentID: experimentID, budgetMB: config.budgetMB, serverID: config.measurementServer.id)
                awards = RecordBook.achievements(for: completed, previous: store.results)
                store.add(completed)
                result = completed; phase = .complete; liveSpeed = down.mbps; progress = 1
                if selectedScale == .automatic { gaugeMaximum = max(gaugeMaximum, SpeedMath.gaugeMaximum(down.mbps)) }
                transferred = completed.totalBytes
                hapticTask?.cancel(); hapticTask = nil
                if store.settings.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            } catch {
                guard runID == id else { return }
                if Task.isCancelled || error is CancellationError { phase = .cancelled }
                else { phase = .failed; errorMessage = error.localizedDescription }
                liveSpeed = 0
                if store.settings.haptics && !Task.isCancelled { UINotificationFeedbackGenerator().notificationOccurred(.error) }
            }
            if runID == id {
                UIApplication.shared.isIdleTimerDisabled = false; task = nil
                recoveryMessage = nil; hapticTask?.cancel(); hapticTask = nil
            }
        }
    }

    func cancel(reason: String? = nil) {
        guard isRunning else { return }
        // Invalidate progress callbacks before another run can begin.
        runID = UUID(); task?.cancel(); task = nil; phase = .cancelled; liveSpeed = 0
        activeAttempt = nil; recoveryMessage = nil; hapticTask?.cancel(); hapticTask = nil
        errorMessage = reason
        UIApplication.shared.isIdleTimerDisabled = false
    }
    private func receive(_ update: TransferProgress, id: UUID, phase expected: TestPhase, duration: Double, priorBytes: Int64) {
        guard id == runID, phase == expected else { return }
        smoothDisplay(update)
        if selectedScale == .automatic { gaugeMaximum = max(gaugeMaximum, SpeedMath.gaugeMaximum(liveSpeed)) }
        transferred = priorBytes + update.bytes
        samples.append(SpeedSample(seconds: update.elapsed, mbps: update.mbps))
        progress = expected == .download ? 0.1 + 0.45 * min(1, update.elapsed / duration) : 0.55 + 0.45 * min(1, update.elapsed / duration)
    }
    private func startLiveHaptics(store: AppStore) {
        hapticTask?.cancel()
        hapticTask = Task { @MainActor [weak self, weak store] in
            let impact = UIImpactFeedbackGenerator(style: .rigid)
            let transition = UIImpactFeedbackGenerator(style: .soft)
            var previousPhase: TestPhase = .idle
            impact.prepare()
            while !Task.isCancelled {
                guard let self, let store, self.isRunning else { return }
                let measuring = self.phase == .download || self.phase == .upload
                let active = measuring && self.recoveryMessage == nil && store.settings.haptics && store.settings.liveHaptics
                let fraction = min(1, max(0, self.liveSpeed / self.gaugeMaximum))
                if active {
                    if previousPhase != self.phase { transition.impactOccurred(intensity: 0.65) }
                    else if self.liveSpeed > 0.1 {
                        impact.impactOccurred(intensity: CGFloat((0.15 + 0.85 * sqrt(fraction)) * store.settings.hapticStrength))
                        impact.prepare()
                    }
                }
                previousPhase = self.phase
                let interval = active ? 0.45 - 0.30 * fraction : 0.2
                do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) }
                catch { return }
            }
        }
    }

    private func recoveryPolicy(_ error: Error, attempt: Int) -> (delay: Double, retry: Bool)? {
        let retryCodes = [408, 409, 429, 500, 502, 503, 504]
        if let error = error as? MeasurementError {
            switch error {
            case .retryLater(let status, let delay): return (max(1, delay), retryCodes.contains(status))
            case .server(let status) where retryCodes.contains(status):
                return (status == 429 ? 30 : pow(2, Double(attempt + 1)), true)
            default: return nil
            }
        }
        if let error = error as? URLError,
           [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
            return (pow(2, Double(attempt)), true)
        }
        return nil
    }
    private func waitBeforeRetry(_ error: Error, attempt: Int) async throws {
        try Task.checkCancellation()
        guard let policy = recoveryPolicy(error, attempt: attempt) else { throw error }
        if error is MeasurementError {
            let until = Date().addingTimeInterval(policy.delay)
            serverCooldowns[activeServer.id] = max(serverCooldowns[activeServer.id] ?? .distantPast, until)
            UserDefaults.standard.set(serverCooldowns, forKey: "measurementServerCooldowns")
        }
        guard attempt < 2, policy.retry, policy.delay <= 12 else { throw error }
        recoveryMessage = "Kurze Unterbrechung · neuer Versuch in \(Int(ceil(policy.delay))) s"
        liveSpeed = 0
        try await Task.sleep(nanoseconds: UInt64(policy.delay * 1_000_000_000))
        try Task.checkCancellation()
        recoveryMessage = nil
    }
    private func latencyWithRecovery(cellularAllowed: Bool) async throws -> [Double] {
        for attempt in 0...2 {
            do { return try await measureLatency(cellularAllowed: cellularAllowed) }
            catch {
                try Task.checkCancellation()
                try await waitBeforeRetry(error, attempt: attempt)
            }
        }
        throw MeasurementError.noData
    }
    private func measureDirection(uploading: Bool, config: AppSettings, budget: Int64,
                                  cellularAllowed: Bool, id: UUID, priorBytes: Int64) async throws -> TransferResult {
        var usedQuota: Int64 = 0
        var failedBytes: Int64 = 0
        for attempt in 0...2 {
            try Task.checkCancellation()
            let remaining = budget - usedQuota
            guard remaining >= 65_536 else { throw MeasurementError.retryBudget }
            let attemptID = UUID()
            activeAttempt = attemptID
            resetDisplay(); samples = []
            let offset = priorBytes + failedBytes
            let direction: TestPhase = uploading ? .upload : .download
            let meter = TransferMeter(upload: uploading, seconds: config.mode.seconds,
                streams: max(1, config.connections / (1 << attempt)), budget: remaining, cellularAllowed: cellularAllowed, server: config.measurementServer) { [weak self] update in
                    Task { @MainActor in
                        guard let self, self.activeAttempt == attemptID else { return }
                        self.receive(update, id: id, phase: direction, duration: config.mode.seconds, priorBytes: offset)
                    }
                }
            do {
                let result = try await meter.run()
                if activeAttempt == attemptID { activeAttempt = nil }
                try Task.checkCancellation()
                return TransferResult(mbps: result.mbps, bytes: failedBytes + result.bytes,
                                      samples: result.samples, retries: attempt)
            } catch {
                if activeAttempt == attemptID { activeAttempt = nil }
                try Task.checkCancellation()
                let usage = await meter.consumption()
                try Task.checkCancellation()
                failedBytes += usage.bytes
                // Retain the reservation for cancelled in-flight data as well:
                // retries never open a fresh full data budget.
                usedQuota += max(usage.bytes, usage.reserved)
                transferred = priorBytes + failedBytes
                try await waitBeforeRetry(error, attempt: attempt)
            }
        }
        throw MeasurementError.noData
    }
    private func resetDisplay() {
        displayWindow.removeAll(keepingCapacity: true)
        lastDisplayTime = 0
    }
    private func smoothDisplay(_ update: TransferProgress) {
        let interval = update.elapsed - lastDisplayTime
        guard interval > 0, update.mbps.isFinite else { return }
        lastDisplayTime = update.elapsed
        displayWindow.append((end: update.elapsed, duration: interval, speed: max(0, update.mbps)))
        let windowStart = max(0, update.elapsed - 1.4)
        displayWindow.removeAll { $0.end <= windowStart }
        var weightedSpeed = 0.0
        var weight = 0.0
        for sample in displayWindow {
            let overlap = sample.end - max(windowStart, sample.end - sample.duration)
            weightedSpeed += sample.speed * overlap
            weight += overlap
        }
        guard weight > 0 else { return }
        // The rolling window absorbs bursty upload acknowledgments; this second
        // stage gently follows sustained changes without spring overshoot.
        let target = weightedSpeed / weight
        let response = 1 - exp(-interval / 0.55)
        liveSpeed += (target - liveSpeed) * response
    }
    private func measureLatency(cellularAllowed: Bool) async throws -> [Double] {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 6
        config.allowsCellularAccess = cellularAllowed
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var values: [Double] = []
        for index in 0..<7 {
            try Task.checkCancellation()
            let url = activeServer.requestURL(ping: true)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            let started = ProcessInfo.processInfo.systemUptime
            let (body, response) = try await session.data(for: request)
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw MeasurementError.responseError(response as? HTTPURLResponse) }
            guard response.url?.host == url.host, response.url?.path == url.path,
                  body.isEmpty || response.mimeType?.lowercased() != "text/html" else { throw MeasurementError.unexpectedResponse }
            if index > 0 { values.append(elapsed) }
            progress = Double(index + 1) / 7 * 0.1
        }
        return values
    }
}
