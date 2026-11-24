import Foundation

/// Fake Readings for UI development and tests. Never used unless explicitly requested.
public struct DemoGlucoseSource: GlucoseSource {
    public init() {}

    public func fetch() async throws -> SourceSnapshot {
        let now = Date()
        // A slow sine wave between ~60 and ~200 mg/dL, one Reading per minute for 6 h.
        let readings = (0..<360).reversed().map { minutesAgo -> Reading in
            let t = now.addingTimeInterval(TimeInterval(-minutesAgo * 60))
            let phase = t.timeIntervalSince1970 / 3600 * .pi / 2
            return Reading(glucose: Glucose(mgPerDL: 130 + 70 * sin(phase)), timestamp: t,
                           trend: Self.trend(slope: cos(phase)))
        }
        return SourceSnapshot(readings: readings,
                              patientDefaults: PatientDefaults(unit: .mgPerDL, low: Glucose(mgPerDL: 70),
                                                               high: Glucose(mgPerDL: 180)))
    }

    private static func trend(slope: Double) -> Trend {
        switch slope {
        case ..<(-0.8): .fallingFast
        case ..<(-0.3): .falling
        case ..<0.3: .flat
        case ..<0.8: .rising
        default: .risingFast
        }
    }
}
