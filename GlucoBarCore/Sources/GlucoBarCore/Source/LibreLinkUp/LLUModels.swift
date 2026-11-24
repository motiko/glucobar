import Foundation

// Wire models for the LibreLinkUp 4.x API. Field names follow the API (a mix of
// camelCase and PascalCase). Everything not strictly needed is optional so that
// harmless API changes don't break decoding.

struct LLUEnvelope<T: Decodable>: Decodable {
    var status: Int?
    var data: T?
    var error: LLUErrorBody?
}

struct LLUErrorBody: Decodable {
    var message: String?
}

struct LLULoginData: Decodable {
    var redirect: Bool?
    var region: String?
    var step: LLUStep?
    var authTicket: LLUAuthTicket?
    var user: LLUUser?
}

struct LLUStep: Decodable {
    var type: String?
}

struct LLUAuthTicket: Codable, Equatable {
    var token: String
    /// Unix seconds.
    var expires: Double
    /// Milliseconds.
    var duration: Double?
}

struct LLUUser: Decodable {
    var id: String
}

struct LLUConnection: Decodable {
    var patientId: String
    var firstName: String?
    var lastName: String?
    var glucoseMeasurement: LLUMeasurement?
    var targetLow: Double?
    var targetHigh: Double?
    var alarmRules: LLUAlarmRules?
}

struct LLUAlarmRules: Decodable {
    struct Threshold: Decodable { var th: Double? }
    var h: Threshold?
    var l: Threshold?
    /// Fixed (urgent) low.
    var f: Threshold?
}

struct LLUMeasurement: Decodable {
    var FactoryTimestamp: String
    var ValueInMgPerDl: Double
    var TrendArrow: Int?
    /// 1 = mg/dL, 0 = mmol/L.
    var GlucoseUnits: Int?
}

struct LLUGraph: Decodable {
    var connection: LLUConnection
    var graphData: [LLUMeasurement]?
}

/// A person who shares their data with the Follower account.
public struct LLUPatient: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
}

extension LLUMeasurement {
    /// `FactoryTimestamp` is UTC, formatted "M/d/yyyy h:mm:ss a" with no zone.
    /// (`Timestamp` is the Patient's local time and is ignored.)
    static func parseFactoryTimestamp(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "M/d/yyyy h:mm:ss a"
        return f.date(from: s)
    }

    func reading(withTrend: Bool) -> Reading? {
        guard let date = Self.parseFactoryTimestamp(FactoryTimestamp) else { return nil }
        let trend = withTrend ? TrendArrow.flatMap(LibreLinkUpSource.trend(fromArrow:)) : nil
        return Reading(glucose: Glucose(mgPerDL: ValueInMgPerDl), timestamp: date, trend: trend)
    }
}

extension LLUConnection {
    var patientDefaults: PatientDefaults {
        func positive(_ v: Double?) -> Glucose? { v.flatMap { $0 > 0 ? Glucose(mgPerDL: $0) : nil } }
        let unit: GlucoseUnit? = switch glucoseMeasurement?.GlucoseUnits {
        case 1: .mgPerDL
        case 0: .mmolPerL
        default: nil
        }
        return PatientDefaults(
            unit: unit,
            low: positive(alarmRules?.l?.th) ?? positive(targetLow),
            high: positive(alarmRules?.h?.th) ?? positive(targetHigh),
            urgentLow: positive(alarmRules?.f?.th)
        )
    }
}
