import Foundation
import Security

struct CloudSession: Codable {
    let userID: UUID
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    static var stored: Self? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        let fields = [kSecValueData as String: data]
        let status = SecItemUpdate(Self.keychainQuery as CFDictionary, fields as CFDictionary)
        if status == errSecItemNotFound {
            var query = Self.keychainQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw CloudError.keychain }
        } else if status != errSecSuccess {
            throw CloudError.keychain
        }
    }

    private static var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.ajolo.supabase",
         kSecAttrAccount as String: "watch-session"]
    }
}

enum CloudError: LocalizedError {
    case configuration, keychain, response, conflict, signupUnavailable
    case rejected(Int, String?)

    var errorDescription: String? {
        switch self {
        case .configuration: return "Supabase is not configured for Ajoló."
        case .keychain: return "The watch could not save your session securely."
        case .response: return "Supabase returned an unexpected response."
        case .signupUnavailable:
            return "Sign-up could not be completed. If your account is confirmed, sign in instead."
        case .conflict: return "Another watch updated your save. This copy is still on your watch."
        case .rejected(let status, let code):
            if code == "email_address_not_authorized" {
                return "The email provider cannot send confirmation to that address."
            }
            if code == "over_email_send_rate_limit" {
                return "Too many confirmation emails. Wait and try again."
            }
            if code == "otp_expired" {
                return "That code is invalid or expired. Request a new one, or sign in if your email is confirmed."
            }
            if code == "email_not_confirmed" { return "Confirm your email before signing in." }
            if code == "invalid_credentials" { return "Check your email and password." }
            if code == "user_already_exists" { return "This email already has an account. Sign in." }
            if status == 401 || code == "refresh_token_not_found" || code == "refresh_token_already_used" {
                return "Link your account again from iPhone."
            }
            if status == 429 { return "Wait a moment and try again." }
            return "Supabase could not complete the request (\(status))."
        }
    }
}

struct CloudRecord: Decodable {
    let revision: Int
    let journal: Journal
}

struct CloudClient {
    private struct Configuration: Decodable {
        let url: String
        let publishableKey: String
    }

    private struct AuthReply: Decodable {
        struct User: Decodable { let id: UUID }
        let user: User?
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Double?

        var session: CloudSession? {
            guard let user, let accessToken, let refreshToken, let expiresIn else { return nil }
            return CloudSession(userID: user.id, accessToken: accessToken,
                                refreshToken: refreshToken, expiresAt: Date().addingTimeInterval(expiresIn))
        }
    }

    private struct APIError: Decodable {
        let errorCode: String?
        let code: String?
    }

    private struct Write: Encodable {
        let pOperation: UUID
        let pRevision: Int
        let pJournal: Journal

        enum CodingKeys: String, CodingKey {
            case pOperation = "p_operation", pRevision = "p_revision", pJournal = "p_journal"
        }
    }

    private struct MatchWrite: Encodable {
        let intent: EncounterIntent

        enum CodingKeys: String, CodingKey {
            case match = "p_match", own = "p_own", partner = "p_partner", moves = "p_moves"
        }

        func encode(to encoder: Encoder) throws {
            var fields = encoder.container(keyedBy: CodingKeys.self)
            try fields.encode(intent.id, forKey: .match)
            try fields.encode(intent.ownID, forKey: .own)
            try fields.encode(intent.partnerID, forKey: .partner)
            try fields.encode(intent.moves, forKey: .moves)
        }
    }

    private let baseURL: URL
    private let publishableKey: String

    init() throws {
        guard let file = Bundle.main.url(forResource: "CloudConfiguration", withExtension: "plist"),
              let data = try? Data(contentsOf: file),
              let config = try? PropertyListDecoder().decode(Configuration.self, from: data),
              let url = URL(string: config.url),
              url.scheme == "https", url.host?.hasSuffix(".supabase.co") == true,
              config.publishableKey.hasPrefix("sb_publishable_") else {
            throw CloudError.configuration
        }
        baseURL = url
        publishableKey = config.publishableKey
    }

    func signIn(email: String, password: String, create: Bool) async throws -> CloudSession? {
        let path = create ? "auth/v1/signup" : "auth/v1/token"
        let query = create ? [] : [URLQueryItem(name: "grant_type", value: "password")]
        do {
            let reply: AuthReply = try await send(path, query: query,
                                                  body: ["email": email, "password": password])
            if !create && reply.session == nil { throw CloudError.response }
            return reply.session
        } catch CloudError.rejected(500, _) where create {
            throw CloudError.signupUnavailable
        }
    }

    func confirmSignup(email: String, code: String) async throws -> CloudSession {
        let reply: AuthReply = try await send("auth/v1/verify",
            body: ["type": "email", "email": email, "token": code])
        guard let session = reply.session else { throw CloudError.response }
        return session
    }

    func resendSignup(email: String) async throws {
        let _: AuthReply = try await send("auth/v1/resend", body: ["type": "signup", "email": email])
    }

    func refresh(_ session: CloudSession) async throws -> CloudSession {
        let reply: AuthReply = try await send("auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: ["refresh_token": session.refreshToken])
        guard let updated = reply.session, updated.userID == session.userID else { throw CloudError.response }
        return updated
    }

    func read(_ session: CloudSession) async throws -> CloudRecord? {
        let rows: [CloudRecord] = try await send("rest/v1/ajolo_accounts",
            query: [URLQueryItem(name: "select", value: "revision,journal"),
                    URLQueryItem(name: "user_id", value: "eq.\(session.userID.uuidString)")],
            body: Optional<String>.none, session: session)
        return rows.first
    }

    func write(_ journal: Journal, session: CloudSession, revision: Int, operation: UUID) async throws -> Int {
        let next: Int? = try await send("rest/v1/rpc/ajolo_save",
            body: Write(pOperation: operation, pRevision: revision, pJournal: journal), session: session)
        guard let next else { throw CloudError.conflict }
        return next
    }

    func submitEncounter(_ intent: EncounterIntent, session: CloudSession) async throws -> EncounterReceipt {
        try await send("rest/v1/rpc/ajolo_submit_encounter", body: MatchWrite(intent: intent), session: session)
    }

    private func send<T: Decodable, Body: Encodable>(_ path: String, query: [URLQueryItem] = [],
        body: Body?, session: CloudSession? = nil) async throws -> T {
        let endpoint = baseURL.appendingPathComponent(path)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw CloudError.configuration }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        if let session { request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudError.response }
        let decoder = JSONDecoder()
        if path.hasPrefix("auth/") { decoder.keyDecodingStrategy = .convertFromSnakeCase }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? decoder.decode(APIError.self, from: data)
            throw CloudError.rejected(http.statusCode, error?.errorCode ?? error?.code)
        }
        return try decoder.decode(T.self, from: data)
    }
}

struct CloudCache: Codable {
    struct Pending: Codable {
        let id: UUID
        let journal: Journal
    }

    var journal: Journal
    var revision: Int?
    var pending: Pending?

    static func key(_ owner: UUID) -> String { "ajolo-account-v1-\(owner.uuidString)" }

    static func load(_ owner: UUID) -> CloudCache? {
        guard let data = UserDefaults.standard.data(forKey: key(owner)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save(_ owner: UUID) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(owner))
    }
}
