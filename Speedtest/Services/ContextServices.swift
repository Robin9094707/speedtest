import Foundation
import Combine
import CoreLocation
import Network
import NetworkExtension
import SystemConfiguration.CaptiveNetwork
import CryptoKit

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
    @Published private(set) var accessPointKey: String?
    private var refreshID = UUID()

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
        let id = UUID(); refreshID = id
        guard kind == .wifi, connected else { ssid = nil; accessPointKey = nil; return }
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            let name = network?.ssid
            let bssid = network?.bssid
            Task { @MainActor [weak self] in
                guard let self, self.refreshID == id, self.kind == .wifi, self.connected else { return }
                let fallback = Self.legacyWiFi()
                var newName = Self.validName(name) ?? Self.validName(fallback.name)
                let address = Self.validAddress(bssid) ?? Self.validAddress(fallback.address)
                if address == nil, let value = newName, ["Wi-Fi", "WLAN"].contains(value) { newName = nil }
                let key = address.map { value in
                    "wifi:ap:" + SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
                }
                // SSID groups mesh access points; BSSID is a fallback when the name is unavailable.
                // Do not identify a network from a changing/public IP address.
                let changed = (self.ssid != nil && self.ssid != newName)
                    || (self.ssid == nil && self.accessPointKey != nil && self.accessPointKey != key)
                self.ssid = newName; self.accessPointKey = key
                if changed { self.revision += 1 }
            }
        }
    }
    private static func legacyWiFi() -> (name: String?, address: String?) {
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else { return (nil, nil) }
        for interface in interfaces {
            if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any] {
                return (info[kCNNetworkInfoKeySSID as String] as? String,
                        info[kCNNetworkInfoKeyBSSID as String] as? String)
            }
        }
        return (nil, nil)
    }
    private static func validName(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return name
    }
    private static func validAddress(_ address: String?) -> String? {
        guard let address else { return nil }
        let groups = address.lowercased().split(separator: ":")
        guard groups.count == 6 else { return nil }
        let bytes = groups.compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6, bytes.contains(where: { $0 != 0 }), !bytes.allSatisfy({ $0 == 255 }) else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
    var automaticKey: String? {
        guard kind == .wifi else { return nil }
        return ssid.map { "wifi:ssid:" + $0 } ?? accessPointKey
    }
    var recognitionMessage: String {
        if ssid != nil { return "WLAN automatisch erkannt · eigener Name wird gespeichert" }
        if accessPointKey != nil { return "WLAN-Zugangspunkt erkannt · einmal benennen genügt" }
        return "iOS gibt keine WLAN-Kennung frei. Standort mit genauer Position und Wi-Fi-Berechtigung der Signatur prüfen. Ohne Kennung ist nur eine manuelle Zuordnung möglich."
    }
    func identity(alias: String, names: [String: String] = [:]) -> NetworkIdentity {
        guard let key = automaticKey else { return .make(kind: kind, ssid: ssid, alias: alias) }
        let draft = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return NetworkIdentity(kind: .wifi, name: !draft.isEmpty ? draft : names[key] ?? ssid ?? "Erkanntes WLAN", recordKey: key)
    }
}
