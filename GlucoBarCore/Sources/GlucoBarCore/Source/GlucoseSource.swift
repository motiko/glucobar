import Foundation

/// Where Readings come from (see docs/adr/0001). Display and alerting depend only on this.
public protocol GlucoseSource: Sendable {
    /// Fetches the latest state. Called once per poll interval.
    func fetch() async throws -> SourceSnapshot
}

/// What one poll of a Glucose Source returns.
public struct SourceSnapshot: Sendable, Equatable {
    /// Recent Readings, oldest first; the last one is the latest.
    public var readings: [Reading]
    /// The Patient's own settings as known to the Source, used to seed GlucoBar's config.
    public var patientDefaults: PatientDefaults?

    public init(readings: [Reading], patientDefaults: PatientDefaults? = nil) {
        self.readings = readings.sorted { $0.timestamp < $1.timestamp }
        self.patientDefaults = patientDefaults
    }

    public var latest: Reading? { readings.last }
}

/// Thresholds and unit configured in the Patient's own CGM app.
public struct PatientDefaults: Sendable, Equatable {
    public var unit: GlucoseUnit?
    public var low: Glucose?
    public var high: Glucose?
    public var urgentLow: Glucose?

    public init(unit: GlucoseUnit? = nil, low: Glucose? = nil, high: Glucose? = nil, urgentLow: Glucose? = nil) {
        self.unit = unit
        self.low = low
        self.high = high
        self.urgentLow = urgentLow
    }
}

public enum GlucoseSourceError: Error, Equatable, Sendable {
    /// Credentials missing or rejected.
    case notSignedIn
    case authenticationFailed(String)
    /// The Source asked us to slow down.
    case rateLimited(retryAfter: TimeInterval?)
    /// The Source exists but answers in a way we don't understand (e.g. the API was changed or switched off).
    case unavailable(String)
    case notImplemented
}
