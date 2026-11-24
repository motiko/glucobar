import Foundation

/// The change in glucose over a window (default 5 minutes): the latest Reading minus
/// the Reading closest to `window` earlier.
public enum Delta {
    /// - Parameters:
    ///   - readings: any order; at least two needed.
    ///   - tolerance: how far the comparison Reading may be from `window` before we give up.
    public static func compute(
        _ readings: [Reading],
        window: TimeInterval = 5 * 60,
        tolerance: TimeInterval = 2 * 60
    ) -> Glucose? {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        guard let latest = sorted.last else { return nil }
        let target = latest.timestamp.addingTimeInterval(-window)
        let candidates = sorted.dropLast()
        guard let earlier = candidates.min(by: {
            abs($0.timestamp.timeIntervalSince(target)) < abs($1.timestamp.timeIntervalSince(target))
        }), abs(earlier.timestamp.timeIntervalSince(target)) <= tolerance else { return nil }
        return Glucose(mgPerDL: latest.glucose.mgPerDL - earlier.glucose.mgPerDL)
    }

    /// "+6", "−8", "±0" in mg/dL; "+0.3" in mmol/L.
    public static func formatted(_ delta: Glucose, in unit: GlucoseUnit) -> String {
        let v = delta.value(in: unit)
        let magnitude = Glucose(mgPerDL: abs(delta.mgPerDL)).formatted(in: unit)
        if magnitude == "0" || magnitude == "0.0" { return "±" + magnitude }
        return (v > 0 ? "+" : "−") + magnitude
    }
}
