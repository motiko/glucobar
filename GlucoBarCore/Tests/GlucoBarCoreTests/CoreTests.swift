import Foundation
import Testing
@testable import GlucoBarCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func reading(_ mg: Double, minutesAgo: Double = 0, trend: Trend? = .flat) -> Reading {
    Reading(glucose: Glucose(mgPerDL: mg), timestamp: t0.addingTimeInterval(-minutesAgo * 60), trend: trend)
}

@Suite struct GlucoseTests {
    @Test func unitConversionAndFormatting() {
        let g = Glucose(mgPerDL: 124)
        #expect(g.formatted(in: .mgPerDL) == "124")
        #expect(g.formatted(in: .mmolPerL) == "6.9")
        #expect(abs(Glucose(mmolPerL: 5.5).mgPerDL - 99.1) < 0.1)
    }

    @Test func staleness() {
        let r = reading(100, minutesAgo: 16)
        #expect(r.isStale(now: t0, threshold: 15 * 60))
        #expect(!reading(100, minutesAgo: 14).isStale(now: t0, threshold: 15 * 60))
    }
}

@Suite struct DeltaTests {
    @Test func overFiveMinutes() {
        let rs = (0...10).map { reading(100 + Double(10 - $0), minutesAgo: Double($0)) }
        #expect(Delta.compute(rs)?.mgPerDL == 5)
    }

    @Test func nilWithoutComparableReading() {
        #expect(Delta.compute([reading(100)]) == nil)
        #expect(Delta.compute([reading(100), reading(90, minutesAgo: 30)]) == nil)
    }

    @Test func formatting() {
        #expect(Delta.formatted(Glucose(mgPerDL: 6), in: .mgPerDL) == "+6")
        #expect(Delta.formatted(Glucose(mgPerDL: -8), in: .mgPerDL) == "−8")
        #expect(Delta.formatted(Glucose(mgPerDL: 0.2), in: .mgPerDL) == "±0")
    }
}

@Suite struct AlertEvaluatorTests {
    let th = Thresholds()
    let ungated: [AlertKind: AlertSettings] = AlertSettings.defaults.mapValues {
        var s = $0; s.onlyWithFastTrend = false; return s
    }

    func eval(_ r: Reading?, _ alerts: [AlertKind: AlertSettings]) -> AlertConditions {
        AlertEvaluator.evaluate(latest: r, now: t0, thresholds: th, staleAfter: 15 * 60, alerts: alerts)
    }

    @Test func ranges() {
        #expect(eval(reading(100), ungated) == AlertConditions(active: []))
        #expect(eval(reading(65), ungated) == AlertConditions(active: [.low]))
        #expect(eval(reading(50), ungated) == AlertConditions(active: [.urgentLow]))
        #expect(eval(reading(200), ungated) == AlertConditions(active: [.high]))
    }

    @Test func fastTrendAloneRaisesNothing() {
        #expect(eval(reading(100, trend: .risingFast), ungated).active.isEmpty)
        #expect(eval(reading(100, trend: .fallingFast), ungated).active.isEmpty)
    }

    @Test func lowIsGatedOnFallingFastByDefault() {
        let d = AlertSettings.defaults
        #expect(eval(reading(65, trend: .flat), d) == AlertConditions(active: [.low], blocked: [.low]))
        #expect(eval(reading(65, trend: .falling), d) == AlertConditions(active: [.low], blocked: [.low]))
        #expect(eval(reading(65, trend: .fallingFast), d) == AlertConditions(active: [.low]))
    }

    @Test func highGateUsesRisingFast() {
        var s = ungated
        s[.high]?.onlyWithFastTrend = true
        #expect(eval(reading(200, trend: .rising), s).blocked == [.high])
        #expect(eval(reading(200, trend: .risingFast), s).blocked.isEmpty)
        #expect(eval(reading(200, trend: .flat), AlertSettings.defaults).blocked.isEmpty) // High ungated by default
    }

    @Test func urgentLowIsNeverGated() {
        var s = AlertSettings.defaults
        s[.urgentLow]?.onlyWithFastTrend = true
        #expect(eval(reading(50, trend: .flat), s) == AlertConditions(active: [.urgentLow]))
    }

    @Test func staleOrMissingIsOnlySignalLoss() {
        #expect(eval(nil, ungated) == AlertConditions(active: [.signalLoss]))
        #expect(eval(reading(40, minutesAgo: 20), ungated) == AlertConditions(active: [.signalLoss]))
    }

    @Test func seedingHappensOnce() {
        var t = Thresholds()
        t.seedIfNeeded(from: PatientDefaults(low: Glucose(mgPerDL: 80)))
        #expect(t.low.mgPerDL == 80)
        t.low = Glucose(mgPerDL: 75)
        t.seedIfNeeded(from: PatientDefaults(low: Glucose(mgPerDL: 80)))
        #expect(t.low.mgPerDL == 75)
    }
}

@Suite struct AlertTrackerTests {
    let settings = AlertSettings.defaults // low repeats every 15 min, Signal Loss every 60
    let low = AlertConditions(active: [.low])
    let lowBlocked = AlertConditions(active: [.low], blocked: [.low])
    let none = AlertConditions(active: [])

    @Test func firesThenRepeatsThenClears() {
        var tr = AlertTracker()
        #expect(tr.update(low, now: t0, settings: settings) == [.low])
        #expect(tr.update(low, now: t0 + 10 * 60, settings: settings) == [])
        #expect(tr.update(low, now: t0 + 15 * 60, settings: settings) == [.low])
        #expect(tr.update(none, now: t0 + 16 * 60, settings: settings) == [])
        #expect(tr.firing.isEmpty)
        #expect(tr.update(low, now: t0 + 17 * 60, settings: settings) == [.low])
    }

    @Test func gateHoldsFiringButKeepsTheEpisode() {
        var tr = AlertTracker()
        // Hovering below Low with a flat trend: no alerts.
        #expect(tr.update(lowBlocked, now: t0, settings: settings) == [])
        #expect(tr.update(lowBlocked, now: t0 + 30 * 60, settings: settings) == [])
        #expect(tr.firing.isEmpty)
        // Starts falling fast: fires.
        #expect(tr.update(low, now: t0 + 31 * 60, settings: settings) == [.low])
        // Trend flickers falling ↔ falling fast: no re-alert before the repeat interval.
        #expect(tr.update(lowBlocked, now: t0 + 32 * 60, settings: settings) == [])
        #expect(tr.update(low, now: t0 + 33 * 60, settings: settings) == [])
        #expect(tr.update(low, now: t0 + 46 * 60, settings: settings) == [.low])
    }

    @Test func snoozeSkipsRepeatsUntilItEnds() {
        var tr = AlertTracker()
        _ = tr.update(low, now: t0, settings: settings)
        tr.snoozeAll(until: t0 + 30 * 60)
        #expect(tr.update(low, now: t0 + 20 * 60, settings: settings) == [])
        #expect(tr.update(low, now: t0 + 31 * 60, settings: settings) == [.low])
    }

    @Test func signalLossRepeatsHourlyAndRespectsWakeSuppression() {
        var tr = AlertTracker()
        let lost = AlertConditions(active: [.signalLoss])
        tr.suppress(.signalLoss, until: t0 + 120)
        #expect(tr.update(lost, now: t0, settings: settings) == [])
        #expect(tr.update(lost, now: t0 + 121, settings: settings) == [.signalLoss])
        #expect(tr.update(lost, now: t0 + 121 + 59 * 60, settings: settings) == [])
        #expect(tr.update(lost, now: t0 + 121 + 60 * 60, settings: settings) == [.signalLoss])
    }

    @Test func disabledAlertNeverFires() {
        var s = settings
        s[.high]?.enabled = false
        var tr = AlertTracker()
        #expect(tr.update(AlertConditions(active: [.high]), now: t0, settings: s) == [])
    }
}

@Suite struct ConfigTests {
    @Test func roundTripsThroughFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(url: dir.appendingPathComponent("config.json"))

        var config = try store.loadOrCreate()
        #expect(config == GlucoBarConfig())
        config.display.showTrend = true
        config.actions["tg"] = .telegram(TelegramActionConfig(chatId: "42"))
        config.alerts[.urgentLow]?.actions.append("tg")
        try store.save(config)
        #expect(try store.loadOrCreate() == config)
    }

    @Test func savesThroughSymlinkWithoutReplacingIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let synced = dir.appendingPathComponent("cloud/GlucoBar/config.json")
        let link = dir.appendingPathComponent("local/config.json")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: synced) // dangling at first

        let store = ConfigStore(url: link)
        #expect(store.fileURL.path == synced.standardizedFileURL.path)
        var config = try store.loadOrCreate() // creates the target, not a file at the link
        config.debugLogging = true
        try store.save(config)

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == synced.path)
        #expect(try JSONDecoder().decode(GlucoBarConfig.self, from: Data(contentsOf: synced)).debugLogging)
    }

    @Test func partialFileFallsBackToDefaults() throws {
        let json = #"{"display": {"showDelta": true}, "polling": {"intervalSeconds": 10}}"#
        let config = try JSONDecoder().decode(GlucoBarConfig.self, from: Data(json.utf8))
        #expect(config.display.showDelta)
        #expect(config.display.staleAfterMinutes == 15)
        #expect(config.polling.interval == 60) // clamped
        #expect(!config.debugLogging)
        #expect(config.alerts == AlertSettings.defaults)
    }

    @Test func retiredAlertKindsInOldFilesAreIgnored() throws {
        let json = #"{"alerts": {"fastRise": {"repeatMinutes": 15}, "low": {"repeatMinutes": 10, "actions": ["x"]}}}"#
        let config = try JSONDecoder().decode(GlucoBarConfig.self, from: Data(json.utf8))
        #expect(config.alerts.keys.sorted { $0.rawValue < $1.rawValue } == [.low])
        #expect(config.alerts[.low]?.onlyWithFastTrend == false) // absent in file → off
    }

    @Test func alertsEncodeAsObjectKeyedByKind() throws {
        let data = try JSONEncoder().encode(GlucoBarConfig())
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((obj?["alerts"] as? [String: Any])?["urgentLow"] != nil)
    }
}

@Suite struct RemoteActionTests {
    @Test func telegramText() {
        let event = AlertEvent(kind: .urgentLow, reading: reading(52, trend: .falling),
                               delta: Glucose(mgPerDL: -8), unit: .mgPerDL, firedAt: t0)
        let text = TelegramMessage.text(for: event, timeZone: TimeZone(identifier: "UTC")!)
        #expect(text == "🚨 Urgent Low: 52 mg/dL ↘ (−8) at 08:00")
    }

    @Test func ntfyPublishesJSONToServerRoot() async throws {
        let t = FakeTransport()
        t.on("POST ntfy.example.com", (200, "{}", [:]))
        let secrets = MemorySecrets()
        try secrets.setSecret("tk_abc", named: "ntfy.token")
        let config = NtfyActionConfig(server: "https://ntfy.example.com", topic: "gb-x7", tokenSecret: "ntfy.token")
        let event = AlertEvent(kind: .urgentLow, reading: reading(52, trend: .falling),
                               delta: Glucose(mgPerDL: -8), unit: .mgPerDL, firedAt: t0)

        try await NtfyPerformer(config: config, secrets: secrets, transport: t).perform(event)

        let request = try #require(t.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tk_abc")
        let sent = try JSONDecoder().decode(NtfyMessage.self, from: try #require(request.httpBody))
        #expect(sent.topic == "gb-x7")
        #expect(sent.title == "Urgent Low")
        #expect(sent.message.hasPrefix("52 mg/dL ↘ (−8) at "))
        #expect(sent.priority == 5)
    }

    @Test func testSendsAreLabelled() {
        let event = AlertEvent(kind: .high, reading: reading(250), delta: nil, unit: .mgPerDL, firedAt: t0, isTest: true)
        #expect(NtfyMessage(topic: "t", event: event).title == "High (test)")
        #expect(WebhookPayload(event).state == "test")
        #expect(WebhookPayload(AlertEvent(kind: .high, reading: nil, delta: nil, unit: .mgPerDL, firedAt: t0)).state == "firing")
    }

    @Test func ntfyErrorsSurface() async throws {
        let t = FakeTransport()
        t.on("POST ntfy.sh", (429, #"{"error":"limit reached"}"#, [:]))
        let event = AlertEvent(kind: .signalLoss, reading: nil, delta: nil, unit: .mgPerDL, firedAt: t0)
        let ntfy = NtfyPerformer(config: NtfyActionConfig(topic: "t"), secrets: MemorySecrets(), transport: t)
        await #expect(throws: ActionError.httpStatus(429, #"{"error":"limit reached"}"#)) { try await ntfy.perform(event) }
        #expect(t.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)

        let missing = NtfyPerformer(config: NtfyActionConfig(topic: "t", tokenSecret: "nope"), secrets: MemorySecrets(), transport: t)
        await #expect(throws: ActionError.missingSecret("nope")) { try await missing.perform(event) }
    }

    @Test func ntfyConfigDefaultsServer() throws {
        let json = #"{"actions": {"phone": {"type": "ntfy", "topic": "gb-x7"}}}"#
        let config = try JSONDecoder().decode(GlucoBarConfig.self, from: Data(json.utf8))
        #expect(config.actions["phone"] == .ntfy(NtfyActionConfig(server: "https://ntfy.sh", topic: "gb-x7")))
    }

    @Test func webhookPostsFixedPayload() async throws {
        let t = FakeTransport()
        t.on("POST hooks.example.com/glucose", (204, "", [:]))
        let event = AlertEvent(kind: .high, reading: reading(250, trend: .risingFast),
                               delta: Glucose(mgPerDL: 12), unit: .mgPerDL, firedAt: t0)
        try await WebhookPerformer(config: WebhookActionConfig(url: "https://hooks.example.com/glucose"),
                                   secrets: MemorySecrets(), transport: t).perform(event)
        let body = try JSONSerialization.jsonObject(with: try #require(t.requests.first?.httpBody)) as? [String: Any]
        #expect(body?["alert"] as? String == "high")
        #expect(body?["value_mgdl"] as? Double == 250)
        #expect(body?["timestamp"] as? String == "2027-01-15T08:00:00Z")
    }

    @Test func lluTrendMapping() {
        #expect(LibreLinkUpSource.trend(fromArrow: 1) == .fallingFast)
        #expect(LibreLinkUpSource.trend(fromArrow: 5) == .risingFast)
        #expect(LibreLinkUpSource.trend(fromArrow: 0) == nil)
    }
}

@Suite struct SettingsSyncTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var local: URL { dir.appendingPathComponent("mac/.config/glucobar/config.json") }
    var cloud: URL { dir.appendingPathComponent("iCloud") }

    private func write(_ config: GlucoBarConfig, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(config).write(to: url)
    }

    private func read(_ url: URL) throws -> GlucoBarConfig {
        try JSONDecoder().decode(GlucoBarConfig.self, from: Data(contentsOf: url))
    }

    @Test func firstMacMovesItsSettingsToTheCloudAndBack() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        var mine = GlucoBarConfig(); mine.polling.intervalSeconds = 120
        try write(mine, to: local)
        let sync = SettingsSync(localURL: local, cloudRoot: cloud)

        #expect(!sync.cloudCopyExists)
        try sync.enable(useCloudCopy: false)
        #expect(sync.isEnabled)
        #expect(try read(sync.cloudURL) == mine)
        #expect(try ConfigStore(url: local).loadOrCreate() == mine) // read through the symlink

        try sync.disable()
        #expect(!sync.isEnabled)
        #expect(try read(local) == mine) // plain file again
        #expect(FileManager.default.fileExists(atPath: sync.cloudURL.path)) // other Macs keep theirs
    }

    @Test func secondMacCanAdoptTheCloudSettings() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let sync = SettingsSync(localURL: local, cloudRoot: cloud)
        var shared = GlucoBarConfig(); shared.debugLogging = true
        try write(shared, to: sync.cloudURL)
        try write(GlucoBarConfig(), to: local)

        #expect(sync.cloudCopyExists)
        try sync.enable(useCloudCopy: true)
        #expect(try ConfigStore(url: local).loadOrCreate() == shared)
        let backup = local.deletingLastPathComponent().appendingPathComponent("config.before-sync.json")
        #expect(try read(backup) == GlucoBarConfig())
    }

    @Test func secondMacCanOverwriteTheCloudSettings() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let sync = SettingsSync(localURL: local, cloudRoot: cloud)
        try write(GlucoBarConfig(), to: sync.cloudURL)
        var mine = GlucoBarConfig(); mine.display.showAge = true
        try write(mine, to: local)

        try sync.enable(useCloudCopy: false)
        #expect(try read(sync.cloudURL) == mine)
    }
}
