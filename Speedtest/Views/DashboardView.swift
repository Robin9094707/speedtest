import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var network: NetworkService
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var engine: SpeedtestEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var networkAlias = ""
    @State private var cellularPrompt = false
    @State private var selectedResult: SpeedResult?
    @State private var showNetworkEditor = false
    private var maximum: Double {
        store.settings.gaugeScale == .automatic
            ? max(engine.gaugeMaximum, SpeedMath.gaugeMaximum(engine.liveSpeed))
            : store.settings.gaugeScale.initialMaximum
    }
    private var accent: Color { Palette.accent(store.settings.accent) }
    private var animate: Bool { store.settings.animations && !reduceMotion }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        compactNetwork
                        VStack(spacing: 0) {
                            HStack {
                                Label(engine.phase.rawValue, systemImage: engine.isRunning ? "waveform.path" : "smallcircle.filled.circle")
                                    .font(.caption.weight(.semibold)).foregroundStyle(engine.isRunning ? accent : .secondary)
                                Spacer()
                                Text("\(store.settings.mode.rawValue) · \(store.settings.connections) Streams")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.horizontal, 20).padding(.top, 20)
                            SpeedometerView(value: engine.liveSpeed, maximum: maximum, unit: store.settings.unit,
                                            color: engine.phase == .upload ? Palette.upload : accent,
                                            subtitle: engine.phase == .complete ? "Download-Ergebnis" : engine.phase.rawValue)
                                .frame(height: 300)
                                .animation(animate ? .linear(duration: 0.22) : nil, value: engine.liveSpeed)
                            if engine.isRunning {
                                ProgressView(value: engine.progress).tint(engine.phase == .upload ? Palette.upload : accent)
                                    .padding(.horizontal, 24).padding(.bottom, 20)
                            }
                        }.glassPanel(radius: 32)

                        startControl

                        if !network.connected {
                            Label("Keine Internetverbindung", systemImage: "wifi.slash").font(.subheadline).foregroundStyle(.orange)
                        }
                        if let error = engine.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.orange)
                                .padding(18).frame(maxWidth: .infinity, alignment: .leading).glassPanel()
                        }
                        if let message = engine.recoveryMessage {
                            Label(message, systemImage: "arrow.clockwise").font(.subheadline).foregroundStyle(accent)
                                .padding(18).frame(maxWidth: .infinity, alignment: .leading).glassPanel()
                        }
                        HStack(spacing: 12) {
                            MetricTile(title: "Download", symbol: "arrow.down", value: engine.download.map(store.settings.unit.format) ?? "—", unit: store.settings.unit.rawValue, color: accent)
                            MetricTile(title: "Upload", symbol: "arrow.up", value: engine.upload.map(store.settings.unit.format) ?? "—", unit: store.settings.unit.rawValue, color: Palette.upload)
                        }
                        HStack {
                            smallMetric("HTTP-Ping", engine.ping.map { "\(SpeedMath.number($0)) ms" } ?? "—")
                            Spacer()
                            smallMetric("Jitter", engine.jitter.map { "\(SpeedMath.number($0)) ms" } ?? "—")
                            Spacer()
                            smallMetric("Nutzdaten", ByteCountFormatter.string(fromByteCount: engine.transferred, countStyle: .decimal))
                        }.padding(20).glassPanel()

                        if !engine.awards.isEmpty && engine.phase == .complete {
                            AwardBanner(awards: engine.awards, animate: animate)
                                .transition(.scale(scale: 0.95).combined(with: .opacity))
                        }
                        if let result = engine.result {
                            Button { selectedResult = result } label: {
                                HStack { Label("Ergebnis & Notiz", systemImage: "doc.text.magnifyingglass"); Spacer(); Image(systemName: "chevron.right") }
                                    .font(.headline).padding(20).glassPanel()
                            }.buttonStyle(.plain)
                        }
                        if !engine.samples.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(engine.result == nil ? "LIVE-VERLAUF" : "MESSVERLAUF").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
                                SpeedTrace(download: engine.result?.downloadSamples ?? (engine.phase == .upload ? [] : engine.samples),
                                           upload: engine.result?.uploadSamples ?? (engine.phase == .upload ? engine.samples : [])).frame(height: 80)
                                Text("Momentane Rate · Mbit/s").font(.caption2).foregroundStyle(.secondary)
                            }.padding(20).glassPanel()
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "globe.europe.africa").foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Cloudflare Edge").font(.subheadline.weight(.semibold))
                                Text("Download → Upload · bis ca. \(store.settings.budgetMB) MB Nutzdaten pro Test. Geschwindigkeit und Datenverbrauch sind echte Messwerte.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.horizontal, 4)
                    }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }.scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedResult) { ResultDetailView(resultID: $0.id) }
            .sheet(isPresented: $showNetworkEditor) {
                NavigationStack {
                    ZStack {
                        AmbientBackground()
                        ScrollView { networkPanel.padding(20) }
                    }
                    .navigationTitle("Dein Netzprofil").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { showNetworkEditor = false } } }
                }.presentationDetents([.medium, .large])
            }
            .alert("Über Mobilfunk messen?", isPresented: $cellularPrompt) {
                Button("Abbrechen", role: .cancel) {}
                Button("Test starten") { start() }
            } message: { Text("Dieser Test überträgt bis zu etwa \(store.settings.budgetMB) MB Nutzdaten. Dein Mobilfunkanbieter kann zusätzlich Protokolldaten mitzählen.") }
            .onChange(of: network.revision) { _, _ in networkAlias = "" }
            .animation(animate ? .spring(duration: 0.5) : nil, value: engine.awards)
        }
    }

    private var startControl: some View {
        TimelineView(.periodic(from: .now, by: 1)) { clock in
            let remaining = max(0, ceil(engine.cooldownUntil?.timeIntervalSince(clock.date) ?? 0))
            let pauseLabel = remaining > 86_400 ? "Serverpause · mehr als 24 Std." : "Serverpause · \(Int(min(86_400, remaining))) s"
            Button {
                if engine.isRunning { engine.cancel() }
                else if network.kind == .cellular && store.settings.confirmCellular { cellularPrompt = true }
                else { start() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: engine.isRunning ? "stop.fill" : remaining > 0 ? "hourglass" : "bolt.fill")
                    Text(engine.isRunning ? "Test stoppen" : remaining > 0 ? pauseLabel : "Speedtest starten")
                }.font(.title3.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 22)
            }.buttonStyle(PrimaryGlassButton())
                .disabled(!engine.isRunning && (!network.connected || remaining > 0))
                .accessibilityIdentifier("startTest")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle.fill").foregroundStyle(accent)
                Text("RJ SPEEDTEST").tracking(3).font(.system(size: 11, weight: .bold))
                Spacer()
                Text("LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.5)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(accent.opacity(0.12), in: Capsule()).foregroundStyle(accent)
            }
            Text("Dein Netz. In Bestform.").font(.system(size: 29, weight: .bold, design: .rounded)).minimumScaleFactor(0.8).lineLimit(2)
            Text(engine.isRunning ? "Ein Moment. Dein Netz zeigt, was es kann." : "Ein Tippen. Alle Antworten.")
                .font(.subheadline).foregroundStyle(.secondary)
        }.padding(.top, 12)
    }

    private var networkPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: network.kind.symbol).font(.title3).foregroundStyle(accent)
                    .frame(width: 42, height: 42).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(network.identity(alias: networkAlias).name).font(.headline).lineLimit(1)
                    Text(network.constrained ? "Datensparmodus ist aktiv" : network.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(network.connected ? .green : .orange).frame(width: 7, height: 7)
            }
            if network.ssid == nil {
                TextField(network.kind == .wifi ? "WLAN benennen – z. B. Zuhause" : "Netzprofil – z. B. o2", text: $networkAlias)
                    .font(.subheadline).textInputAutocapitalization(.words).autocorrectionDisabled()
                    .disabled(engine.isRunning).accessibilityIdentifier("networkAlias")
                if network.kind == .wifi {
                    Text("iOS gibt den WLAN-Namen nicht immer frei. Wähle für dasselbe WLAN immer denselben Namen. Ohne Namen werden keine WLAN-Rekorde zugeordnet.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if network.ssid == nil && !store.records.isEmpty && !engine.isRunning {
                Menu {
                    ForEach(store.records.filter { $0.kind == network.kind }) { record in
                        Button(record.name) { networkAlias = record.name }
                    }
                } label: { Label("Gespeichertes Netz wählen", systemImage: "chevron.down").font(.caption) }
            }
            Label(store.settings.locationEnabled ? location.message : "Standort ausgeschaltet", systemImage: "location")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(18).glassPanel()
    }

    private var compactNetwork: some View {
        Button { showNetworkEditor = true } label: {
            HStack(spacing: 13) {
                Image(systemName: network.kind.symbol).font(.title3).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(network.identity(alias: networkAlias).name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(network.kind == .wifi && network.ssid == nil && networkAlias.isEmpty ? "Für WLAN-Rekorde hier benennen" : network.connected ? "Verbunden · Netzprofil bearbeiten" : "Keine Internetverbindung")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 5)
                Circle().fill(network.connected ? .green : .orange).frame(width: 7, height: 7)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }.padding(16).glassPanel(radius: 22)
        }.buttonStyle(.plain).disabled(engine.isRunning).accessibilityIdentifier("editNetwork")
    }

    private func smallMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        }
    }
    private func start() {
        guard network.connected else { return }
        if store.settings.haptics { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        engine.start(store: store, network: network.identity(alias: networkAlias), location: location)
    }
}

struct AwardBanner: View {
    let awards: [String]
    let animate: Bool
    @State private var revealed = false
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "trophy.fill").font(.system(size: 35)).foregroundStyle(.yellow)
                .rotationEffect(.degrees(revealed ? 0 : -18)).scaleEffect(revealed ? 1 : 0.4)
                .symbolEffect(.bounce, options: .nonRepeating, value: animate && revealed)
            VStack(alignment: .leading, spacing: 5) {
                Text("Persönliche Bestmarke!").font(.headline)
                ForEach(awards, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Image(systemName: "sparkles").foregroundStyle(.yellow)
        }.padding(22).glassPanel()
            .onAppear { withAnimation(animate ? .spring(duration: 0.65, bounce: 0.45) : nil) { revealed = true } }
            .accessibilityElement(children: .combine)
    }
}
