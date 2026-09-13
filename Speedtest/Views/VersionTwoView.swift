import SwiftUI

struct VersionTwoView: View {
    @Environment(\.dismiss) private var dismiss
    private let features: [(String, String, String)] = [
        ("chart.xyaxis.line", "Einblicke pro Netz", "Median, Zeitverlauf, Datenverbrauch und Geschwindigkeitsspanne mit Netz- und Zeitfiltern."),
        ("arrow.left.arrow.right", "A / B Vergleich", "Zwei Tests nebeneinander, mit absoluten und prozentualen Unterschieden sowie Angaben zur Vergleichbarkeit."),
        ("wifi.router", "Router-Labor", "Plätze benennen, selbst messen und die Ergebnisse einer Runde vergleichen. Frühere Runden bleiben abrufbar."),
        ("star.fill", "Dein organisierter Verlauf", "Favoriten, Tags, Suche nach Server und Ort sowie Sortierung nach Tempo oder Ping."),
        ("shippingbox", "Transferzeit-Rechner", "Abschätzen, wie lange große Downloads und Uploads mit deinem gemessenen Tempo dauern."),
        ("square.and.arrow.down", "Messungen wiederherstellen", "JSON-Exporte lokal importieren, Vorschau ansehen und neue Test-IDs ohne Duplikate ergänzen."),
        ("map", "Mehr Übersicht auf der Karte", "Favoriten und Zeiträume filtern, Upload anzeigen und zur Satellitenansicht wechseln.")
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("RJ SPEEDTEST 2.0").font(.caption.bold()).tracking(3).foregroundStyle(.cyan)
                    Text("Mehr als\neine schnelle Zahl.").font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("Dein Netz verstehen – und gute Messungen wiederfinden.").font(.title3).foregroundStyle(.secondary)
                    ForEach(features.indices, id: \.self) { index in
                        let item = features[index]
                        ToolLabel(title: item.1, subtitle: item.2, symbol: item.0)
                    }
                    Button { dismiss() } label: { Text("Los geht’s").font(.headline).frame(maxWidth: .infinity).padding(20) }.buttonStyle(PrimaryGlassButton())
                }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(AmbientBackground()).navigationTitle("Das ist neu")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
        }
    }
}

struct DashboardOverview: View {
    @EnvironmentObject private var store: AppStore
    @State private var news = false
    private var today: [SpeedResult] { store.results.filter { Calendar.current.isDateInToday($0.date) } }
    var body: some View {
        VStack(spacing: 14) {
            Button { news = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles").foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Willkommen in Version 2.0").font(.subheadline.weight(.semibold))
                        Text("Neue Werkzeuge findest du unter Einblicke.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName: "chevron.right").font(.caption)
                }.padding(16).glassPanel(radius: 22)
            }.buttonStyle(.plain)
            if !store.results.isEmpty {
                HStack {
                    mini("HEUTE", "\(today.count) Tests", "clock")
                    Spacer()
                    mini("NUTZDATEN HEUTE", ByteCountFormatter.string(fromByteCount: today.reduce(Int64(0)) { $0 + $1.totalBytes }, countStyle: .decimal), "arrow.up.arrow.down")
                    Spacer()
                    mini("FAVORITEN", String(store.results.filter { $0.favorite == true }.count), "star")
                }.padding(.horizontal, 4)
            }
        }.sheet(isPresented: $news) { VersionTwoView() }
    }
    private func mini(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
            Label(value, systemImage: symbol).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}
