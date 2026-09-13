import SwiftUI
import Charts

enum Palette {
    static func accent(_ name: String) -> Color {
        switch name {
        case "Jade": return Color(red: 0.1, green: 0.82, blue: 0.59)
        case "Roségold": return Color(red: 0.93, green: 0.48, blue: 0.53)
        case "Elektrisch": return Color(red: 0.44, green: 0.38, blue: 1)
        case "Ozean": return .blue; case "Violett": return .purple; case "Sonnenuntergang": return .orange; default: return .cyan }
    }
    static let upload = Color(red: 0.71, green: 0.56, blue: 1)
}

struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var store: AppStore
    var body: some View {
        ZStack {
            (scheme == .dark ? Color(red: 0.025, green: 0.04, blue: 0.08) : Color(red: 0.94, green: 0.96, blue: 0.99))
            GeometryReader { proxy in
                Circle().fill(Palette.accent(store.settings.accent).opacity(scheme == .dark ? 0.19 : 0.09)).frame(width: 320).blur(radius: 85)
                    .offset(x: proxy.size.width - 170, y: -100)
                Circle().fill(.indigo.opacity(0.16)).frame(width: 300).blur(radius: 85)
                    .offset(x: -170, y: proxy.size.height * 0.45)
            }
        }.ignoresSafeArea()
    }
}

struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = 26
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: radius))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.15), lineWidth: 0.7))
        }
    }
}

extension View {
    func glassPanel(radius: CGFloat = 26) -> some View { modifier(GlassSurface(radius: radius)) }
}

struct PrimaryGlassButton: ButtonStyle {
    @EnvironmentObject private var store: AppStore
    func makeBody(configuration: Configuration) -> some View {
        let color = Palette.accent(store.settings.accent)
        Group {
            if #available(iOS 26.0, *) {
                configuration.label.foregroundStyle(.primary)
                    .glassEffect(.regular.tint(color.opacity(0.55)).interactive(), in: Capsule())
            } else {
                configuration.label.foregroundStyle(.white)
                    .background(LinearGradient(colors: [color, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
            }
        }
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .shadow(color: color.opacity(0.22), radius: 20, y: 8)
    }
}

struct MetricTile: View {
    var title: String
    var symbol: String
    var value: String
    var unit: String
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.medium)).foregroundStyle(color)
            Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.55).lineLimit(1)
                .contentTransition(.numericText())
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).glassPanel()
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(LinearGradient(colors: [color.opacity(0.28), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }
}

struct SpeedTrace: View {
    var download: [SpeedSample]
    var upload: [SpeedSample] = []
    var body: some View {
        Chart {
            ForEach(download) { sample in
                AreaMark(x: .value("Zeit", sample.seconds), y: .value("Mbit/s", sample.mbps))
                    .foregroundStyle(LinearGradient(colors: [.cyan.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.linear)
                LineMark(x: .value("Sekunden", sample.seconds), y: .value("Mbit/s", sample.mbps), series: .value("Richtung", "Download"))
                    .foregroundStyle(.cyan).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.linear)
            }
            ForEach(upload) { sample in
                LineMark(x: .value("Sekunden", sample.seconds), y: .value("Mbit/s", sample.mbps), series: .value("Richtung", "Upload"))
                    .foregroundStyle(Palette.upload).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.linear)
            }
        }.chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: .automatic(includesZero: true))
            .accessibilityLabel("Geschwindigkeitsverlauf in Mbit pro Sekunde")
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        ContentUnavailableView { Label(title, systemImage: symbol) } description: { Text(message) }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
