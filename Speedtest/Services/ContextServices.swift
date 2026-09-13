import Foundation
import Combine
import CoreLocation
import Network
import NetworkExtension

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var latest: TestLocation?
    @Published private(set) var message = "Standort noch nicht verfügbar"
    private let manager = CLLocationManager()
    private var enabled = true

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorization = manager.authorizationStatus
    }
    func activate(enabled: Bool) {
        self.enabled = enabled
        guard enabled else { manager.stopUpdatingLocation(); latest = nil; message = "Standort ausgeschaltet"; return }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { refresh() }
    }
    func refresh() {
        guard enabled else { return }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if manager.authorizationStatus != .notDetermined {
            latest = nil
            message = "Ohne Standort · Zugriff in iOS-Einstellungen erlauben"
        }
    }
    func snapshot() -> TestLocation? {
        guard enabled, let latest, abs(latest.timestamp.timeIntervalSinceNow) < 120, latest.accuracy >= 0, latest.accuracy <= 1000 else { return nil }
        return latest
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorization = self.manager.authorizationStatus
            self.refresh()
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        let snapshot = TestLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                    accuracy: location.horizontalAccuracy, timestamp: location.timestamp)
        Task { @MainActor [weak self] in
            guard let self, self.enabled else { return }
            self.latest = snapshot
            self.message = "Standort bereit · ±\(Int(snapshot.accuracy)) m"
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.message = "Standort momentan nicht verfügbar" }
    }
}

@MainActor
final class NetworkService: ObservableObject {
    @Published private(set) var kind: ConnectionKind = .other
    @Published private(set) var connected = false
    @Published private(set) var ssid: String?
    @Published private(set) var constrained = false
    @Published private(set) var revision = 0
    private let monitor = NWPathMonitor()
    private var fingerprint = ""

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let kind: ConnectionKind = path.usesInterfaceType(.wifi) ? .wifi : path.usesInterfaceType(.cellular) ? .cellular : path.usesInterfaceType(.wiredEthernet) ? .wired : .other
            let online = path.status == .satisfied
            let constrained = path.isConstrained
            // Changes to an unused cellular interface must not cancel a Wi-Fi test.
            let usedInterfaces = path.availableInterfaces.filter { path.usesInterfaceType($0.type) }.map(\.name).sorted()
            let fingerprint = "\(online):\(kind.rawValue):\(usedInterfaces.joined(separator: ","))"
            Task { @MainActor [weak self] in
                guard let self else { return }
                if fingerprint != self.fingerprint { self.revision += 1; self.fingerprint = fingerprint }
                self.kind = kind
                self.connected = online
                self.constrained = constrained
                self.refreshSSID()
            }
        }
        monitor.start(queue: DispatchQueue(label: "de.robinjuhas.speedtest.network"))
    }
    deinit { monitor.cancel() }
    func refreshSSID() {
        guard kind == .wifi else { ssid = nil; return }
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            Task { @MainActor [weak self] in
                guard let self, self.kind == .wifi else { return }
                if let old = self.ssid, let new = network?.ssid, old != new { self.revision += 1 }
                self.ssid = network?.ssid
            }
        }
    }
    func identity(alias: String) -> NetworkIdentity { .make(kind: kind, ssid: ssid, alias: alias) }
}
