import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Something GlucoBar does when an Alert fires. Stored in config with a `type` discriminator.
public enum ActionConfig: Codable, Sendable, Equatable {
    case sound(SoundActionConfig)
    case webhook(WebhookActionConfig)
    case telegram(TelegramActionConfig)
    case ntfy(NtfyActionConfig)

    private enum CodingKeys: String, CodingKey { case type }
    private enum Kind: String, Codable { case sound, webhook, telegram, ntfy }

    public init(from decoder: Decoder) throws {
        let kind = try decoder.container(keyedBy: CodingKeys.self).decode(Kind.self, forKey: .type)
        switch kind {
        case .sound: self = .sound(try SoundActionConfig(from: decoder))
        case .webhook: self = .webhook(try WebhookActionConfig(from: decoder))
        case .telegram: self = .telegram(try TelegramActionConfig(from: decoder))
        case .ntfy: self = .ntfy(try NtfyActionConfig(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sound(let a): try c.encode(Kind.sound, forKey: .type); try a.encode(to: encoder)
        case .webhook(let a): try c.encode(Kind.webhook, forKey: .type); try a.encode(to: encoder)
        case .telegram(let a): try c.encode(Kind.telegram, forKey: .type); try a.encode(to: encoder)
        case .ntfy(let a): try c.encode(Kind.ntfy, forKey: .type); try a.encode(to: encoder)
        }
    }

    public static let defaults: [String: ActionConfig] = [
        "notificationSound": .sound(SoundActionConfig(sound: .notification, bypassFocusAndMute: false)),
        "urgentSound": .sound(SoundActionConfig(sound: .urgent, bypassFocusAndMute: true)),
    ]
}

public enum SoundKind: String, Codable, Sendable { case notification, urgent }

/// Plays the Notification or Urgent sound and shows a macOS banner. Performed by the Mac app only.
public struct SoundActionConfig: Codable, Sendable, Equatable {
    public var sound: SoundKind
    /// Play even when Focus / Do Not Disturb is on or output is muted.
    public var bypassFocusAndMute: Bool

    public init(sound: SoundKind, bypassFocusAndMute: Bool) {
        self.sound = sound
        self.bypassFocusAndMute = bypassFocusAndMute
    }
}

public struct WebhookActionConfig: Codable, Sendable, Equatable {
    public var url: String
    /// Optional SecretStore name whose value is sent as the `Authorization` header.
    public var authorizationSecret: String?

    public init(url: String, authorizationSecret: String? = nil) {
        self.url = url
        self.authorizationSecret = authorizationSecret
    }
}

public struct TelegramActionConfig: Codable, Sendable, Equatable {
    /// SecretStore name of the bot token.
    public var botTokenSecret: String
    /// Discovered via the bot's getUpdates in Settings.
    public var chatId: String?

    public init(botTokenSecret: String = "telegram.botToken", chatId: String? = nil) {
        self.botTokenSecret = botTokenSecret
        self.chatId = chatId
    }
}

/// A Webhook Action in ntfy's format: a push notification to every phone/desktop subscribed
/// to `topic` on `server` (https://ntfy.sh or a self-hosted one).
///
/// On the public server the topic name is the only protection: anyone who knows it can read the
/// Alerts, so pick an unguessable one, or use a protected topic with an access token.
public struct NtfyActionConfig: Codable, Sendable, Equatable {
    public var server: String
    public var topic: String
    /// Optional SecretStore name of an ntfy access token (`tk_…`) for protected topics.
    public var tokenSecret: String?

    public init(server: String = NtfyActionConfig.defaultServer, topic: String, tokenSecret: String? = nil) {
        self.server = server
        self.topic = topic
        self.tokenSecret = tokenSecret
    }

    public static let defaultServer = "https://ntfy.sh"

    private enum CodingKeys: String, CodingKey { case server, topic, tokenSecret }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        server = try c.decodeIfPresent(String.self, forKey: .server) ?? Self.defaultServer
        topic = try c.decode(String.self, forKey: .topic)
        tokenSecret = try c.decodeIfPresent(String.self, forKey: .tokenSecret)
    }
}

/// One firing of an Alert, handed to every Action in its list.
public struct AlertEvent: Sendable, Equatable {
    public var kind: AlertKind
    /// The latest Reading (for Signal Loss: the last known one, if any).
    public var reading: Reading?
    public var delta: Glucose?
    public var unit: GlucoseUnit
    public var firedAt: Date
    /// Sent by the user from Settings to check an Action works, not raised by a Reading.
    public var isTest: Bool

    public init(kind: AlertKind, reading: Reading?, delta: Glucose?, unit: GlucoseUnit, firedAt: Date,
                isTest: Bool = false) {
        self.kind = kind
        self.isTest = isTest
        self.reading = reading
        self.delta = delta
        self.unit = unit
        self.firedAt = firedAt
    }
}

/// Runs one kind of Action. Sound performers live in the Mac app; remote ones in Core.
public protocol ActionPerformer: Sendable {
    func perform(_ event: AlertEvent) async throws
}
