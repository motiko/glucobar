/// Reads and writes secrets by name. The config file only ever holds these names
/// (see docs/adr/0002). The Mac app backs this with Keychain; a Linux relay can use
/// environment variables or a file.
public protocol SecretStore: Sendable {
    func secret(named name: String) throws -> String?
    func setSecret(_ value: String?, named name: String) throws
}
