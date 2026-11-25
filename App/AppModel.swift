import AppKit
import GlucoBarCore
import Observation
import os

/// App state: config, latest Source snapshot, polling loop and Alert dispatch.
@MainActor @Observable
final class AppModel {
    enum Status: Equatable {
        case starting
        case ok
        case notSignedIn
        case error(String)
    }

    var config: GlucoBarConfig
    private(set) var snapshot: SourceSnapshot?
    private(set) var status: Status = .starting
    private(set) var lastPoll: Date?
    /// Email set and a password stored in Keychain.
    private(set) var hasCredentials = false
    private(set) var tracker = AlertTracker()
    /// Launch with `-demo` to show fake Readings. Never on by default.
    let isDemo = CommandLine.arguments.contains("-demo")

    let configStore = ConfigStore()
    let secrets = KeychainSecretStore()
    private var pollTask: Task<Void, Never>?
    private var source: any GlucoseSource = DemoGlucoseSource()
    private var configWatcher: ConfigWatcher?
    /// Set while config.json on disk can't be read; the last good config stays in use.
    private(set) var configError: String?
    private var consecutiveFailures = 0
    private let log = Logger(subsystem: "dev.moti.glucobar", category: "app")

    /// After wake, give the Source this long before Signal Loss may fire.
    private let wakeGrace: TimeInterval = 120

    init() {
        do {
            config = try configStore.loadOrCreate()
        } catch {
            config = GlucoBarConfig()
            status = .error("Config unreadable: \(error.localizedDescription)")
        }
        hasCredentials = config.libreLinkUp.email != nil
            && (try? secrets.secret(named: config.libreLinkUp.passwordSecret)) != nil
        SoundPerformer.requestAuthorization()
        LaunchAtLogin.apply(config.launchAtLogin)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        }
        configWatcher = ConfigWatcher(url: configStore.url) { [weak self] in self?.reloadConfig() }
        restartPolling()
    }

    // MARK: Polling

    /// Recreates the Source (picking up new credentials/settings) and polls now.
    func restartPolling() {
        pollTask?.cancel()
        consecutiveFailures = 0
        source = makeSource()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.pollOnce()
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Polls once and returns how long to wait before the next poll.
    private func pollOnce() async -> TimeInterval {
        let interval = config.polling.interval
        var delay = interval
        do {
            let snap = try await source.fetch()
            let isNew = snap.latest?.timestamp != snapshot?.latest?.timestamp
            snapshot = snap
            if isNew, let r = snap.latest {
                let trend = r.trend?.arrow ?? "?"
                let d = delta.map { Delta.formatted($0, in: unit) } ?? "-"
                let values = "\(r.glucose.formatted(in: unit)) \(trend) Δ\(d)"
                // os.Logger needs privacy to be a compile-time choice, hence the branch.
                if config.debugLogging {
                    log.info("Reading \(values, privacy: .public) at \(r.timestamp, privacy: .public)")
                } else {
                    log.info("Reading \(values, privacy: .private) at \(r.timestamp, privacy: .public)")
                }
            }
            status = .ok
            consecutiveFailures = 0
            if !isDemo { // demo values must never become the Patient's thresholds
                let before = config.thresholds
                config.thresholds.seedIfNeeded(from: snap.patientDefaults)
                if config.thresholds != before { saveConfig() }
            }
        } catch GlucoseSourceError.notSignedIn {
            status = .notSignedIn
        } catch let GlucoseSourceError.authenticationFailed(message) {
            status = .error(message) // the Source won't retry until credentials change
        } catch let GlucoseSourceError.unavailable(message) {
            consecutiveFailures += 1
            status = .error(message)
            delay = backoff(interval)
        } catch let GlucoseSourceError.rateLimited(retryAfter) {
            consecutiveFailures += 1
            status = .error("Rate limited")
            delay = max(retryAfter ?? 0, backoff(interval))
        } catch {
            consecutiveFailures += 1
            status = .error(String(describing: error))
            delay = backoff(interval)
        }
        lastPoll = Date()
        evaluateAlerts(now: Date())
        return delay
    }

    private func backoff(_ interval: TimeInterval) -> TimeInterval {
        min(interval * pow(2, Double(consecutiveFailures)), 300)
    }

    private func makeSource() -> any GlucoseSource {
        if isDemo { return DemoGlucoseSource() }
        let llu = config.libreLinkUp
        let password = try? secrets.secret(named: llu.passwordSecret)
        let creds = llu.email.flatMap { email in
            password.flatMap { $0 }.map { LibreLinkUpSource.Credentials(email: email, password: $0) }
        }
        return LibreLinkUpSource(settings: llu, credentials: creds, secrets: secrets)
    }

    /// Patients sharing with the Follower account, for the Settings picker.
    func loadPatients() async -> [LLUPatient] {
        guard let llu = source as? LibreLinkUpSource else { return [] }
        return (try? await llu.patients()) ?? []
    }

    private func didWake() {
        tracker.suppress(.signalLoss, until: Date().addingTimeInterval(wakeGrace))
        restartPolling()
    }

    // MARK: Alerts

    private func evaluateAlerts(now: Date) {
        // Nothing to watch while signed out: no Signal Loss for an intentionally empty Source.
        guard hasCredentials || isDemo else {
            tracker = AlertTracker()
            return
        }
        let conditions = AlertEvaluator.evaluate(
            latest: latest, now: now, thresholds: config.thresholds,
            staleAfter: config.display.staleAfter, alerts: config.alerts)
        for kind in tracker.update(conditions, now: now, settings: config.alerts) {
            let event = AlertEvent(kind: kind, reading: latest, delta: delta, unit: unit, firedAt: now)
            let value = latest.map { $0.glucose.formatted(in: unit) } ?? "-"
            let actions = (config.alerts[kind]?.actions ?? []).joined(separator: ", ")
            if config.debugLogging {
                log.notice("Alert \(kind.rawValue, privacy: .public) fired at \(value, privacy: .public) → \(actions, privacy: .public)")
            } else {
                log.notice("Alert \(kind.rawValue, privacy: .public) fired at \(value, privacy: .private) → \(actions, privacy: .public)")
            }
            for name in config.alerts[kind]?.actions ?? [] {
                Task {
                    do { try await run(action: name, event) } catch {
                        // Error text can contain the webhook URL (which may embed a token) or a server reply.
                        let detail = String(describing: error)
                        if self.config.debugLogging {
                            self.log.error("Action \(name, privacy: .public) failed: \(detail, privacy: .public)")
                        } else {
                            self.log.error("Action \(name, privacy: .public) failed: \(detail, privacy: .private)")
                        }
                    }
                }
            }
        }
    }

    private func run(action name: String, _ event: AlertEvent) async throws {
        guard let action = config.actions[name] else { throw ActionTestError.unknownAction(name) }
        try await performer(for: action).perform(event)
    }

    /// A made-up event for a test send: the latest Reading, marked as a test.
    private func testEvent(_ kind: AlertKind) -> AlertEvent {
        AlertEvent(kind: kind, reading: latest, delta: delta, unit: unit, firedAt: Date(), isTest: true)
    }

    /// Runs every Action of `kind` once, as a test. Returns one result per Action, in order.
    func sendTest(_ kind: AlertKind) async -> [(action: String, error: String?)] {
        let event = testEvent(kind)
        var results: [(String, String?)] = []
        for name in config.alerts[kind]?.actions ?? [] {
            results.append((name, await testError(action: name, event)))
        }
        return results
    }

    /// Runs one Action once as a test (as an Urgent Low). nil = sent.
    func sendTest(action name: String) async -> String? {
        await testError(action: name, testEvent(.urgentLow))
    }

    private func testError(action name: String, _ event: AlertEvent) async -> String? {
        do { try await run(action: name, event); return nil } catch { return String(describing: error) }
    }

    // MARK: Action secrets (Keychain)

    func hasSecret(_ name: String) -> Bool {
        ((try? secrets.secret(named: name)) ?? nil)?.isEmpty == false
    }

    func setSecret(_ value: String?, named name: String) {
        do { try secrets.setSecret(value?.isEmpty == true ? nil : value, named: name) } catch {
            log.error("Keychain write for \(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func performer(for action: ActionConfig) -> any ActionPerformer {
        switch action {
        case .sound(let c): SoundPerformer(config: c)
        case .webhook(let c): WebhookPerformer(config: c, secrets: secrets)
        case .telegram(let c): TelegramPerformer(config: c, secrets: secrets)
        case .ntfy(let c): NtfyPerformer(config: c, secrets: secrets)
        }
    }

    func snooze(minutes: Int) {
        tracker.snoozeAll(until: Date().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    // MARK: Derived display state

    var latest: Reading? { snapshot?.latest }
    var delta: Glucose? { snapshot.flatMap { Delta.compute($0.readings) } }
    var unit: GlucoseUnit { config.displayUnit(patientUnit: snapshot?.patientDefaults?.unit) }

    func isStale(at now: Date = Date()) -> Bool {
        latest?.isStale(now: now, threshold: config.display.staleAfter) ?? true
    }

    var menuBarText: String {
        guard let r = latest else { return "---" }
        var parts = [r.glucose.formatted(in: unit)]
        if config.display.showTrend, let arrow = r.trend?.arrow { parts.append(arrow) }
        if config.display.showDelta, let d = delta { parts.append(Delta.formatted(d, in: unit)) }
        if config.display.showAge { parts.append(Self.age(of: r)) }
        return parts.joined(separator: " ")
    }

    /// nil = normal menu bar text colour. Stale grey wins over range colours.
    var menuBarColor: NSColor? {
        guard let r = latest else { return nil }
        if isStale() { return .systemGray }
        if r.glucose < config.thresholds.urgentLow { return .systemRed }
        if r.glucose < config.thresholds.low || r.glucose > config.thresholds.high { return .systemOrange }
        return nil
    }

    static func age(of reading: Reading, now: Date = Date()) -> String {
        "\(max(0, Int(now.timeIntervalSince(reading.timestamp) / 60)))m"
    }

    // MARK: Config

    func saveConfig() {
        do { try configStore.save(config) } catch {
            status = .error("Could not save config: \(error.localizedDescription)")
        }
    }

    /// Applies config.json from disk. Called automatically when the file changes.
    /// No-op when the content equals what's in memory (e.g. our own saves).
    func reloadConfig() {
        let new: GlucoBarConfig
        do {
            new = try configStore.loadOrCreate()
        } catch {
            configError = "config.json not applied: \(Self.describe(error))"
            log.error("\(self.configError ?? "", privacy: .public)")
            return
        }
        configError = nil
        guard new != config else { return }

        let needsRestart = new.libreLinkUp != config.libreLinkUp || new.polling != config.polling
        if new.launchAtLogin != config.launchAtLogin { LaunchAtLogin.apply(new.launchAtLogin) }
        config = new
        hasCredentials = config.libreLinkUp.email != nil
            && (try? secrets.secret(named: config.libreLinkUp.passwordSecret)) != nil
        log.notice("Reloaded config.json\(needsRestart ? " (restarting polling)" : "", privacy: .public)")
        if needsRestart { restartPolling() }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let c):
            let underlying = (c.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return underlying ?? c.debugDescription
        case DecodingError.typeMismatch(_, let c), DecodingError.valueNotFound(_, let c):
            return "\(c.codingPath.map(\.stringValue).joined(separator: ".")): \(c.debugDescription)"
        case DecodingError.keyNotFound(let key, let c):
            return "\((c.codingPath + [key]).map(\.stringValue).joined(separator: ".")) is missing"
        default:
            return error.localizedDescription
        }
    }

    /// Stores the Follower account credentials and restarts polling.
    func signIn(email: String, password: String) {
        if email != config.libreLinkUp.email { config.libreLinkUp.patientId = nil }
        config.libreLinkUp.email = email
        saveConfig()
        do {
            try secrets.setSecret(password, named: config.libreLinkUp.passwordSecret)
            try secrets.setSecret(nil, named: config.libreLinkUp.tokenSecret) // force a fresh login
        } catch {
            status = .error("Keychain: \(error.localizedDescription)")
            return
        }
        hasCredentials = true
        status = .starting
        snapshot = nil
        restartPolling()
    }

    /// Forgets the password and token; keeps the email to make signing back in easier.
    func signOut() {
        try? secrets.setSecret(nil, named: config.libreLinkUp.passwordSecret)
        try? secrets.setSecret(nil, named: config.libreLinkUp.tokenSecret)
        hasCredentials = false
        snapshot = nil
        tracker = AlertTracker()
        restartPolling()
    }
}

enum ActionTestError: Error, CustomStringConvertible {
    case unknownAction(String)
    var description: String {
        switch self { case .unknownAction(let name): "no Action named \(name)" }
    }
}
