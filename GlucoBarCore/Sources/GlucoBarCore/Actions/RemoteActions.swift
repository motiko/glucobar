import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The fixed JSON body a Webhook Action posts.
public struct WebhookPayload: Codable, Sendable, Equatable {
    public var alert: AlertKind
    public var state = "firing"
    public var value_mgdl: Double?
    public var value: Double?
    public var unit: GlucoseUnit
    public var trend: Trend?
    public var delta: Double?
    public var timestamp: Date?

    public init(_ event: AlertEvent) {
        alert = event.kind
        unit = event.unit
        value_mgdl = event.reading?.glucose.mgPerDL
        value = event.reading?.glucose.value(in: event.unit)
        trend = event.reading?.trend
        delta = event.delta?.value(in: event.unit)
        timestamp = event.reading?.timestamp
    }
}

/// The fixed Telegram message text, e.g. "⚠️ Urgent Low: 52 mg/dL ↘ (−8) at 03:12".
public enum TelegramMessage {
    public static func text(for event: AlertEvent, timeZone: TimeZone = .current) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = timeZone
        let icon = event.kind == .urgentLow ? "🚨" : "⚠️"

        guard let r = event.reading else { return "\(icon) \(event.kind.displayName): no readings" }
        let value = "\(r.glucose.formatted(in: event.unit)) \(event.unit.rawValue)"
        let time = fmt.string(from: r.timestamp)
        if event.kind == .signalLoss {
            return "\(icon) Signal Loss: last reading \(value) at \(time)"
        }
        var parts = ["\(icon) \(event.kind.displayName): \(value)"]
        if let arrow = r.trend?.arrow { parts.append(arrow) }
        if let d = event.delta { parts.append("(\(Delta.formatted(d, in: event.unit)))") }
        parts.append("at \(time)")
        return parts.joined(separator: " ")
    }
}

public struct WebhookPerformer: ActionPerformer {
    public var config: WebhookActionConfig
    public var secrets: any SecretStore

    public init(config: WebhookActionConfig, secrets: any SecretStore) {
        self.config = config
        self.secrets = secrets
    }

    public func perform(_ event: AlertEvent) async throws {
        // TODO: POST WebhookPayload(event) as JSON (ISO-8601 dates) to config.url.
        throw GlucoseSourceError.notImplemented
    }
}

public struct TelegramPerformer: ActionPerformer {
    public var config: TelegramActionConfig
    public var secrets: any SecretStore

    public init(config: TelegramActionConfig, secrets: any SecretStore) {
        self.config = config
        self.secrets = secrets
    }

    public func perform(_ event: AlertEvent) async throws {
        // TODO: POST https://api.telegram.org/bot<token>/sendMessage {chat_id, text}.
        throw GlucoseSourceError.notImplemented
    }

    // TODO: chat-id discovery: GET /bot<token>/getUpdates and list `message.chat` entries.
}
