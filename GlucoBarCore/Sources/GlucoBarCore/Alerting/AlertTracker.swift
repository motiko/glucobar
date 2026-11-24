import Foundation

/// Decides when an Alert's Actions run: once when its condition starts, then every
/// `repeatMinutes` until the condition clears or the Alert is Snoozed. Nothing is
/// emitted when an Alert clears.
///
/// An episode lasts as long as the condition holds (e.g. glucose below Low), even while
/// its trend gate is closed. Firing (first or repeat) needs an open gate, and repeats
/// stay spaced by `repeatMinutes`, so a Trend flickering between falling and falling
/// fast cannot re-alert every poll.
public struct AlertTracker: Sendable {
    public struct Episode: Sendable, Equatable {
        public var startedAt: Date
        /// nil while the episode has not fired yet (gate closed since it started).
        public var lastFiredAt: Date?
    }

    public private(set) var episodes: [AlertKind: Episode] = [:]
    public private(set) var snoozedUntil: [AlertKind: Date] = [:]
    /// Suppresses an Alert entirely until a time, e.g. Signal Loss right after wake.
    public private(set) var suppressedUntil: [AlertKind: Date] = [:]

    public init() {}

    /// Feed the current conditions; returns the Alerts whose Actions should run now.
    public mutating func update(
        _ conditions: AlertConditions,
        now: Date,
        settings: [AlertKind: AlertSettings]
    ) -> [AlertKind] {
        for kind in Array(episodes.keys) where !conditions.active.contains(kind) {
            episodes[kind] = nil
            snoozedUntil[kind] = nil // a Snooze ends with the condition
        }

        var toFire: [AlertKind] = []
        for kind in AlertKind.allCases where conditions.active.contains(kind) {
            guard let s = settings[kind], s.enabled else { continue }
            var episode = episodes[kind] ?? Episode(startedAt: now, lastFiredAt: nil)
            defer { episodes[kind] = episode }

            if conditions.blocked.contains(kind) { continue }
            if let until = suppressedUntil[kind], now < until { continue }
            if let until = snoozedUntil[kind], now < until { continue }
            if let last = episode.lastFiredAt, now.timeIntervalSince(last) < s.repeatInterval { continue }
            episode.lastFiredAt = now
            toFire.append(kind)
        }
        return toFire
    }

    /// Snoozes every currently firing Alert.
    public mutating func snoozeAll(until: Date) {
        for kind in firing { snoozedUntil[kind] = until }
    }

    public mutating func suppress(_ kind: AlertKind, until: Date) {
        suppressedUntil[kind] = until
    }

    /// Alerts in an episode that has fired at least once.
    public var firing: [AlertKind] { AlertKind.allCases.filter { episodes[$0]?.lastFiredAt != nil } }
}
