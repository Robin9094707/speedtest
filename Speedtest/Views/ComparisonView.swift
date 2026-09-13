import SwiftUI

struct ComparisonSelectionView: View {
    var initialID: UUID? = nil
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var ids: [UUID] = []
    @State private var query = ""
    @State private var showing = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Wähle zwei Messungen: A ist die Basis, B der Vergleich. Gleicher Server und gleiche Testeinstellungen erleichtern die Einordnung.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(store.results.filter { query.isEmpty || $0.searchText.localizedCaseInsensitiveContains(query) }) { result in
                    Button {
                        if ids.contains(result.id) { ids.removeAll { $0 == result.id } }
                        else if ids.count < 2 { ids.append(result.id) }
                    } label: {
                        HStack {
                            ResultRow(result: result, unit: store.settings.unit)
                            Spacer()
                            if let index = ids.firstIndex(of: result.id) {
                                Text(index == 0 ? "A" : "B").font(.headline).foregroundStyle(.cyan)
                            } else { Image(systemName: "circle").foregroundStyle(.secondary) }
                        }
                    }.buttonStyle(.plain)
                }
            }
            .navigationTitle("Zwei Tests vergleichen")
            .searchable(text: $query, prompt: "Messungen suchen")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button { showing = true } label: {
                    Text("\(ids.count)/2 ausgewählt · Vergleichen").font(.headline).frame(maxWidth: .infinity).padding(18)
                }.buttonStyle(PrimaryGlassButton()).disabled(ids.count != 2).padding().background(.ultraThinMaterial)
            }
            .onAppear { if ids.isEmpty, let initialID { ids = [initialID] } }
            .navigationDestination(isPresented: $showing) {
                if ids.count == 2, let a = store.results.first(where: { $0.id == ids[0] }), let b = store.results.first(where: { $0.id == ids[1] }) {
                    ComparisonDetailView(a: a, b: b)
                }
            }
        }
    }
}

struct ComparisonDetailView: View {
    let a: SpeedResult
    let b: SpeedResult
    @State private var swapped = false
    private var first: SpeedResult { swapped ? b : a }
    private var second: SpeedResult { swapped ? a : b }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("A · \(first.shortLabel)", systemImage: first.network.kind.symbol).font(.headline)
                Label("B · \(second.shortLabel)", systemImage: second.network.kind.symbol).font(.headline)
                Button("A und B tauschen") { swapped.toggle() }
                comparison("Download", first.download, second.download, unit: "Mbit/s", higherIsBetter: true)
                comparison("Upload", first.upload, second.upload, unit: "Mbit/s", higherIsBetter: true)
                comparison("HTTP-Ping", first.ping, second.ping, unit: "ms", higherIsBetter: false)
                comparison("Jitter", first.jitter, second.jitter, unit: "ms", higherIsBetter: false)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Vergleichbarkeit").font(.headline)
                    Label(first.sameServer(as: second) ? "Gleicher Messserver" : "Unterschiedliche Messserver", systemImage: first.sameServer(as: second) ? "checkmark.circle" : "exclamationmark.triangle")
                    Text("A: \(first.server)\nB: \(second.server)").font(.caption).foregroundStyle(.secondary)
                    Label(first.mode == second.mode && first.connections == second.connections ? "Gleiches Messprofil" : "Abweichendes Messprofil", systemImage: "slider.horizontal.3")
                    Text("A: \(first.mode) · \(first.connections) Streams · \(SpeedMath.number(first.duration)) s\nB: \(second.mode) · \(second.connections) Streams · \(SpeedMath.number(second.duration)) s")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Datenlimit A: \(first.budgetMB.map { "\($0) MB" } ?? "nicht erfasst") · B: \(second.budgetMB.map { "\($0) MB" } ?? "nicht erfasst")")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Eine einzelne Messung beweist keine dauerhafte Verbesserung. Tageszeit, Auslastung und Funkbedingungen können sich ändern.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20).glassPanel()
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(AmbientBackground()).navigationTitle("A / B Vergleich").navigationBarTitleDisplayMode(.inline)
    }
    private func comparison(_ title: String, _ old: Double, _ new: Double, unit: String, higherIsBetter: Bool) -> some View {
        let improved = higherIsBetter ? new > old : new < old
        return VStack(alignment: .leading, spacing: 13) {
            HStack { Text(title).font(.headline); Spacer(); Text(InsightMath.change(from: old, to: new)).foregroundStyle(old == new ? Color.secondary : improved ? .green : .orange) }
            HStack {
                Text("A  \(SpeedMath.number(old))").foregroundStyle(.secondary)
                Spacer(); Text("B  \(SpeedMath.number(new)) \(unit)").fontWeight(.semibold)
            }.font(.subheadline).monospacedDigit()
            Text("Differenz: \(new > old ? "+" : "")\(SpeedMath.number(new - old)) \(unit)")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).glassPanel()
    }
}
