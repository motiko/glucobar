import AppKit
import GlucoBarCore
import UserNotifications

/// Sound Action: a macOS banner plus the Notification or Urgent sound.
struct SoundPerformer: ActionPerformer {
    let config: SoundActionConfig

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func perform(_ event: AlertEvent) async throws {
        let content = UNMutableNotificationContent()
        content.title = event.kind.displayName
        if let r = event.reading {
            content.body = "\(r.glucose.formatted(in: event.unit)) \(event.unit.rawValue) \(r.trend?.arrow ?? "")"
        }
        if config.bypassFocusAndMute {
            // Banners respect Focus; the sound is played directly so Focus can't silence it.
            // TODO: also override system mute / low volume for the Urgent sound.
            content.interruptionLevel = .timeSensitive
            await MainActor.run { playDirectly() }
        } else {
            content.sound = .default
        }
        let request = UNNotificationRequest(identifier: "\(event.kind.rawValue)-\(event.firedAt.timeIntervalSince1970)",
                                            content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }

    @MainActor private func playDirectly() {
        switch config.sound {
        case .urgent: AlarmTone.play()
        case .notification: _ = NSSound(named: "Glass")?.play()
        }
    }
}
