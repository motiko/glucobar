import Foundation

/// Syncs settings between Macs by keeping config.json in iCloud Drive and pointing the usual
/// path (~/.config/glucobar/config.json) at it with a symlink. Secrets stay in each Mac's Keychain.
public struct SettingsSync: Sendable {
    /// The path GlucoBar (and the user's hand edits) use; becomes a symlink while syncing.
    public let localURL: URL
    /// The synced folder's root: iCloud Drive, or a temp dir in tests.
    public let cloudRoot: URL
    private var fileManager: FileManager { .default }

    public init(localURL: URL, cloudRoot: URL = SettingsSync.iCloudDrive) {
        self.localURL = localURL
        self.cloudRoot = cloudRoot
    }

    public static var iCloudDrive: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    public var cloudURL: URL {
        cloudRoot.appendingPathComponent("GlucoBar/config.json")
    }

    /// iCloud Drive is turned on for this Mac.
    public var isAvailable: Bool { fileManager.fileExists(atPath: cloudRoot.path) }

    public var isEnabled: Bool {
        guard let dest = try? fileManager.destinationOfSymbolicLink(atPath: localURL.path) else { return false }
        return URL(fileURLWithPath: dest).standardizedFileURL.path == cloudURL.standardizedFileURL.path
    }

    /// Another Mac already syncs settings (the file may still be downloading).
    public var cloudCopyExists: Bool {
        fileManager.fileExists(atPath: cloudURL.path) || fileManager.fileExists(atPath: placeholderURL.path)
    }

    /// iCloud's stand-in for a file it hasn't downloaded: ".config.json.icloud".
    private var placeholderURL: URL {
        cloudURL.deletingLastPathComponent().appendingPathComponent(".\(cloudURL.lastPathComponent).icloud")
    }

    /// Starts syncing. `useCloudCopy`: take the settings already in iCloud (this Mac's file is kept
    /// as config.before-sync.json); otherwise this Mac's settings replace the iCloud copy.
    public func enable(useCloudCopy: Bool) throws {
        try fileManager.createDirectory(at: cloudURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let hasLocal = fileManager.fileExists(atPath: localURL.path)
        if useCloudCopy && cloudCopyExists {
            if hasLocal {
                let backup = localURL.deletingLastPathComponent().appendingPathComponent("config.before-sync.json")
                try? fileManager.removeItem(at: backup)
                try fileManager.moveItem(at: localURL, to: backup)
            }
            ensureDownloaded()
        } else if hasLocal {
            try? fileManager.removeItem(at: cloudURL)
            try fileManager.moveItem(at: localURL, to: cloudURL)
        }
        try fileManager.createSymbolicLink(at: localURL, withDestinationURL: cloudURL)
    }

    /// Stops syncing: this Mac keeps a plain copy of the current settings; iCloud's copy stays for other Macs.
    public func disable() throws {
        guard isEnabled else { return }
        ensureDownloaded()
        let data = try? Data(contentsOf: cloudURL)
        try fileManager.removeItem(at: localURL)
        if let data { try data.write(to: localURL, options: .atomic) }
    }

    /// If iCloud has evicted the file to save space, fetch it, waiting up to `timeout` seconds so
    /// GlucoBar doesn't start from defaults (and then overwrite the synced settings with them).
    public func ensureDownloaded(timeout: TimeInterval = 10) {
        guard !fileManager.fileExists(atPath: cloudURL.path),
              fileManager.fileExists(atPath: placeholderURL.path) else { return }
        #if canImport(Darwin)
        try? fileManager.startDownloadingUbiquitousItem(at: cloudURL)
        #endif
        let deadline = Date().addingTimeInterval(timeout)
        while !fileManager.fileExists(atPath: cloudURL.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
    }
}
