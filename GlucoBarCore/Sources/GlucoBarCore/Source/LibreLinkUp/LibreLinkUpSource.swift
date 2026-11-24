import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Glucose Source backed by Abbott's unofficial LibreLinkUp 4.x follower API.
///
/// Ported from the MIT-licensed nightscout-librelink-up and pylibrelinkup clients
/// (see THIRD_PARTY_NOTICES.md). Behaviour:
/// - logs in once and reuses the token until it expires (persisted in the SecretStore),
///   because LibreLinkUp locks the account after 3 failed logins in a minute;
/// - follows regional redirects and accepts Terms/Privacy Policy steps (`status: 4`);
/// - after a rejected login, makes no more network calls until it is recreated with
///   new credentials;
/// - keeps the latest Readings from recent polls so Delta has 1-minute resolution
///   (the graph endpoint only returns sparse history).
public actor LibreLinkUpSource: GlucoseSource {
    public struct Credentials: Sendable, Equatable {
        public var email: String
        public var password: String
        public init(email: String, password: String) {
            self.email = email
            self.password = password
        }
    }

    /// What we persist between launches so we don't log in on every start.
    struct Session: Codable, Equatable {
        var email: String
        var host: String
        var ticket: LLUAuthTicket
        var accountIdHash: String
    }

    private let settings: LibreLinkUpSettings
    private let credentials: Credentials?
    private let secrets: (any SecretStore)?
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date

    private var session: Session?
    private var sessionLoaded = false
    private var host: String
    private var rejectedLogin: String?
    private var loginTask: Task<Session, Error>?
    private var recentLatest: [Reading] = []

    /// Any regional host works for the first login; it redirects to the right one.
    public static let defaultHost = "api-us.libreview.io"
    static let userAgent = "Mozilla/5.0 (iPhone; CPU OS 17_4.1 like Mac OS X) AppleWebKit/536.26 (KHTML, like Gecko) Version/17.4.1 Mobile/10A5355d Safari/8536.25"
    private static let recentWindow: TimeInterval = 30 * 60

    public init(
        settings: LibreLinkUpSettings,
        credentials: Credentials?,
        secrets: (any SecretStore)? = nil,
        transport: any HTTPTransport = URLSession.shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.credentials = credentials
        self.secrets = secrets
        self.transport = transport
        self.now = now
        self.host = settings.region.map(Self.host(forRegion:)) ?? Self.defaultHost
    }

    // MARK: GlucoseSource

    public func fetch() async throws -> SourceSnapshot {
        let graph: LLUGraph = try await authenticated { session in
            let patientId = try await self.choosePatient(session)
            return try await self.get("/llu/connections/\(patientId)/graph", session: session)
        }
        return snapshot(from: graph)
    }

    /// Everyone who shares their data with this Follower account.
    public func patients() async throws -> [LLUPatient] {
        try await authenticated { session in try await self.connections(session) }.map {
            LLUPatient(id: $0.patientId,
                       name: [$0.firstName, $0.lastName].compactMap { $0 }.joined(separator: " "))
        }
    }

    // MARK: Snapshot

    private func snapshot(from graph: LLUGraph) -> SourceSnapshot {
        let history = (graph.graphData ?? []).compactMap { $0.reading(withTrend: false) }
        if let latest = graph.connection.glucoseMeasurement?.reading(withTrend: true),
           recentLatest.last?.timestamp != latest.timestamp {
            recentLatest.append(latest)
        }
        let cutoff = now().addingTimeInterval(-Self.recentWindow)
        recentLatest.removeAll { $0.timestamp < cutoff }

        // Polled 1-minute Readings win over sparse graph points at nearly the same time.
        let merged = history.filter { h in
            !recentLatest.contains { abs($0.timestamp.timeIntervalSince(h.timestamp)) < 30 }
        } + recentLatest
        return SourceSnapshot(readings: merged, patientDefaults: graph.connection.patientDefaults)
    }

    private func connections(_ session: Session) async throws -> [LLUConnection] {
        try await get("/llu/connections", session: session)
    }

    private func choosePatient(_ session: Session) async throws -> String {
        if let id = settings.patientId { return id }
        guard let first = try await connections(session).first else {
            throw GlucoseSourceError.unavailable("No one shares their data with this LibreLinkUp account")
        }
        return first.patientId
    }

    // MARK: Authentication

    /// Runs `body` with a valid session; on 401 logs in again once and retries.
    private func authenticated<T>(_ body: (Session) async throws -> T) async throws -> T {
        let session = try await validSession()
        do {
            return try await body(session)
        } catch LLUHTTPError.unauthorized {
            clearSession()
            do {
                return try await body(try await login())
            } catch LLUHTTPError.unauthorized {
                throw GlucoseSourceError.unavailable("LibreLinkUp refused a fresh token")
            }
        }
    }

    private func validSession() async throws -> Session {
        guard let credentials else { throw GlucoseSourceError.notSignedIn }
        if let rejectedLogin { throw GlucoseSourceError.authenticationFailed(rejectedLogin) }
        if !sessionLoaded {
            sessionLoaded = true
            session = loadSession()
        }
        if let s = session, s.email == credentials.email,
           s.ticket.expires > now().timeIntervalSince1970 + 60 {
            host = s.host
            return s
        }
        return try await login()
    }

    /// Concurrent callers share one in-flight login, so a bad password costs one
    /// failed attempt, not several (3 failures within a minute lock the account).
    private func login() async throws -> Session {
        if let loginTask { return try await loginTask.value }
        let task = Task { try await performLogin() }
        loginTask = task
        defer { loginTask = nil }
        return try await task.value
    }

    private func performLogin() async throws -> Session {
        guard let credentials else { throw GlucoseSourceError.notSignedIn }
        let body = try JSONEncoder().encode(["email": credentials.email, "password": credentials.password])
        var data = try await loginRequest(path: "/llu/auth/login", body: body, bearer: nil)

        if data.redirect == true, let region = data.region {
            host = Self.host(forRegion: region)
            data = try await loginRequest(path: "/llu/auth/login", body: body, bearer: nil)
        }

        // Terms of Use / Privacy Policy acceptance; may come as several consecutive steps.
        var steps = 0
        while let type = data.step?.type, steps < 3 {
            steps += 1
            if type == "verifyEmail" { throw reject("Verify your email in the LibreLinkUp app first") }
            guard let stepToken = data.authTicket?.token else { break }
            data = try await loginRequest(path: "/auth/continue/\(type)", body: nil, bearer: stepToken)
        }

        guard data.step == nil, let ticket = data.authTicket, let user = data.user else {
            throw reject("LibreLinkUp rejected the sign-in")
        }
        let s = Session(email: credentials.email, host: host, ticket: ticket,
                        accountIdHash: SHA256.hexDigest(user.id))
        session = s
        saveSession(s)
        return s
    }

    private func reject(_ message: String) -> GlucoseSourceError {
        rejectedLogin = message
        return .authenticationFailed(message)
    }

    private func loginRequest(path: String, body: Data?, bearer: String?) async throws -> LLULoginData {
        let envelope: LLUEnvelope<LLULoginData>
        do {
            envelope = try await send(request(path, method: "POST", body: body ?? Data(), bearer: bearer, accountIdHash: nil))
        } catch LLUHTTPError.unauthorized {
            throw reject("LibreLinkUp rejected the sign-in")
        }
        if let data = envelope.data { return data }
        throw reject(envelope.error?.message.map { "LibreLinkUp: \($0)" } ?? "LibreLinkUp rejected the sign-in")
    }

    private func clearSession() {
        session = nil
        try? secrets?.setSecret(nil, named: settings.tokenSecret)
    }

    private func loadSession() -> Session? {
        guard let json = try? secrets?.secret(named: settings.tokenSecret) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: Data(json.utf8))
    }

    private func saveSession(_ s: Session) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? secrets?.setSecret(String(decoding: data, as: UTF8.self), named: settings.tokenSecret)
    }

    // MARK: HTTP

    private func get<T: Decodable>(_ path: String, session: Session) async throws -> T {
        let envelope: LLUEnvelope<T> = try await send(
            request(path, method: "GET", body: nil, bearer: session.ticket.token, accountIdHash: session.accountIdHash))
        guard let data = envelope.data else {
            throw GlucoseSourceError.unavailable(envelope.error?.message ?? "Empty response from LibreLinkUp")
        }
        return data
    }

    private func request(_ path: String, method: String, body: Data?, bearer: String?, accountIdHash: String?) -> URLRequest {
        var r = URLRequest(url: URL(string: "https://\(host)\(path)")!)
        r.httpMethod = method
        r.httpBody = body
        r.timeoutInterval = 20
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        r.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        r.setValue(settings.product, forHTTPHeaderField: "product")
        r.setValue(settings.versionHeader, forHTTPHeaderField: "version")
        if let bearer { r.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let accountIdHash { r.setValue(accountIdHash, forHTTPHeaderField: "account-id") }
        return r
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw GlucoseSourceError.unavailable("Network: \(error.localizedDescription)")
        }
        switch response.statusCode {
        case 200..<300:
            break
        case 401:
            throw LLUHTTPError.unauthorized
        case 429, 430:
            throw GlucoseSourceError.rateLimited(retryAfter: Self.retryAfter(response, data))
        default:
            throw GlucoseSourceError.unavailable("LibreLinkUp HTTP \(response.statusCode)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GlucoseSourceError.unavailable("Unexpected LibreLinkUp response (API changed?)")
        }
    }

    /// `Retry-After` header, else the lockout seconds in a body like
    /// `{"code":60,"data":{"failures":3,"interval":60,"lockout":300},"message":"locked"}`.
    static func retryAfter(_ response: HTTPURLResponse, _ data: Data) -> TimeInterval? {
        if let header = response.value(forHTTPHeaderField: "Retry-After"), let s = TimeInterval(header) { return s }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return ((body?["data"] as? [String: Any])?["lockout"] as? NSNumber)?.doubleValue
    }

    // MARK: Mapping

    static func host(forRegion region: String) -> String {
        switch region.lowercased() {
        case "ru": "api.libreview.ru"
        case "cn": "api-cn.myfreestyle.cn"
        case let r: "api-\(r).libreview.io"
        }
    }

    /// LibreLinkUp TrendArrow → Trend.
    public static func trend(fromArrow arrow: Int) -> Trend? {
        switch arrow {
        case 1: .fallingFast
        case 2: .falling
        case 3: .flat
        case 4: .rising
        case 5: .risingFast
        default: nil
        }
    }
}

enum LLUHTTPError: Error { case unauthorized }
