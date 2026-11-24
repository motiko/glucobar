import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import GlucoBarCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000) // 1/15/2027 8:00:00 AM UTC
private let future = Int(t0.timeIntervalSince1970) + 86_400

/// Answers requests by "METHOD /path" and records what was sent.
private final class FakeTransport: HTTPTransport, @unchecked Sendable {
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

private final class MemorySecrets: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func secret(named name: String) throws -> String? { lock.withLock { values[name] } }
    func setSecret(_ value: String?, named name: String) throws { lock.withLock { values[name] = value } }
}

private func ok(_ body: String) -> FakeTransport.Reply { (200, body, [:]) }

private let loginOK = ok(#"{"status":0,"data":{"user":{"id":"user-123"},"authTicket":{"token":"tok","expires":\#(future),"duration":15552000000}}}"#)
private let connections = ok(#"{"status":0,"data":[{"patientId":"p1","firstName":"Pat","lastName":"Ient"}]}"#)
private func graph(latest: String = "1/15/2027 8:00:00 AM", value: Int = 124) -> FakeTransport.Reply {
    ok(#"""
    {"status":0,"data":{"connection":{"patientId":"p1","targetLow":70,"targetHigh":180,
      "alarmRules":{"h":{"th":200},"l":{"th":72},"f":{"th":55}},
      "glucoseMeasurement":{"FactoryTimestamp":"\#(latest)","Timestamp":"1/15/2027 9:00:00 AM","ValueInMgPerDl":\#(value),"TrendArrow":3,"GlucoseUnits":1,"isHigh":false,"isLow":false}},
     "graphData":[{"FactoryTimestamp":"1/15/2027 7:45:00 AM","ValueInMgPerDl":118,"isHigh":false,"isLow":false}]}}
    """#)
}

private let us = "api-us.libreview.io"
private let creds = LibreLinkUpSource.Credentials(email: "me@example.com", password: "pw")

private func makeSource(_ transport: FakeTransport, secrets: MemorySecrets = MemorySecrets(),
                        settings: LibreLinkUpSettings = LibreLinkUpSettings()) -> LibreLinkUpSource {
    LibreLinkUpSource(settings: settings, credentials: creds, secrets: secrets, transport: transport, now: { t0 })
}

@Suite struct SHA256Tests {
    @Test func knownVectors() {
        #expect(SHA256.hexDigest("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(SHA256.hexDigest("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(SHA256.hexDigest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
                == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    #if canImport(CryptoKit)
    @Test func matchesCryptoKitAcrossLengths() {
        for length in 0..<300 {
            let bytes = (0..<length).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
            let expected = Array(CryptoKitReference.hash(bytes))
            #expect(SHA256.hash(bytes) == expected, "length \(length)")
        }
    }
    #endif
}

@Suite struct LibreLinkUpSourceTests {
    @Test func signsInThenReadsGraph() async throws {
        let t = FakeTransport()
        t.on("POST \(us)/llu/auth/login", loginOK)
        t.on("GET \(us)/llu/connections", connections)
        t.on("GET \(us)/llu/connections/p1/graph", graph())

        let snap = try await makeSource(t).fetch()

        #expect(t.sent == ["POST \(us)/llu/auth/login", "GET \(us)/llu/connections", "GET \(us)/llu/connections/p1/graph"])
        let graphRequest = t.requests[2]
        #expect(graphRequest.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(graphRequest.value(forHTTPHeaderField: "account-id") == SHA256.hexDigest("user-123"))
        #expect(graphRequest.value(forHTTPHeaderField: "version") == "4.16.0")
        #expect(graphRequest.value(forHTTPHeaderField: "product") == "llu.ios")

        #expect(snap.latest == Reading(glucose: Glucose(mgPerDL: 124), timestamp: t0, trend: .flat))
        #expect(snap.readings.count == 2)
        #expect(snap.patientDefaults == PatientDefaults(unit: .mgPerDL, low: Glucose(mgPerDL: 72),
                                                         high: Glucose(mgPerDL: 200), urgentLow: Glucose(mgPerDL: 55)))
    }

    @Test func followsRegionRedirect() async throws {
        let t = FakeTransport()
        let eu = "api-eu.libreview.io"
        t.on("POST \(us)/llu/auth/login", ok(#"{"status":0,"data":{"redirect":true,"region":"eu"}}"#))
        t.on("POST \(eu)/llu/auth/login", loginOK)
        t.on("GET \(eu)/llu/connections", connections)
        t.on("GET \(eu)/llu/connections/p1/graph", graph())

        _ = try await makeSource(t).fetch()
        #expect(t.sent.first == "POST \(us)/llu/auth/login")
        #expect(t.sent.dropFirst().allSatisfy { $0.contains(eu) })
    }

    @Test func acceptsTermsSteps() async throws {
        let t = FakeTransport()
        t.on("POST \(us)/llu/auth/login",
             ok(#"{"status":4,"data":{"step":{"type":"tou"},"authTicket":{"token":"step1","expires":\#(future)}}}"#))
        t.on("POST \(us)/auth/continue/tou",
             ok(#"{"status":4,"data":{"step":{"type":"pp"},"authTicket":{"token":"step2","expires":\#(future)}}}"#))
        t.on("POST \(us)/auth/continue/pp", loginOK)
        t.on("GET \(us)/llu/connections", connections)
        t.on("GET \(us)/llu/connections/p1/graph", graph())

        _ = try await makeSource(t).fetch()
        #expect(t.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer step1")
        #expect(t.requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer step2")
    }

    @Test func rejectedLoginStopsCallingTheAPI() async throws {
        let t = FakeTransport()
        t.on("POST \(us)/llu/auth/login", ok(#"{"status":2,"error":{"message":"notAuthenticated"}}"#))
        let source = makeSource(t)

        await #expect(throws: GlucoseSourceError.authenticationFailed("LibreLinkUp: notAuthenticated")) {
            try await source.fetch()
        }
        await #expect(throws: GlucoseSourceError.self) { try await source.fetch() }
        #expect(t.sent.count == 1) // no second login attempt → no lockout
    }

    @Test func reusesPersistedSessionAcrossInstances() async throws {
        let t = FakeTransport()
        t.on("POST \(us)/llu/auth/login", loginOK)
        t.on("GET \(us)/llu/connections", connections)
        t.on("GET \(us)/llu/connections/p1/graph", graph())
        let secrets = MemorySecrets()

        let first = makeSource(t, secrets: secrets)
        _ = try await first.fetch()
        _ = try await first.fetch()
        _ = try await makeSource(t, secrets: secrets).fetch()

        #expect(t.sent.filter { $0.hasSuffix("/login") }.count == 1)
    }

    @Test func reLogsInOnceAfter401() async throws {
        let t = FakeTransport()
        t.on("POST \(us)/llu/auth/login", loginOK)
        t.on("GET \(us)/llu/connections", connections)
        t.on("GET \(us)/llu/connections/p1/graph", (401, "{}", [:]), graph())

        _ = try await makeSource(t).fetch()
        #expect(t.sent.filter { $0.hasSuffix("/login") }.count == 2)
    }

    @Test func lockoutBecomesRateLimited() async throws {
        let t = FakeTransport()
        t.on("POST \(us)/llu/auth/login",
             (429, #"{"code":60,"data":{"failures":3,"interval":60,"lockout":300},"message":"locked"}"#, [:]))
        await #expect(throws: GlucoseSourceError.rateLimited(retryAfter: 300)) { try await makeSource(t).fetch() }
    }

    @Test func usesConfiguredPatientAndKeepsPolledReadingsForDelta() async throws {
        let t = FakeTransport()
        t.on("POST \(us)/llu/auth/login", loginOK)
        t.on("GET \(us)/llu/connections/p9/graph",
             graph(latest: "1/15/2027 7:55:00 AM", value: 118), graph(latest: "1/15/2027 8:00:00 AM", value: 124))
        var settings = LibreLinkUpSettings()
        settings.patientId = "p9"
        let source = makeSource(t, settings: settings)

        _ = try await source.fetch()
        let snap = try await source.fetch()
        #expect(!t.sent.contains("GET \(us)/llu/connections"))
        #expect(Delta.compute(snap.readings)?.mgPerDL == 6)
    }

    @Test func concurrentCallersShareOneLogin() async throws {
        let t = FakeTransport()
        t.on("POST \(us)/llu/auth/login", loginOK)
        t.on("GET \(us)/llu/connections", connections)
        t.on("GET \(us)/llu/connections/p1/graph", graph())
        let source = makeSource(t)

        async let a = source.fetch()
        async let b = source.patients()
        _ = try await (a, b)
        #expect(t.sent.filter { $0.hasSuffix("/login") }.count == 1)
    }

    @Test func listsPatients() async throws {
        let t = FakeTransport()
        t.on("POST \(us)/llu/auth/login", loginOK)
        t.on("GET \(us)/llu/connections", connections)
        #expect(try await makeSource(t).patients() == [LLUPatient(id: "p1", name: "Pat Ient")])
    }
}
