import SwiftUI

extension QualityUseCase {
    var color: Color {
        switch self {
        case .gaming: return .mint
        case .streaming: return .cyan
        case .calls: return .blue
        case .download: return .indigo
        case .upload: return Palette.upload
        }
    }
}

struct QualityCard: View {
    let result: SpeedResult
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var details = false
    private var profile: QualityProfile { QualityProfile(result) }
    private var animated: Bool { store.settings.animations && !reduceMotion }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 18) {
                if profile.available {
                    ScoreRing(points: Double(profile.points), revealed: revealed).frame(width: 98, height: 98)
                } else {
                    Image(systemName: "questionmark.circle").font(.system(size: 60, weight: .ultraLight)).foregroundStyle(.secondary).frame(width: 98, height: 98)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("DEIN RJ SCORE").font(.system(size: 10, weight: .heavy)).tracking(2).foregroundStyle(.cyan)
                    Text(profile.title).font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Einschätzung aus diesem Test").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if profile.available {
                ForEach(profile.ratings) { rating in
                    HStack(spacing: 12) {
                        Image(systemName: rating.category.symbol).font(.subheadline).foregroundStyle(rating.category.color).frame(width: 26)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(rating.category.rawValue).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(rating.value.formatted(.number.precision(.fractionLength(1)))) / 10")
                                    .font(.subheadline.weight(.bold)).monospacedDigit()
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(rating.category.color.opacity(0.1))
                                    Capsule().fill(LinearGradient(colors: [rating.category.color.opacity(0.55), rating.category.color], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: proxy.size.width * (revealed ? rating.value / 10 : 0))
                                }
                            }.frame(height: 5)
                        }
                    }.accessibilityElement(children: .combine)
                }
            }
            Button { details = true } label: {
                HStack { Label("Was bedeuten die Punkte?", systemImage: "info.circle"); Spacer(); Image(systemName: "chevron.right") }
                    .font(.caption.weight(.semibold))
            }.buttonStyle(.plain).foregroundStyle(.secondary)
            Text("Schätzung · kein Spielserver- oder Lastlatenztest").font(.caption2).foregroundStyle(.secondary)
        }.padding(22)
            .glassPanel(radius: 30)
            .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(LinearGradient(colors: [.cyan.opacity(0.4), .clear, .purple.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .onAppear { withAnimation(animated ? .easeOut(duration: 0.9) : nil) { revealed = true } }
            .onChange(of: animated) { _, _ in revealed = true }
            .sheet(isPresented: $details) { QualityDetailsView(result: result) }
    }
}

struct ScoreRing: View {
    let points: Double
    var revealed = true
    var body: some View {
        ZStack {
            Circle().stroke(.cyan.opacity(0.1), lineWidth: 7)
            Circle().trim(from: 0, to: revealed ? min(1, max(0, points / 100)) : 0)
                .stroke(AngularGradient(colors: [.mint, .cyan, Palette.upload], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                AnimatedScoreNumber(value: revealed ? points : 0)
                Text("/ 100").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("RJ Score \(Int(points)) von 100 Punkten")
    }
}

private struct AnimatedScoreNumber: View, Animatable {
    var value: Double
    var animatableData: Double { get { value } set { value = newValue } }
    var body: some View {
        Text(String(Int(value.rounded()))).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
    }
}

struct QualityDetailsView: View {
    let result: SpeedResult
    @Environment(\.dismiss) private var dismiss
    private var profile: QualityProfile { QualityProfile(result) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 20) {
                        if profile.available {
                            ScoreRing(points: Double(profile.points)).frame(width: 100, height: 100)
                        } else {
                            Image(systemName: "questionmark.circle").font(.largeTitle).frame(width: 100, height: 100)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(profile.title).font(.title2.bold())
                            Text(QualityProfile.method).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Die Punkte sind eine eigene Einordnung der App, kein standardisiertes Gütesiegel. Sie werden aus Download, Upload, HTTP-Ping und Jitter berechnet – auch für deine älteren Tests nach demselben Modell.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(profile.ratings) { rating in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(rating.category.rawValue, systemImage: rating.category.symbol).foregroundStyle(rating.category.color)
                                Spacer()
                                Text("\(rating.value.formatted(.number.precision(.fractionLength(1)))) / 10").monospacedDigit()
                            }.font(.headline)
                            Text(rating.label).font(.subheadline.weight(.semibold))
                            Text(rating.explanation).font(.subheadline).foregroundStyle(.secondary)
                            DisclosureGroup("Berechnung ansehen") {
                                Text(rating.formula).font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                            }.font(.caption.weight(.semibold))
                        }.padding(20).glassPanel()
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Die Grenzen der Einschätzung", systemImage: "scope").font(.headline)
                        Text("Gaming: Der HTTP-Ping geht zum Messserver. Die Latenz zu deinem Spielserver kann anders sein. Paketverlust, Bufferbloat, Latenz unter Last und WLAN-Funkstörungen werden hier nicht separat gemessen.")
                        Text("Streaming und Videoanrufe: Auflösung, Codec, Zahl der Geräte und jeweiliger Anbieter fehlen im Modell. Eine hohe Punktzahl garantiert keine störungsfreie Sitzung.")
                        Text("Alle Grenzwerte sind App-Entscheidungen. Zwischen den Stützpunkten wird linear gerechnet und am Skalenende begrenzt. Mehr Tests bringen keine zusätzlichen Sammelpunkte; ein Test wird allein nach seinen Messwerten bewertet.")
                    }.font(.subheadline).foregroundStyle(.secondary).padding(20).glassPanel()
                    DisclosureGroup("Gesamtscore und gemeinsame Kurven") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Gesamt: Gaming 30 %, Streaming 20 %, Videoanrufe 20 %, Downloads 15 %, Uploads 15 %. Gewichteter Durchschnitt × 10, auf ganze Punkte gerundet (10–100). Einzelkategorien 1–10. Fehlende vollständige Messdaten erhalten keine Bewertung.")
                            Text("HTTP-Ping: 0/20/50/100/200/300 ms → 10/10/8/5/2/1 Punkte. Jitter: 0/3/10/25/60/100 ms → 10/10/8/5/2/1 Punkte.")
                            Text("Konfetti bei mindestens 75 Gesamtpunkten oder einem persönlichen Netzrekord – abhängig von deinen Einstellungen. Eine Bestmarke ist nicht automatisch ein guter Gaming-Wert.")
                        }.font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                    }
                }.padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(AmbientBackground()).navigationTitle("Dein Netz im Alltag").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
        }
    }
}

struct QualityInsightsCard: View {
    let results: [SpeedResult]
    private var profiles: [QualityProfile] { results.map(QualityProfile.init).filter(\.available) }
    var body: some View {
        let values = profiles
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Dein Netz im Alltag", systemImage: "sparkles").font(.headline)
                    Spacer()
                    Text("\(values.count) Tests").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(QualityUseCase.allCases) { category in
                    let median = InsightMath.median(values.compactMap { $0.ratings.first { $0.category == category }?.value })
                    HStack {
                        Label(category.rawValue, systemImage: category.symbol).foregroundStyle(category.color)
                        Spacer()
                        Text("\(median.formatted(.number.precision(.fractionLength(1)))) / 10").monospacedDigit().fontWeight(.semibold)
                    }.font(.subheadline)
                }
                Text("Median der geschätzten Kategorien im gewählten Filter · \(QualityProfile.method). Kein Spielserver-, Paketverlust- oder Lastlatenztest.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(22).glassPanel(radius: 28)
        }
    }
}
