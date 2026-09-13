import Foundation
import Combine
import UIKit

enum TestPhase: String {
    case idle = "Bereit", latency = "Latenz messen", download = "Download", upload = "Upload", complete = "Abgeschlossen", cancelled = "Abgebrochen", failed = "Test fehlgeschlagen"
    var running: Bool { self == .latency || self == .download || self == .upload }
}

enum MeasurementError: LocalizedError {
    case server(Int), noData, networkChanged, background
    var errorDescription: String? {
        switch self {
        case .server(let status): return "Der Messserver antwortet mit HTTP \(status). Bitte später erneut versuchen."
        case .noData: return "Zu wenige bestätigte Daten für eine zuverlässige Messung. Versuche einen längeren Test."
        case .networkChanged: return "Die Netzwerkverbindung hat sich geändert. Starte im gewünschten Netz erneut."
        case .background: return "Der Test wurde beim Verlassen der App beendet. Bitte halte die App für die Messung geöffnet."
        }
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
}

// All mutable transport state is confined to queue, including delegate callbacks,
// cancellation, the deadline timer and continuation completion.
final class TransferMeter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "de.robinjuhas.speedtest.transfer", qos: .userInitiated)
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
    private var payload = Data()

    init(upload: Bool, seconds: Double, streams: Int, budget: Int64, cellularAllowed: Bool, sessionProtocols: [AnyClass]? = nil,
         progress: @escaping @Sendable (TransferProgress) -> Void) {
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
        let count = Int(min(Int64(upload ? nextUploadSize : 25_000_000), budget - reserved))
        guard count > 0 else { return }
        reserved += Int64(count)
        var components = URLComponents(string: "https://speed.cloudflare.com/\(upload ? "__up" : "__down")")!
        components.queryItems = [URLQueryItem(name: "r", value: UUID().uuidString)]
        if !upload { components.queryItems?.append(URLQueryItem(name: "bytes", value: String(count))) }
        var request = URLRequest(url: components.url!)
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
            completionHandler(.cancel); finish(error: MeasurementError.server(status)); return
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
        guard (200..<300).contains(status) else { finish(error: MeasurementError.server(status)); return }
        completedRequests += 1
        if upload {
            // Final upload bandwidth counts only payload acknowledged by a successful HTTP response.
            bytes += Int64(info.size)
            let elapsed = max(0.05, ProcessInfo.processInfo.systemUptime - info.start)
            nextUploadSize = min(4 * 1024 * 1024, max(64 * 1024, Int(Double(info.size) / elapsed * 0.6)))
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
    private var task: Task<Void, Never>?
    private var runID = UUID()
    // Display-only smoothing: recorded samples and final results stay untouched.
    private var displayWindow: [(end: Double, duration: Double, speed: Double)] = []
    private var lastDisplayTime = 0.0
    var isRunning: Bool { phase.running }

    func start(store: AppStore, network: NetworkIdentity, location: LocationService) {
        guard !isRunning else { return }
        let config = store.settings
        resetDisplay()
        phase = .latency; liveSpeed = 0; progress = 0; download = nil; upload = nil
        ping = nil; jitter = nil; transferred = 0; samples = []; result = nil; awards = []; errorMessage = nil
        let id = UUID(); runID = id
        UIApplication.shared.isIdleTimerDisabled = config.keepAwake
        location.refresh()
        task = Task {
            let started = Date()
            do {
                let latencies = try await measureLatency(cellularAllowed: network.kind == .cellular)
                try Task.checkCancellation()
                ping = SpeedMath.median(latencies); jitter = SpeedMath.jitter(latencies)
                let position = config.locationEnabled ? location.snapshot() : nil
                let budget = Int64(config.budgetMB) * 1_000_000 / 2
                phase = .download
                let down = try await TransferMeter(upload: false, seconds: config.mode.seconds,
                    streams: config.connections, budget: budget, cellularAllowed: network.kind == .cellular) { [weak self] update in
                    Task { @MainActor in self?.receive(update, id: id, phase: .download, duration: config.mode.seconds, priorBytes: 0) }
                }.run()
                try Task.checkCancellation()
                download = down.mbps; phase = .upload; samples = []; liveSpeed = 0
                resetDisplay()
                let up = try await TransferMeter(upload: true, seconds: config.mode.seconds,
                    streams: config.connections, budget: budget, cellularAllowed: network.kind == .cellular) { [weak self] update in
                    Task { @MainActor in self?.receive(update, id: id, phase: .upload, duration: config.mode.seconds, priorBytes: down.bytes) }
                }.run()
                try Task.checkCancellation()
                upload = up.mbps
                let completed = SpeedResult(date: started, network: network, download: down.mbps, upload: up.mbps,
                    ping: ping ?? 0, jitter: jitter ?? 0, downloadBytes: down.bytes, uploadBytes: up.bytes,
                    duration: Date().timeIntervalSince(started), location: position,
                    downloadSamples: down.samples, uploadSamples: up.samples,
                    mode: config.mode.rawValue, connections: config.connections)
                awards = RecordBook.achievements(for: completed, previous: store.results)
                store.add(completed)
                result = completed; phase = .complete; liveSpeed = down.mbps; progress = 1
                transferred = completed.totalBytes
                if config.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            } catch {
                guard runID == id else { return }
                if Task.isCancelled || error is CancellationError { phase = .cancelled }
                else { phase = .failed; errorMessage = error.localizedDescription }
                liveSpeed = 0
            }
            if runID == id { UIApplication.shared.isIdleTimerDisabled = false; task = nil }
        }
    }

    func cancel(reason: String? = nil) {
        guard isRunning else { return }
        // Invalidate progress callbacks before another run can begin.
        runID = UUID(); task?.cancel(); task = nil; phase = .cancelled; liveSpeed = 0
        errorMessage = reason
        UIApplication.shared.isIdleTimerDisabled = false
    }
    private func receive(_ update: TransferProgress, id: UUID, phase expected: TestPhase, duration: Double, priorBytes: Int64) {
        guard id == runID, phase == expected else { return }
        smoothDisplay(update)
        transferred = priorBytes + update.bytes
        samples.append(SpeedSample(seconds: update.elapsed, mbps: update.mbps))
        progress = expected == .download ? 0.1 + 0.45 * min(1, update.elapsed / duration) : 0.55 + 0.45 * min(1, update.elapsed / duration)
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
            let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0&r=\(UUID().uuidString)")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            let started = ProcessInfo.processInfo.systemUptime
            let (_, response) = try await session.data(for: request)
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status), response.url?.host == "speed.cloudflare.com" else { throw MeasurementError.server(status) }
            if index > 0 { values.append(elapsed) }
            progress = Double(index + 1) / 7 * 0.1
        }
        return values
    }
}
