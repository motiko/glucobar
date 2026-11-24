#if canImport(CryptoKit)
import CryptoKit

/// Test-only reference implementation (macOS), to check the pure-Swift SHA-256.
enum CryptoKitReference {
    static func hash(_ bytes: [UInt8]) -> [UInt8] { Array(CryptoKit.SHA256.hash(data: bytes)) }
}
#endif
