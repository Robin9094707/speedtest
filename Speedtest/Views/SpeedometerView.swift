import SwiftUI

struct SpeedometerView: View, Animatable {
    var value: Double
    var maximum: Double
    var unit: SpeedUnit
    var color: Color
    var subtitle: String
    var animatableData: Double { get { value } set { value = newValue } }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.49)
            let radius = side * 0.44
            ZStack {
                Circle().fill(RadialGradient(colors: [color.opacity(0.15), color.opacity(0.015), .clear], center: .center, startRadius: 0, endRadius: radius))
                    .frame(width: radius * 2.05, height: radius * 2.05).position(center)
                Canvas { context, _ in
                    let fraction = min(1, max(0, value / maximum))
                    var halo = Path()
                    halo.addArc(center: center, radius: radius + 9, startAngle: .degrees(135), endAngle: .degrees(405), clockwise: false)
                    context.stroke(halo, with: .color(color.opacity(0.12)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    var track = Path()
                    track.addArc(center: center, radius: radius, startAngle: .degrees(135), endAngle: .degrees(405), clockwise: false)
                    context.stroke(track, with: .color(.gray.opacity(0.16)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    if fraction > 0 {
                        var active = Path()
                        active.addArc(center: center, radius: radius, startAngle: .degrees(135), endAngle: .degrees(135 + 270 * fraction), clockwise: false)
                        var glow = context
                        glow.addFilter(.shadow(color: color.opacity(0.45), radius: 7))
                        glow.stroke(active, with: .linearGradient(Gradient(colors: [color.opacity(0.5), color, Palette.upload]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: proxy.size.width, y: 0)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    }
                    for index in 0...50 {
                        let angle = (135 + Double(index) / 50 * 270) * .pi / 180
                        let major = index.isMultiple(of: 10)
                        let outer = radius - 15
                        let inner = outer - (major ? 14.0 : 6.0)
                        var tick = Path()
                        tick.move(to: point(center, outer, angle)); tick.addLine(to: point(center, inner, angle))
                        context.stroke(tick, with: .color(.secondary.opacity(major ? 0.8 : 0.35)), lineWidth: major ? 2 : 1)
                        if major {
                            let number = unit.convert(maximum * Double(index) / 50)
                            let text = Text(number.formatted(.number.locale(Locale(identifier: "de_DE")).precision(.fractionLength(0))))
                                .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                            context.draw(text, at: point(center, inner - 17, angle))
                        }
                    }
                    let angle = (135 + 270 * fraction) * .pi / 180
                    let tip = point(center, radius, angle)
                    context.fill(Path(ellipseIn: CGRect(x: tip.x - 4, y: tip.y - 4, width: 8, height: 8)), with: .color(color))
                    var needle = Path()
                    needle.move(to: point(center, radius * 0.64, angle))
                    needle.addLine(to: point(center, radius * 0.87, angle))
                    context.stroke(needle, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
                VStack(spacing: 4) {
                    Text(unit.format(max(0, value))).font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    Text(unit.rawValue).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Text(subtitle.uppercased()).font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(color).padding(.top, 12)
                }.frame(width: radius * 1.28).position(x: center.x, y: center.y + 8)
                Text("BIS \(SpeedMath.number(unit.convert(maximum))) \(unit.rawValue.uppercased())")
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.5).foregroundStyle(.secondary)
                    .position(x: center.x, y: center.y + radius * 0.93)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(subtitle), \(unit.format(value)) \(unit.rawValue)")
        .accessibilityIdentifier("speedometer")
    }

    private func point(_ center: CGPoint, _ radius: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}
