import SwiftUI

struct VersionThreeView: View {
    @Environment(\.dismiss) private var dismiss
    private let features: [(String, String, String)] = [
        ("sparkles", "Dein RJ Score", "Ein animierter Gesamtscore und fünf Alltagsbewertungen von 1 bis 10 – aus den Messwerten jedes Tests."),
        ("gamecontroller.fill", "Gaming verständlich einordnen", "Ping und Jitter zählen stärker als Downloadtempo. Berechnung und Grenzen sind im Ergebnis nachlesbar."),
        ("party.popper.fill", "Deine Bestleistung feiern", "Kurzes Konfetti für gute Tests oder Netzrekorde. Einstellbar und mit Rücksicht auf reduzierte Bewegung."),
        ("circle.hexagongrid.fill", "Ein frischer Glas-Look", "Leuchtende Konturen, ein überarbeiteter Tacho und klare Ergebnis-Karten mit animierten Bewertungsbalken."),
        ("square.and.arrow.up", "Deine Punkte im Bild", "Auf Wunsch erscheinen Gesamtscore und Einzelbewertungen samt Hinweis zur Schätzung im geteilten Ergebnis."),
        ("chart.xyaxis.line", "Einblicke mit Alltagswerten", "Sieh typische Gaming-, Streaming- und Transferbewertungen pro Netz und Zeitraum. Die Werkzeuge aus Version 2 bleiben erhalten.")
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("RJ SPEEDTEST 3.0").font(.caption.bold()).tracking(3).foregroundStyle(.cyan)
                    Text("Dein Netz.\nMit Wow-Moment.").font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("Echte Messwerte. Verständliche Punkte. Ein Ergebnis, das sich sehen lassen kann.").font(.title3).foregroundStyle(.secondary)
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
                        Text("Willkommen in Version 3.0").font(.subheadline.weight(.semibold))
                        Text("Neue Punkte, Alltagsbewertungen und Konfetti.").font(.caption).foregroundStyle(.secondary)
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
        }.sheet(isPresented: $news) { VersionThreeView() }
    }
    private func mini(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
            Label(value, systemImage: symbol).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}
