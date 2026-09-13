import SwiftUI

@main
struct SpeedtestApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var network = NetworkService()
    @StateObject private var location = LocationService()
    @StateObject private var engine = SpeedtestEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store).environmentObject(network)
                .environmentObject(location).environmentObject(engine)
                .environment(\.locale, Locale(identifier: "de_DE"))
                .preferredColorScheme(store.settings.appearance == "System" ? nil : store.settings.appearance == "Hell" ? .light : .dark)
                .tint(Palette.accent(store.settings.accent))
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var network: NetworkService
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var engine: SpeedtestEngine
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("welcomeNeeded") private var welcomeNeeded = true
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            DashboardView().tabItem { Label("Speedtest", systemImage: "speedometer") }.tag(0)
            HistoryView().tabItem { Label("Verlauf", systemImage: "clock.arrow.circlepath") }.tag(1)
            TestMapView().tabItem { Label("Karte", systemImage: "map") }.tag(2)
            RecordsView().tabItem { Label("Rekorde", systemImage: "trophy") }.tag(3)
            SettingsView().tabItem { Label("Einstellungen", systemImage: "slider.horizontal.3") }.tag(4)
        }
        .sheet(isPresented: $welcomeNeeded) {
            WelcomeView {
                welcomeNeeded = false
                location.activate(enabled: store.settings.locationEnabled)
            }.interactiveDismissDisabled()
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") { welcomeNeeded = false }
            else if !welcomeNeeded { location.activate(enabled: store.settings.locationEnabled) }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                network.refreshSSID()
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { engine.cancel(reason: MeasurementError.background.localizedDescription) }
            if phase == .active { network.refreshSSID(); location.refresh() }
        }
        .onChange(of: network.revision) { _, _ in
            if engine.isRunning { engine.cancel(reason: MeasurementError.networkChanged.localizedDescription) }
        }
        .onChange(of: location.authorization) { _, _ in network.refreshSSID() }
        .alert("Speichern fehlgeschlagen", isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
            Button("OK", role: .cancel) { store.storageError = nil }
        } message: { Text(store.storageError ?? "") }
    }
}

struct WelcomeView: View {
    var onContinue: () -> Void
    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(alignment: .leading, spacing: 26) {
                Spacer()
                Image(systemName: "speedometer").font(.system(size: 64, weight: .light)).foregroundStyle(.cyan)
                Text("Dein Netz.\nIn Bestform.").font(.system(size: 42, weight: .bold, design: .rounded))
                Text("Willkommen bei RJ Speedtest").font(.title3.weight(.semibold))
                Label("Echte Messungen für Download & Upload", systemImage: "arrow.up.arrow.down")
                Label("Deine Orte, Notizen und Netz-Rekorde", systemImage: "map")
                Text("Für die Karte fragt die App gleich nach deinem Standort. Die Freigabe ist freiwillig. Verlauf und Orte bleiben auf deinem Gerät.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Ein Test überträgt echte Daten an den gewählten Messanbieter. Standardmäßig bis zu etwa 1 GB Nutzdaten pro Test; das Limit kannst du ändern. Der Anbieter sieht dabei deine IP-Adresse.")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button(action: onContinue) {
                    Text("Los geht’s").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 20)
                }.buttonStyle(PrimaryGlassButton()).accessibilityIdentifier("welcomeContinue")
            }.padding(28)
        }.presentationDetents([.large])
    }
}
