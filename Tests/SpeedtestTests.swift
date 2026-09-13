import XCTest
@testable import Speedtest

final class SpeedMathTests: XCTestCase {
    func testUnitsAndScaleBeyondGigabit() {
        XCTAssertEqual(SpeedMath.mbps(bytes: 125_000_000, seconds: 1), 1000)
        XCTAssertEqual(SpeedUnit.megabytes.convert(800), 100)
        XCTAssertEqual(SpeedMath.gaugeMaximum(999), 1000)
        XCTAssertEqual(SpeedMath.gaugeMaximum(1001), 2500)
        XCTAssertEqual(SpeedMath.gaugeMaximum(5100), 10000)
        XCTAssertEqual(SpeedMath.mbps(bytes: 10, seconds: 0), 0)
        XCTAssertEqual(SpeedMath.mbps(bytes: 10, seconds: .nan), 0)
    }
    func testMedianAndJitter() {
        XCTAssertEqual(SpeedMath.median([9, 1, 5]), 5)
        XCTAssertEqual(SpeedMath.median([4, 1, 8, 2]), 3)
        XCTAssertEqual(SpeedMath.jitter([10, 20, 15]), 7.5)
        XCTAssertEqual(SpeedMath.jitter([]), 0)
    }
    func testWiFiIdentityDoesNotMixUnknownNetworks() {
        XCTAssertNil(NetworkIdentity.make(kind: .wifi, ssid: nil, alias: "  ").recordKey)
        let a = NetworkIdentity.make(kind: .wifi, ssid: "Zuhause", alias: "falsch")
        let b = NetworkIdentity.make(kind: .wifi, ssid: "Arbeit", alias: "Zuhause")
        XCTAssertNotEqual(a.recordKey, b.recordKey)
        XCTAssertEqual(a.name, "Zuhause")
        XCTAssertNotEqual(a.recordKey, NetworkIdentity.make(kind: .wifi, ssid: nil, alias: "Zuhause").recordKey)
        XCTAssertNotEqual(NetworkIdentity.make(kind: .cellular, ssid: nil, alias: "o2").recordKey,
                          NetworkIdentity.make(kind: .cellular, ssid: nil, alias: "Telekom").recordKey)
    }
    func testCSVDoesNotExecuteNotesAsFormulas() {
        XCTAssertEqual(SpeedMath.csvField("=1+1"), "\"'=1+1\"")
        XCTAssertEqual(SpeedMath.csvField("a\"b;c"), "\"a\"\"b;c\"")
        XCTAssertEqual(SpeedMath.csvField("zwei\nZeilen"), "\"zwei\nZeilen\"")
    }
}

@MainActor
final class PersistenceTests: XCTestCase {
    private func fixture(_ download: Double, _ upload: Double, alias: String = "Zuhause") -> SpeedResult {
        SpeedResult(network: .make(kind: .wifi, ssid: alias, alias: ""), download: download, upload: upload,
                    ping: 12, jitter: 2, downloadBytes: 1_000_000, uploadBytes: 500_000, duration: 12,
                    location: TestLocation(latitude: 51.43, longitude: 6.76, accuracy: 10, timestamp: Date()),
                    downloadSamples: [], uploadSamples: [], mode: "Kurz", connections: 4)
    }
    func testHistorySurvivesReloadNoteEditsAndDeletion() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(directory: folder)
        let result = fixture(700, 90)
        store.add(result)
        store.updateNote(result.id, note: "Am Fenster")
        store.settings.unit = .megabytes
        let reloaded = AppStore(directory: folder)
        XCTAssertNil(reloaded.storageError)
        XCTAssertEqual(reloaded.results.count, 1)
        XCTAssertEqual(reloaded.results[0].note, "Am Fenster")
        XCTAssertEqual(reloaded.results[0].location?.latitude, 51.43)
        XCTAssertEqual(reloaded.settings.unit, .megabytes)
        reloaded.remove(result.id)
        XCTAssertTrue(AppStore(directory: folder).results.isEmpty)
    }
    func testRecordsRecomputeAfterDeletingBestTest() {
        let first = fixture(700, 90)
        let fast = fixture(900, 80)
        let other = fixture(1000, 100, alias: "Arbeit")
        XCTAssertEqual(RecordBook.achievements(for: fast, previous: [first]), ["Neuer Download-Rekord"])
        XCTAssertEqual(RecordBook.records([first, fast, other]).count, 2)
        XCTAssertEqual(RecordBook.records([first]).first?.download, 700)
        XCTAssertEqual(RecordBook.records([first, fast]).first?.upload, 90)
    }
    func testExportIncludesLocationAndEscapesNotes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(directory: folder)
        var r = fixture(100, 30); r.note = "=HYPERLINK(\"https://example.com\")"
        store.add(r)
        let csv = try String(contentsOf: store.export(json: false), encoding: .utf8)
        XCTAssertTrue(csv.contains("51.43"))
        XCTAssertTrue(csv.contains("'=HYPERLINK"))
        let json = try Data(contentsOf: store.export(json: true))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual((object["results"] as? [[String: Any]])?.count, 1)
    }
}

final class ServerErrorProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("unavailable".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class TransferTests: XCTestCase {
    func testHTTPFailureNeverBecomesSpeedResult() async {
        let meter = TransferMeter(upload: false, seconds: 1, streams: 2, budget: 10000,
                                  cellularAllowed: false, sessionProtocols: [ServerErrorProtocol.self]) { _ in }
        do { _ = try await meter.run(); XCTFail("HTTP 503 must fail") }
        catch MeasurementError.server(let status) { XCTAssertEqual(status, 503) }
        catch { XCTFail("Unexpected error: \(error)") }
    }
    func testCancellationBeforeStartFinishesExactlyOnce() async {
        let task = Task {
            try Task.checkCancellation()
            return try await TransferMeter(upload: false, seconds: 10, streams: 4, budget: 10000,
                                           cellularAllowed: false, sessionProtocols: [ServerErrorProtocol.self]) { _ in }.run()
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled task returned a result") }
        catch is CancellationError {}
        catch { /* A server failure can win the cancellation race, but never a result. */ }
    }
}
