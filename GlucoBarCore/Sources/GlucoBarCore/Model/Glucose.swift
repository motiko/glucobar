import Foundation

/// The unit a glucose value is shown in. Values are always stored in mg/dL.
public enum GlucoseUnit: String, Codable, Sendable, CaseIterable {
    case mgPerDL = "mg/dL"
    case mmolPerL = "mmol/L"

    /// mg/dL per mmol/L for glucose.
    public static let mgPerDLPerMmol = 18.0182
}

/// A glucose concentration, stored in mg/dL.
public struct Glucose: Hashable, Comparable, Codable, Sendable {
    public var mgPerDL: Double

    public init(mgPerDL: Double) { self.mgPerDL = mgPerDL }
    public init(mmolPerL: Double) { self.mgPerDL = mmolPerL * GlucoseUnit.mgPerDLPerMmol }

    public func value(in unit: GlucoseUnit) -> Double {
        switch unit {
        case .mgPerDL: mgPerDL
        case .mmolPerL: mgPerDL / GlucoseUnit.mgPerDLPerMmol
        }
    }

    /// "124" in mg/dL, "6.9" in mmol/L.
    public func formatted(in unit: GlucoseUnit) -> String {
        switch unit {
        case .mgPerDL: String(Int(mgPerDL.rounded()))
        case .mmolPerL: String(format: "%.1f", value(in: unit))
        }
    }

    public static func < (lhs: Glucose, rhs: Glucose) -> Bool { lhs.mgPerDL < rhs.mgPerDL }
}

/// The direction and speed glucose is moving, as reported by the Glucose Source.
public enum Trend: String, Codable, Sendable, CaseIterable {
    case fallingFast, falling, flat, rising, risingFast

    public var arrow: String {
        switch self {
        case .fallingFast: "↓"
        case .falling: "↘"
        case .flat: "→"
        case .rising: "↗"
        case .risingFast: "↑"
        }
    }
}

/// One glucose value from the Patient's sensor.
public struct Reading: Hashable, Codable, Sendable {
    public var glucose: Glucose
    /// When the sensor measured it (UTC instant).
    public var timestamp: Date
    public var trend: Trend?

    public init(glucose: Glucose, timestamp: Date, trend: Trend? = nil) {
        self.glucose = glucose
        self.timestamp = timestamp
        self.trend = trend
    }

    public func isStale(now: Date, threshold: TimeInterval) -> Bool {
        now.timeIntervalSince(timestamp) > threshold
    }
}
