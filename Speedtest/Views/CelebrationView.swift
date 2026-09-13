import SwiftUI

struct CelebrationView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var engine: SpeedtestEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var burst: Burst?
    private struct Burst: Identifiable {
        let id: UUID
        let started: Date
        let title: String
    }
    private var enabled: Bool { store.settings.animations && !reduceMotion && store.settings.celebrationStyle != .off }
    var body: some View {
        ZStack(alignment: .top) {
            if let burst, enabled, scenePhase == .active {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { clock in
                    let elapsed = clock.date.timeIntervalSince(burst.started)
                    ZStack {
                    Canvas { context, size in
                        let colors: [Color] = [.cyan, .mint, .yellow, .pink, Palette.upload]
                        for index in 0..<72 {
                            let delay = Double(index % 9) * 0.045
                            let time = max(0, elapsed - delay)
                            guard elapsed >= delay, time < 2.8 else { continue }
                            let fraction = time / 2.8
                            let x = size.width * Double((index * 37) % 101) / 100 + sin(time * 3 + Double(index)) * 28
                            let y = -20 + (size.height + 80) * fraction
                            var particle = context
                            particle.opacity = max(0, min(1, (1 - fraction) * 3))
                            particle.translateBy(x: x, y: y)
                            particle.rotate(by: .degrees(Double(index * 47) + time * (index.isMultiple(of: 2) ? 170 : -210)))
                            let rect = CGRect(x: -3, y: -5, width: index.isMultiple(of: 3) ? 5 : 7, height: 10)
                            particle.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(colors[index % colors.count]))
                        }
                    }
                    VStack {
                        Label(burst.title, systemImage: "sparkles")
                            .font(.subheadline.weight(.bold)).padding(.horizontal, 18).padding(.vertical, 12)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(.cyan.opacity(0.3), lineWidth: 1))
                            .opacity(min(1, max(0, (3.2 - elapsed) * 2)))
                            .padding(.top, 12)
                        Spacer()
                    }
                    }
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .onChange(of: engine.result?.id) { _, id in
            guard enabled, scenePhase == .active, let id, let result = engine.result,
                  store.results.contains(where: { $0.id == id }) else { burst = nil; return }
            let record = !engine.awards.isEmpty
            let profile = QualityProfile(result)
            let good = profile.available && profile.points >= 75
            guard record || (store.settings.celebrationStyle == .goodTests && good) else { burst = nil; return }
            burst = Burst(id: id, started: Date(), title: record ? "Deine neue Netz-Bestmarke!" : "Starkes Ergebnis · \(profile.points) Punkte")
        }
        .task(id: burst?.id) {
            guard let id = burst?.id else { return }
            do { try await Task.sleep(nanoseconds: 3_400_000_000) } catch { return }
            if burst?.id == id { burst = nil }
        }
        .onChange(of: enabled) { _, value in if !value { burst = nil } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { burst = nil } }
    }
}
