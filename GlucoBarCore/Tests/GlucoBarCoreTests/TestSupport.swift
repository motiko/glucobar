import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import GlucoBarCore

/// Answers requests by "METHOD /path" and records what was sent.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    typealias Reply = (status: Int, body: String, headers: [String: String])
    private let lock = NSLock()
    private var routes: [String: [Reply]] = [:]
    private(set) var requests: [URLRequest] = []

    /// Queue replies for a route; the last one repeats.
    func on(_ route: String, _ replies: Reply...) {
        lock.withLock { routes[route, default: []].append(contentsOf: replies) }
    }

    var sent: [String] { lock.withLock { requests.map(Self.key) } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = lock.withLock {
            requests.append(request)
            let key = Self.key(request)
            guard var queue = routes[key], !queue.isEmpty else { return (404, "{}", [:]) }
            let r = queue.count > 1 ? queue.removeFirst() : queue[0]
            routes[key] = queue
            return r
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil,
                                       headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }

    static func key(_ r: URLRequest) -> String { "\(r.httpMethod ?? "GET") \(r.url!.host!)\(r.url!.path)" }
}

final class MemorySecrets: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func secret(named name: String) throws -> String? { lock.withLock { values[name] } }
    func setSecret(_ value: String?, named name: String) throws { lock.withLock { values[name] = value } }
}
