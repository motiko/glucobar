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
    private(set) var tracker = AlertTracker()
    /// Launch with `-demo` to show fake Readings. Never on by default.
    let isDemo = CommandLine.arguments.contains("-demo")

    let configStore = ConfigStore()
    let secrets = KeychainSecretStore()
    private var pollTask: Task<Void, Never>?
    private var source: any GlucoseSource = DemoGlucoseSource()
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
        SoundPerformer.requestAuthorization()
        LaunchAtLogin.apply(config.launchAtLogin)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        }
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
            snapshot = snap
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
        let conditions = AlertEvaluator.evaluate(
            latest: latest, now: now, thresholds: config.thresholds,
            staleAfter: config.display.staleAfter, alerts: config.alerts)
        for kind in tracker.update(conditions, now: now, settings: config.alerts) {
            let event = AlertEvent(kind: kind, reading: latest, delta: delta, unit: unit, firedAt: now)
            for name in config.alerts[kind]?.actions ?? [] {
                guard let action = config.actions[name] else {
                    log.error("Alert \(kind.rawValue) refers to unknown action \(name)")
                    continue
                }
                let performer = performer(for: action)
                Task {
                    do { try await performer.perform(event) } catch {
                        self.log.error("Action \(name) failed: \(String(describing: error))")
                    }
                }
            }
        }
    }

    private func performer(for action: ActionConfig) -> any ActionPerformer {
        switch action {
        case .sound(let c): SoundPerformer(config: c)
        case .webhook(let c): WebhookPerformer(config: c, secrets: secrets)
        case .telegram(let c): TelegramPerformer(config: c, secrets: secrets)
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

    func reloadConfig() {
        do {
            config = try configStore.loadOrCreate()
            restartPolling()
        } catch {
            status = .error("Config unreadable: \(error.localizedDescription)")
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
        restartPolling()
    }
}
