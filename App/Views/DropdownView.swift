import Charts
import GlucoBarCore
import SwiftUI

/// The left-click dropdown: details line, mini graph, Snooze, Settings… and Quit.
struct DropdownView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            details
            graph
            if !model.tracker.firing.isEmpty { snooze }
            Divider()
            HStack {
                // SettingsLink does nothing inside a MenuBarExtra of an LSUIElement app;
                // become a regular app briefly so the Settings window can come to the front.
                Button("Settings…") {
                    dismiss()
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Spacer()
                Button("Quit GlucoBar") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let r = model.latest {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(r.glucose.formatted(in: model.unit)).font(.system(size: 28, weight: .semibold))
                    Text(model.unit.rawValue).foregroundStyle(.secondary)
                    if let arrow = r.trend?.arrow { Text(arrow).font(.title2) }
                    if let d = model.delta { Text(Delta.formatted(d, in: model.unit)).foregroundStyle(.secondary) }
                }
                Text("\(AppModel.age(of: r)) ago · \(r.timestamp.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(model.isStale() ? .orange : .secondary)
            } else {
                Text("No readings yet").font(.headline)
            }
            Text(statusText).font(.caption).foregroundStyle(.secondary)
            if let error = model.configError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var statusText: String {
        let source = model.isDemo ? "Demo data" : "LibreLinkUp"
        switch model.status {
        case .starting: return "\(source): connecting…"
        case .ok: return "\(source): connected"
        case .notSignedIn: return "\(source): not signed in. Open Settings."
        case .error(let message): return "\(source): \(message)"
        }
    }

    @ViewBuilder private var graph: some View {
        let cutoff = Date().addingTimeInterval(-6 * 3600)
        let points = (model.snapshot?.readings ?? []).filter { $0.timestamp >= cutoff }
        if points.isEmpty {
            EmptyView()
        } else {
            let unit = model.unit
            Chart {
                RuleMark(y: .value("Low", model.config.thresholds.low.value(in: unit)))
                    .foregroundStyle(.orange.opacity(0.5))
                RuleMark(y: .value("High", model.config.thresholds.high.value(in: unit)))
                    .foregroundStyle(.orange.opacity(0.5))
                ForEach(points, id: \.timestamp) { r in
                    LineMark(x: .value("Time", r.timestamp), y: .value("Glucose", r.glucose.value(in: unit)))
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 2)) }
            .frame(height: 120)
        }
    }

    private var snooze: some View {
        // Re-render every few seconds so the countdown stays current and an ended Snooze drops out.
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let firing = model.tracker.firing
            let ends = firing.compactMap { kind in model.tracker.snoozeEnd(for: kind, now: context.date).map { (kind, $0) } }
            VStack(alignment: .leading, spacing: 6) {
                Text("Firing: " + firing.map(\.displayName).joined(separator: ", "))
                    .font(.callout)
                ForEach(ends, id: \.0) { kind, end in
                    Label {
                        Text("\(kind.displayName) snoozed until \(end.formatted(date: .omitted, time: .shortened)) · \(Self.remaining(until: end, now: context.date)) left")
                    } icon: {
                        Image(systemName: "bell.slash")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text(ends.isEmpty ? "Snooze" : "Snooze again")
                    ForEach([15, 30, 60], id: \.self) { m in
                        Button("\(m) min") { model.snooze(minutes: m) }
                    }
                }
            }
        }
    }

    /// Whole minutes left, rounded up so "0 min" never shows while still Snoozed.
    private static func remaining(until end: Date, now: Date) -> String {
        "\(max(1, Int(ceil(end.timeIntervalSince(now) / 60)))) min"
    }
}
