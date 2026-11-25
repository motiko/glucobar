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

    /// The file actually read and written: `url` with symlinks followed (e.g. into a synced
    /// folder), even when the target doesn't exist yet. An atomic write to the symlink itself
    /// would replace it with a plain file and silently stop the sync.
    public var fileURL: URL {
        var current = url
        for _ in 0..<8 {
            guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else { break }
            current = URL(fileURLWithPath: dest, relativeTo: current.deletingLastPathComponent()).standardizedFileURL
        }
        return current
    }

    /// Returns the stored config, writing the defaults first if the file doesn't exist.
    public func loadOrCreate() throws -> GlucoBarConfig {
        let file = fileURL
        guard FileManager.default.fileExists(atPath: file.path) else {
            let config = GlucoBarConfig()
            try save(config)
            return config
        }
        return try JSONDecoder().decode(GlucoBarConfig.self, from: Data(contentsOf: file))
    }

    public func save(_ config: GlucoBarConfig) throws {
        let file = fileURL
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: file, options: .atomic)
    }
}
