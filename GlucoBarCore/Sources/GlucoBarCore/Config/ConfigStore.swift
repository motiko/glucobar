import Foundation

/// Loads and saves the JSON config file. Both the Settings window and hand edits go through this file.
public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL = ConfigStore.defaultURL) { self.url = url }

    /// `$XDG_CONFIG_HOME/glucobar/config.json`, falling back to `~/.config/glucobar/config.json`.
    public static var defaultURL: URL {
        let base: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        }
        return base.appendingPathComponent("glucobar", isDirectory: true).appendingPathComponent("config.json")
    }

    /// Returns the stored config, writing the defaults first if the file doesn't exist.
    public func loadOrCreate() throws -> GlucoBarConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let config = GlucoBarConfig()
            try save(config)
            return config
        }
        return try JSONDecoder().decode(GlucoBarConfig.self, from: Data(contentsOf: url))
    }

    public func save(_ config: GlucoBarConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
