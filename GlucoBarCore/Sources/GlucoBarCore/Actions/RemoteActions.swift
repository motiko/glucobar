import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Why a remote Action could not be delivered.
public enum ActionError: Error, Equatable, CustomStringConvertible {
    case invalidURL(String)
    case missingSecret(String)
    case httpStatus(Int, String)

    public var description: String {
        switch self {
        case .invalidURL(let url): "invalid URL: \(url)"
        case .missingSecret(let name): "no Keychain secret named \(name)"
        case .httpStatus(let code, let body): "HTTP \(code): \(body.prefix(200))"
        }
    }
}

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
        state = event.isTest ? "test" : "firing"
        unit = event.unit
        value_mgdl = event.reading?.glucose.mgPerDL
        value = event.reading?.glucose.value(in: event.unit)
        trend = event.reading?.trend
        delta = event.delta?.value(in: event.unit)
        timestamp = event.reading?.timestamp
    }
}

/// Human-readable Alert text shared by the message-based Actions.
public enum AlertMessage {
    /// e.g. "Urgent Low", or "Urgent Low (test)".
    public static func title(for event: AlertEvent) -> String {
        event.kind.displayName + (event.isTest ? " (test)" : "")
    }

    /// e.g. "52 mg/dL ↘ (−8) at 03:12", or "last reading 52 mg/dL at 03:12" for Signal Loss.
    public static func body(for event: AlertEvent, timeZone: TimeZone = .current) -> String {
        guard let r = event.reading else { return "no readings" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = timeZone
        let value = "\(r.glucose.formatted(in: event.unit)) \(event.unit.rawValue)"
        let time = fmt.string(from: r.timestamp)
        if event.kind == .signalLoss { return "last reading \(value) at \(time)" }
        var parts = [value]
        if let arrow = r.trend?.arrow { parts.append(arrow) }
        if let d = event.delta { parts.append("(\(Delta.formatted(d, in: event.unit)))") }
        parts.append("at \(time)")
        return parts.joined(separator: " ")
    }
}

/// The fixed Telegram message text, e.g. "🚨 Urgent Low: 52 mg/dL ↘ (−8) at 03:12".
public enum TelegramMessage {
    public static func text(for event: AlertEvent, timeZone: TimeZone = .current) -> String {
        let icon = event.kind == .urgentLow ? "🚨" : "⚠️"
        return "\(icon) \(AlertMessage.title(for: event)): \(AlertMessage.body(for: event, timeZone: timeZone))"
    }
}

/// The JSON body ntfy accepts at its root URL (https://docs.ntfy.sh/publish/#publish-as-json).
/// JSON rather than headers so titles and arrows survive as UTF-8.
public struct NtfyMessage: Codable, Sendable, Equatable {
    public var topic: String
    public var title: String
    public var message: String
    /// 1 (min) … 5 (max). 5 is "urgent": it can break through the phone's Do Not Disturb.
    public var priority: Int
    public var tags: [String]

    public init(topic: String, event: AlertEvent, timeZone: TimeZone = .current) {
        self.topic = topic
        title = AlertMessage.title(for: event)
        message = AlertMessage.body(for: event, timeZone: timeZone)
        switch event.kind {
        case .urgentLow: priority = 5; tags = ["rotating_light"]
        case .low: priority = 4; tags = ["arrow_down"]
        case .high: priority = 4; tags = ["arrow_up"]
        case .signalLoss: priority = 3; tags = ["warning"]
        }
    }
}

private func post(_ body: Data, to url: URL, authorization: String?, via transport: any HTTPTransport) async throws {
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("GlucoBar", forHTTPHeaderField: "User-Agent")
    if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
    request.httpBody = body
    let (data, response) = try await transport.send(request)
    guard (200..<300).contains(response.statusCode) else {
        throw ActionError.httpStatus(response.statusCode, String(decoding: data, as: UTF8.self))
    }
}

private func secret(_ name: String?, in secrets: any SecretStore) throws -> String? {
    guard let name else { return nil }
    guard let value = try secrets.secret(named: name), !value.isEmpty else { throw ActionError.missingSecret(name) }
    return value
}

private func httpURL(_ string: String) throws -> URL {
    guard let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased()), url.host != nil else {
        throw ActionError.invalidURL(string)
    }
    return url
}

/// POSTs `WebhookPayload` as JSON (ISO-8601 dates) to the configured URL.
public struct WebhookPerformer: ActionPerformer {
    public var config: WebhookActionConfig
    public var secrets: any SecretStore
    public var transport: any HTTPTransport

    public init(config: WebhookActionConfig, secrets: any SecretStore, transport: any HTTPTransport = URLSession.shared) {
        self.config = config
        self.secrets = secrets
        self.transport = transport
    }

    public func perform(_ event: AlertEvent) async throws {
        let url = try httpURL(config.url)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        try await post(try encoder.encode(WebhookPayload(event)), to: url,
                       authorization: try secret(config.authorizationSecret, in: secrets), via: transport)
    }
}

/// Publishes an `NtfyMessage` to the configured ntfy server.
public struct NtfyPerformer: ActionPerformer {
    public var config: NtfyActionConfig
    public var secrets: any SecretStore
    public var transport: any HTTPTransport

    public init(config: NtfyActionConfig, secrets: any SecretStore, transport: any HTTPTransport = URLSession.shared) {
        self.config = config
        self.secrets = secrets
        self.transport = transport
    }

    public func perform(_ event: AlertEvent) async throws {
        let url = try httpURL(config.server)
        let token = try secret(config.tokenSecret, in: secrets)
        let body = try JSONEncoder().encode(NtfyMessage(topic: config.topic, event: event))
        try await post(body, to: url, authorization: token.map { "Bearer \($0)" }, via: transport)
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
