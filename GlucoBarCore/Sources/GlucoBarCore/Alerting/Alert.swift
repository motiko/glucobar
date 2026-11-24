import Foundation

/// A condition on the Patient's glucose that GlucoBar watches for.
public enum AlertKind: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable {
    case low, high, urgentLow, signalLoss

    public var displayName: String {
        switch self {
        case .low: "Low"
        case .high: "High"
        case .urgentLow: "Urgent Low"
        case .signalLoss: "Signal Loss"
        }
    }
}

/// Low/High/Urgent Low limits. GlucoBar owns these; they are seeded once from the Source.
public struct Thresholds: Codable, Sendable, Equatable {
    public var low: Glucose
    public var high: Glucose
    public var urgentLow: Glucose
    /// Set after the first successful sign-in copied the Patient's own thresholds.
    public var seededFromSource: Bool

    public init(low: Glucose = Glucose(mgPerDL: 70), high: Glucose = Glucose(mgPerDL: 180),
                urgentLow: Glucose = Glucose(mgPerDL: 55), seededFromSource: Bool = false) {
        self.low = low
        self.high = high
        self.urgentLow = urgentLow
        self.seededFromSource = seededFromSource
    }

    /// Copies the Patient's own values once; later edits in GlucoBar are never overwritten.
    public mutating func seedIfNeeded(from defaults: PatientDefaults?) {
        guard !seededFromSource, let defaults else { return }
        if let v = defaults.low { low = v }
        if let v = defaults.high { high = v }
        if let v = defaults.urgentLow { urgentLow = v }
        seededFromSource = true
    }
}

/// The result of evaluating the latest Reading.
public struct AlertConditions: Sendable, Equatable {
    /// Alerts whose glucose condition holds (an episode is in progress).
    public var active: Set<AlertKind>
    /// Active Alerts that may not fire right now because their trend gate is closed.
    public var blocked: Set<AlertKind>

    public init(active: Set<AlertKind>, blocked: Set<AlertKind> = []) {
        self.active = active
        self.blocked = blocked.intersection(active)
    }
}

/// Which Alerts hold right now. Pure function of the latest Reading and settings.
public enum AlertEvaluator {
    public static func evaluate(
        latest: Reading?,
        now: Date,
        thresholds: Thresholds,
        staleAfter: TimeInterval,
        alerts: [AlertKind: AlertSettings]
    ) -> AlertConditions {
        // A Stale Reading is not trusted as current: only Signal Loss applies.
        guard let latest, !latest.isStale(now: now, threshold: staleAfter) else {
            return AlertConditions(active: [.signalLoss])
        }

        var active: Set<AlertKind> = []
        var blocked: Set<AlertKind> = []
        let g = latest.glucose
        if g < thresholds.urgentLow {
            active.insert(.urgentLow) // supersedes Low; never trend-gated
        } else if g < thresholds.low {
            active.insert(.low)
            if alerts[.low]?.onlyWithFastTrend == true, latest.trend != .fallingFast { blocked.insert(.low) }
        }
        if g > thresholds.high {
            active.insert(.high)
            if alerts[.high]?.onlyWithFastTrend == true, latest.trend != .risingFast { blocked.insert(.high) }
        }
        return AlertConditions(active: active, blocked: blocked)
    }
}
