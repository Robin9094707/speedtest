import SwiftUI
import MapKit

struct ResultDetailView: View {
    let resultID: UUID
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var tagsText = ""
    @State private var compare = false
    @State private var deletePrompt = false
    @State private var share = false
    private var result: SpeedResult? { store.results.first { $0.id == resultID } }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if let result {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(result.network.name, systemImage: result.network.kind.symbol).font(.title2.bold())
                                Text(result.date, format: .dateTime.day().month(.wide).year().hour().minute()).font(.subheadline).foregroundStyle(.secondary)
                            }
                            HStack {
                                Button { store.toggleFavorite(resultID) } label: {
                                    Label(result.favorite == true ? "Gemerkt" : "Merken", systemImage: result.favorite == true ? "star.fill" : "star")
                                }.tint(.orange)
                                Spacer()
                                Button { compare = true } label: { Label("Vergleichen", systemImage: "arrow.left.arrow.right") }.disabled(store.results.count < 2)
                            }.font(.subheadline.weight(.semibold))
                            if let place = result.placeLabel { Label(place, systemImage: "mappin.and.ellipse").font(.headline).foregroundStyle(.cyan) }
                            QualityCard(result: result).id(result.id)
                            HStack(spacing: 12) {
                                MetricTile(title: "Download", symbol: "arrow.down", value: store.settings.unit.format(result.download), unit: store.settings.unit.rawValue, color: .cyan)
                                MetricTile(title: "Upload", symbol: "arrow.up", value: store.settings.unit.format(result.upload), unit: store.settings.unit.rawValue, color: Palette.upload)
                            }
                            Button { share = true } label: {
                                Label("Ergebnis als Bild teilen", systemImage: "square.and.arrow.up")
                                    .font(.headline).frame(maxWidth: .infinity).padding(18).glassPanel()
                            }.buttonStyle(.plain)
                            VStack(spacing: 16) {
                                detail("HTTP-Ping", "\(SpeedMath.number(result.ping)) ms")
                                detail("Jitter", "\(SpeedMath.number(result.jitter)) ms")
                                detail("Nutzdaten", ByteCountFormatter.string(fromByteCount: result.totalBytes, countStyle: .decimal))
                                detail("Dauer", "\(SpeedMath.number(result.duration)) s")
                                detail("Messprofil", "\(result.mode) · \(result.connections) Streams")
                                detail("Server", result.server)
                                if let attempts = result.recoveryAttempts, attempts > 0 {
                                    detail("Wiederholte Lastphasen", "\(attempts) · weniger Verbindungen")
                                }
                            }.padding(20).glassPanel()
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Geschwindigkeitsverlauf").font(.headline)
                                SpeedTrace(download: result.downloadSamples, upload: result.uploadSamples).frame(height: 120)
                                HStack {
                                    Label("Download", systemImage: "circle.fill").foregroundStyle(.cyan)
                                    Label("Upload", systemImage: "circle.fill").foregroundStyle(Palette.upload)
                                    Spacer(); Text("Mbit/s")
                                }.font(.caption2)
                            }.padding(20).glassPanel()
                            if let location = result.location {
                                let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
                                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))), interactionModes: []) {
                                    Marker(result.network.name, coordinate: coordinate).tint(.cyan)
                                }.frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 24))
                                Text("Standort beim Testbeginn · Genauigkeit ±\(Int(location.accuracy)) m")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Label("Für diesen Test wurde kein Standort gespeichert.", systemImage: "location.slash").font(.caption).foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Deine Notiz", systemImage: "square.and.pencil").font(.headline)
                                TextField("Zum Beispiel: Wohnzimmer, Fenster offen …", text: $note, axis: .vertical)
                                    .lineLimit(3...8).accessibilityIdentifier("resultNote")
                                TextField("Tags, durch Kommas getrennt", text: $tagsText)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                Text("Zum Beispiel: Fenster, 5G, abends · maximal 12 Tags").font(.caption).foregroundStyle(.secondary)
                                Button("Notiz und Tags speichern") { saveMetadata() }
                                    .disabled(note == result.note && tagsText == (result.tags ?? []).joined(separator: ", ")).accessibilityIdentifier("saveNote")
                            }.padding(20).glassPanel()
                            Text("HTTP-Ping misst die Antwortzeit kleiner HTTPS-Anfragen einschließlich Serververarbeitung. Die Bandbreite ist ein Durchschnitt der Nutzdatenrate; kurze Live-Spitzen sind keine Rekorde. Serverauslastung, WLAN und VPN können das Ergebnis beeinflussen.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button(role: .destructive) { deletePrompt = true } label: {
                                Label("Diesen Speedtest löschen", systemImage: "trash").frame(maxWidth: .infinity).padding(18)
                            }.glassPanel().accessibilityIdentifier("deleteResult")
                        }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
                    }
                } else { EmptyState(symbol: "doc", title: "Ergebnis nicht verfügbar", message: "Diese Messung ist nicht im gespeicherten Verlauf.") }
            }
            .navigationTitle("Testergebnis").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { share = true } label: { Image(systemName: "square.and.arrow.up") }.disabled(result == nil) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { saveMetadata(); dismiss() }.fontWeight(.semibold)
                }
            }
            .task { note = result?.note ?? ""; tagsText = (result?.tags ?? []).joined(separator: ", ") }
            .sheet(isPresented: $compare) { ComparisonSelectionView(initialID: resultID) }
            .sheet(isPresented: $share) {
                if let r = result { ResultShareView(result: shareSnapshot(r)) }
            }
            .alert("Speedtest löschen?", isPresented: $deletePrompt) {
                Button("Nein", role: .cancel) {}
                Button("Ja, löschen", role: .destructive) { store.remove(resultID); if store.results.allSatisfy({ $0.id != resultID }) { dismiss() } }
            } message: { Text("Diese Messung wird aus Verlauf, Karte und Rekorden entfernt.") }
        }
    }
    private func saveMetadata() {
        guard let result else { return }
        if note != result.note { store.updateNote(resultID, note: note) }
        if tagsText != (result.tags ?? []).joined(separator: ", ") { store.updateTags(resultID, text: tagsText) }
    }
    private func shareSnapshot(_ result: SpeedResult) -> SpeedResult {
        var snapshot = result
        snapshot.note = note
        return snapshot
    }
    private func detail(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }.font(.subheadline)
    }
}
