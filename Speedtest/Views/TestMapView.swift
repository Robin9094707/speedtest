import SwiftUI
import MapKit

struct TestMapView: View {
    @EnvironmentObject private var store: AppStore
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedID: UUID?
    @State private var selected: SpeedResult?
    @State private var filter = "Alle"
    private var mapped: [SpeedResult] {
        store.results.filter { $0.location != nil && (filter == "Alle" || $0.network.kind.rawValue == filter) }
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position, selection: $selectedID) {
                    ForEach(mapped) { result in
                        if let location = result.location {
                            Marker("↓ \(store.settings.unit.format(result.download)) \(store.settings.unit.rawValue)",
                                   systemImage: result.network.kind.symbol,
                                   coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))
                                .tint(result.network.kind == .cellular ? Palette.upload : .cyan).tag(result.id)
                        }
                    }
                    if store.settings.locationEnabled { UserAnnotation() }
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapControls { MapCompass(); MapScaleView(); if store.settings.locationEnabled { MapUserLocationButton() } }
                if mapped.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse").font(.largeTitle).foregroundStyle(.cyan)
                        Text("Deine Speedtest-Karte").font(.headline)
                        Text("Messungen mit freigegebenem, verfügbarem Standort erscheinen hier. Tippe später auf einen Pin für alle Details.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(26).glassPanel().padding(30)
                }
            }
            .navigationTitle("Deine Orte").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Picker("Kartenfilter", selection: $filter) {
                    Text("Alle").tag("Alle"); Text("WLAN").tag("WLAN"); Text("Mobilfunk").tag("Mobilfunk")
                }.pickerStyle(.segmented).padding(14).glassPanel(radius: 20).padding(.horizontal, 16).padding(.top, 6)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Label("\(mapped.count) Messungen auf der Karte", systemImage: "mappin.circle")
                    Spacer()
                    Button { position = .automatic } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .accessibilityLabel("Alle Messungen zeigen")
                }.font(.caption.weight(.medium)).padding(16).glassPanel(radius: 20).padding(16)
            }
            .onChange(of: selectedID) { _, id in
                if let id { selected = store.results.first { $0.id == id } }
            }
            .onChange(of: filter) { _, _ in position = .automatic }
            .sheet(item: $selected, onDismiss: { selectedID = nil }) { ResultDetailView(resultID: $0.id) }
        }
    }
}
