import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Something GlucoBar does when an Alert fires. Stored in config with a `type` discriminator.
public enum ActionConfig: Codable, Sendable, Equatable {
    case sound(SoundActionConfig)
    case webhook(WebhookActionConfig)
    case telegram(TelegramActionConfig)

    private enum CodingKeys: String, CodingKey { case type }
    private enum Kind: String, Codable { case sound, webhook, telegram }

    public init(from decoder: Decoder) throws {
        let kind = try decoder.container(keyedBy: CodingKeys.self).decode(Kind.self, forKey: .type)
        switch kind {
        case .sound: self = .sound(try SoundActionConfig(from: decoder))
        case .webhook: self = .webhook(try WebhookActionConfig(from: decoder))
        case .telegram: self = .telegram(try TelegramActionConfig(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sound(let a): try c.encode(Kind.sound, forKey: .type); try a.encode(to: encoder)
        case .webhook(let a): try c.encode(Kind.webhook, forKey: .type); try a.encode(to: encoder)
        case .telegram(let a): try c.encode(Kind.telegram, forKey: .type); try a.encode(to: encoder)
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

/// One firing of an Alert, handed to every Action in its list.
public struct AlertEvent: Sendable, Equatable {
    public var kind: AlertKind
    /// The latest Reading (for Signal Loss: the last known one, if any).
    public var reading: Reading?
    public var delta: Glucose?
    public var unit: GlucoseUnit
    public var firedAt: Date

    public init(kind: AlertKind, reading: Reading?, delta: Glucose?, unit: GlucoseUnit, firedAt: Date) {
        self.kind = kind
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
