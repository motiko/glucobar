import Foundation

/// Everything in the JSON config file (docs/adr/0002). Secrets are referenced by name only.
/// Every key is optional when decoding, so a hand-edited file may omit anything.
public struct GlucoBarConfig: Codable, Sendable, Equatable {
    public var version = 1
    public var display = DisplayConfig()
    public var polling = PollingConfig()
    public var thresholds = Thresholds()
    public var alerts: [AlertKind: AlertSettings] = AlertSettings.defaults
    /// Named Actions; Alerts refer to them by key.
    public var actions: [String: ActionConfig] = ActionConfig.defaults
    public var libreLinkUp = LibreLinkUpSettings()
    public var launchAtLogin = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GlucoBarConfig()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        display = try c.decodeIfPresent(DisplayConfig.self, forKey: .display) ?? d.display
        polling = try c.decodeIfPresent(PollingConfig.self, forKey: .polling) ?? d.polling
        thresholds = try c.decodeIfPresent(Thresholds.self, forKey: .thresholds) ?? d.thresholds
        // Keyed by String so unknown/retired kinds (e.g. the old fastRise/fastFall) are ignored, not fatal.
        if let raw = try c.decodeIfPresent([String: AlertSettings].self, forKey: .alerts) {
            alerts = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in AlertKind(rawValue: k).map { ($0, v) } })
        } else {
            alerts = d.alerts
        }
        actions = try c.decodeIfPresent([String: ActionConfig].self, forKey: .actions) ?? d.actions
        libreLinkUp = try c.decodeIfPresent(LibreLinkUpSettings.self, forKey: .libreLinkUp) ?? d.libreLinkUp
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
    }

    /// The unit to display: the override if set, else the Patient's own, else mg/dL.
    public func displayUnit(patientUnit: GlucoseUnit?) -> GlucoseUnit {
        display.unit ?? patientUnit ?? .mgPerDL
    }
}

public struct DisplayConfig: Codable, Sendable, Equatable {
    public var showTrend = false
    public var showDelta = false
    public var showAge = false
    /// nil = follow the Patient's unit.
    public var unit: GlucoseUnit?
    /// A Reading older than this is Stale (shown grey) and raises Signal Loss.
    public var staleAfterMinutes = 15

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DisplayConfig()
        showTrend = try c.decodeIfPresent(Bool.self, forKey: .showTrend) ?? d.showTrend
        showDelta = try c.decodeIfPresent(Bool.self, forKey: .showDelta) ?? d.showDelta
        showAge = try c.decodeIfPresent(Bool.self, forKey: .showAge) ?? d.showAge
        unit = try c.decodeIfPresent(GlucoseUnit.self, forKey: .unit)
        staleAfterMinutes = try c.decodeIfPresent(Int.self, forKey: .staleAfterMinutes) ?? d.staleAfterMinutes
    }

    public var staleAfter: TimeInterval { TimeInterval(staleAfterMinutes * 60) }
}

public struct PollingConfig: Codable, Sendable, Equatable {
    public static let minimumIntervalSeconds = 60
    public var intervalSeconds = 60

    public init() {}

    /// Never poll faster than once a minute, whatever the file says.
    public var interval: TimeInterval {
        TimeInterval(max(intervalSeconds, Self.minimumIntervalSeconds))
    }
}

public struct AlertSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var repeatMinutes: Int
    /// Keys into `GlucoBarConfig.actions`.
    public var actions: [String]

    /// Low: fire only while the Trend is falling fast. High: only while rising fast.
    /// Ignored for Urgent Low and Signal Loss.
    public var onlyWithFastTrend: Bool

    public init(enabled: Bool = true, repeatMinutes: Int, actions: [String], onlyWithFastTrend: Bool = false) {
        self.enabled = enabled
        self.repeatMinutes = repeatMinutes
        self.actions = actions
        self.onlyWithFastTrend = onlyWithFastTrend
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        repeatMinutes = try c.decodeIfPresent(Int.self, forKey: .repeatMinutes) ?? 15
        actions = try c.decodeIfPresent([String].self, forKey: .actions) ?? []
        onlyWithFastTrend = try c.decodeIfPresent(Bool.self, forKey: .onlyWithFastTrend) ?? false
    }

    public var repeatInterval: TimeInterval { TimeInterval(max(repeatMinutes, 1) * 60) }

    public static let defaults: [AlertKind: AlertSettings] = [
        .low: AlertSettings(repeatMinutes: 15, actions: ["notificationSound"], onlyWithFastTrend: true),
        .high: AlertSettings(repeatMinutes: 60, actions: ["notificationSound"]),
        .urgentLow: AlertSettings(repeatMinutes: 5, actions: ["urgentSound"]),
        .signalLoss: AlertSettings(repeatMinutes: 60, actions: ["notificationSound"]),
    ]
}

public struct LibreLinkUpSettings: Codable, Sendable, Equatable {
    /// Not secret; the password lives in the SecretStore under `passwordSecret`.
    public var email: String?
    public var passwordSecret = "librelinkup.password"
    public var tokenSecret = "librelinkup.token"
    /// The 4.x API version header. Configurable because Abbott changes it (docs/adr/0001).
    public var versionHeader = "4.16.0"
    public var product = "llu.ios"
    /// Regional host learned from the login redirect, e.g. "eu".
    public var region: String?
    /// The followed Patient's id, if the Follower account follows several.
    public var patientId: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LibreLinkUpSettings()
        email = try c.decodeIfPresent(String.self, forKey: .email)
        passwordSecret = try c.decodeIfPresent(String.self, forKey: .passwordSecret) ?? d.passwordSecret
        tokenSecret = try c.decodeIfPresent(String.self, forKey: .tokenSecret) ?? d.tokenSecret
        versionHeader = try c.decodeIfPresent(String.self, forKey: .versionHeader) ?? d.versionHeader
        product = try c.decodeIfPresent(String.self, forKey: .product) ?? d.product
        region = try c.decodeIfPresent(String.self, forKey: .region)
        patientId = try c.decodeIfPresent(String.self, forKey: .patientId)
    }
}
