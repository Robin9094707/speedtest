import SwiftUI
import MapKit

struct ResultShareView: View {
    let result: SpeedResult
    @Environment(\.dismiss) private var dismiss
    @State private var includeLocation = true
    @State private var includeNote = false
    @State private var mapImage: UIImage?
    @State private var image: UIImage?
    @State private var share = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .accessibilityLabel("Vorschau des Ergebnisbilds")
                    } else { ProgressView("Ergebnisbild wird erstellt …") }
                    if result.location != nil {
                        Toggle("Standort ins Bild aufnehmen", isOn: $includeLocation)
                    }
                    if !result.note.isEmpty { Toggle("Notiz ins Bild aufnehmen", isOn: $includeNote) }
                    Text(includeLocation && result.location != nil
                         ? "Das Bild enthält deinen Netzwerknamen und den gespeicherten Standort."
                         : "Das Bild enthält deinen Netzwerknamen. Es wird kein Standort geteilt.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                    Button { share = true } label: {
                        Label("Bild teilen", systemImage: "square.and.arrow.up")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 20)
                    }.buttonStyle(PrimaryGlassButton()).disabled(image == nil)
                    Text("Wähle anschließend Nachrichten, WhatsApp, AirDrop oder eine andere App im Teilen-Menü.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 540).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Speedtest teilen").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
            .task {
                render()
                guard let location = result.location else { return }
                let options = MKMapSnapshotter.Options()
                options.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012))
                options.size = CGSize(width: 440, height: 170)
                options.scale = 2
                options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
                let snapshotter = MKMapSnapshotter(options: options)
                let timeout = Task {
                    do { try await Task.sleep(nanoseconds: 8_000_000_000); snapshotter.cancel() } catch {}
                }
                defer { timeout.cancel() }
                do {
                    let snapshot = try await withTaskCancellationHandler {
                        try await snapshotter.start()
                    } onCancel: { snapshotter.cancel() }
                    try Task.checkCancellation()
                    mapImage = snapshot.image
                    render()
                } catch {
                    // Coordinates stay available offline; the image can be shared immediately.
                }
            }
            .onChange(of: includeLocation) { _, _ in render() }
            .onChange(of: includeNote) { _, _ in render() }
            .sheet(isPresented: $share) { if let image { ShareSheet(items: [image]) } }
        }
    }
    @MainActor private func render() {
        let card = ResultShareCard(result: result, includeLocation: includeLocation, includeNote: includeNote, mapImage: mapImage)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "de_DE"))
            .environment(\.dynamicTypeSize, .medium)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = true
        image = renderer.uiImage
        error = image == nil ? "Das Ergebnisbild konnte nicht erstellt werden. Öffne die Vorschau erneut." : nil
    }
}

private struct ResultShareCard: View {
    let result: SpeedResult
    let includeLocation: Bool
    let includeNote: Bool
    let mapImage: UIImage?
    private let cyan = Color(red: 0.23, green: 0.9, blue: 1)
    private let violet = Color(red: 0.76, green: 0.61, blue: 1)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("RJ SPEEDTEST", systemImage: "bolt.horizontal.circle.fill")
                    .font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(cyan)
                Spacer()
                Text("NETZREPORT").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(.white.opacity(0.55))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Dein Netz. In Bestform.").font(.system(size: 29, weight: .bold, design: .rounded))
                Label(result.network.name, systemImage: result.network.kind.symbol)
                    .font(.system(size: 18, weight: .semibold)).lineLimit(3)
                Text(result.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: 14) {
                rate("DOWNLOAD", symbol: "arrow.down", value: result.download, color: cyan)
                rate("UPLOAD", symbol: "arrow.up", value: result.upload, color: violet)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Download", systemImage: "circle.fill").foregroundStyle(cyan)
                    Label("Upload", systemImage: "circle.fill").foregroundStyle(violet)
                    Spacer(); Text("Mbit/s").foregroundStyle(.white.opacity(0.5))
                }.font(.system(size: 10, weight: .medium))
                ShareTrace(download: result.downloadSamples, upload: result.uploadSamples)
                    .frame(height: 88)
            }.padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
            VStack(spacing: 14) {
                HStack {
                    stat("HTTP-PING", "\(SpeedMath.number(result.ping)) ms")
                    stat("JITTER", "\(SpeedMath.number(result.jitter)) ms")
                    stat("DAUER", "\(SpeedMath.number(result.duration)) s")
                }
                Rectangle().fill(.white.opacity(0.09)).frame(height: 1)
                row("Download / Upload", "\(SpeedMath.number(result.download / 8)) / \(SpeedMath.number(result.upload / 8)) MB/s")
                row("Nutzdaten ↓ / ↑", "\(bytes(result.downloadBytes)) / \(bytes(result.uploadBytes))")
                row("Live-Spitze ↓ / ↑", "\(SpeedMath.number(peak(result.downloadSamples))) / \(SpeedMath.number(peak(result.uploadSamples))) Mbit/s")
                row("Messprofil", "\(result.mode) · \(result.connections) Streams")
                row("Wiederholte Lastphasen", String(result.recoveryAttempts ?? 0))
                row("Messserver", result.server)
            }.padding(18).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
            if includeLocation, let location = result.location {
                VStack(alignment: .leading, spacing: 10) {
                    Label("STANDORT BEIM TEST", systemImage: "location.fill")
                        .font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(cyan)
                    if let mapImage {
                        ZStack {
                            Image(uiImage: mapImage).resizable().scaledToFit()
                            Image(systemName: "mappin.circle.fill").font(.system(size: 28))
                                .foregroundStyle(cyan).background(.black.opacity(0.6), in: Circle())
                        }.clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Text(String(format: "%.5f°, %.5f° · ±%.0f m", location.latitude, location.longitude, location.accuracy))
                        .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                }
            } else if includeLocation {
                Label("Kein Standort gespeichert", systemImage: "location.slash").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            }
            if includeNote, !result.note.isEmpty {
                Text(result.note).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)).lineLimit(10)
            }
            Text("Echte Nutzdatenmessung · HTTP-Ping ≠ ICMP\nLive-Spitzen sind Momentaufnahmen, keine Durchschnittsrate.")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
        }
        .padding(28).frame(width: 500)
        .foregroundStyle(.white)
        .background {
            LinearGradient(colors: [Color(red: 0.025, green: 0.09, blue: 0.15), Color(red: 0.045, green: 0.035, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    private func rate(_ label: String, symbol: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(label, systemImage: symbol).font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(color)
            Text(SpeedMath.number(value)).font(.system(size: 42, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.45)
            Text("Mbit/s").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(LinearGradient(colors: [color.opacity(0.19), color.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(color.opacity(0.3), lineWidth: 1))
    }
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.5))
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label).foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 5)
            Text(value).multilineTextAlignment(.trailing)
        }.font(.system(size: 11, weight: .medium))
    }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
    private func peak(_ samples: [SpeedSample]) -> Double { samples.map(\.mbps).filter(\.isFinite).max() ?? 0 }
}

private struct ShareTrace: View {
    let download: [SpeedSample]
    let upload: [SpeedSample]
    var body: some View {
        GeometryReader { proxy in
            let all = (download + upload).filter { $0.mbps.isFinite && $0.seconds.isFinite }
            let maxRate = max(1, all.map(\.mbps).max() ?? 1)
            let maxTime = max(1, all.map(\.seconds).max() ?? 1)
            ZStack {
                ForEach(0..<3) { index in
                    Path { path in
                        let y = proxy.size.height * CGFloat(index) / 2
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }.stroke(.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                }
                trace(download, size: proxy.size, maxRate: maxRate, maxTime: maxTime).stroke(.cyan, lineWidth: 2)
                trace(upload, size: proxy.size, maxRate: maxRate, maxTime: maxTime).stroke(Palette.upload, lineWidth: 2)
            }
        }
    }
    private func trace(_ samples: [SpeedSample], size: CGSize, maxRate: Double, maxTime: Double) -> Path {
        Path { path in
            for (index, sample) in samples.filter({ $0.mbps.isFinite && $0.seconds.isFinite }).enumerated() {
                let point = CGPoint(x: max(0, sample.seconds) / maxTime * size.width,
                                    y: (1 - max(0, sample.mbps) / maxRate) * size.height)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}
