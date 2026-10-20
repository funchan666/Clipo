import Foundation
import Combine
import Security
import UIKit
import OSLog

struct ClipoConfiguration {
    let apiBaseURL: URL?
    let bundleID: String
    let version: String
    let privacyURL: URL?
    let termsURL: URL?
    static var current: Self {
        let bundle = Bundle.main
        let host = (bundle.object(forInfoDictionaryKey: "ClipoAPIHost") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = host.isEmpty || host.contains("$(") ? nil : URL(string: "https://" + host)
        return Self(apiBaseURL: base, bundleID: bundle.bundleIdentifier ?? "",
                    version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
                    privacyURL: WebAddress.media(bundle.object(forInfoDictionaryKey: "ClipoPrivacyURL") as? String),
                    termsURL: WebAddress.media(bundle.object(forInfoDictionaryKey: "ClipoTermsURL") as? String))
    }
    var isReady: Bool {
        apiBaseURL?.host != nil && !bundleID.isEmpty && !bundleID.contains("unconfigured")
    }
}


enum SecureStorage {
    private static let service = "Clipo.Session"
    static func read(_ key: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ClipoError.storage }
        return data
    }
    static func write(_ data: Data, key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw ClipoError.storage }
        } else if status != errSecSuccess { throw ClipoError.storage }
        guard try read(key) == data else { throw ClipoError.storage }
    }
    static func remove(_ key: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ClipoError.storage }
    }
}

@MainActor
final class APIClient: ObservableObject {
    private let diagnostics = Logger(subsystem: "com.clipo.video", category: "API")
    @Published private(set) var session: VisitorSession?
    @Published private(set) var hasEnteredApp = false
    let configuration: ClipoConfiguration
    private let transport: URLSession
    private var loginTask: Task<VisitorSession, Error>?
    private var sessionGeneration = UUID()
    private var storageFailure: Error?

    init(configuration: ClipoConfiguration = .current) {
        self.configuration = configuration
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        transport = URLSession(configuration: config)
        do {
            if let data = try SecureStorage.read("visitor") {
                let saved = try JSONDecoder().decode(VisitorSession.self, from: data)
                if !saved.accessToken.isEmpty {
                    session = saved
                    hasEnteredApp = try SecureStorage.read("visitor-awaiting-welcome") == nil
                }
            }
        } catch {
            session = nil
            hasEnteredApp = false
            storageFailure = error
        }
    }

    // Prepare a real guest for package/ad configuration without bypassing the welcome gate.
    func prepareVisitor() async throws {
        guard session == nil else { return }
        try SecureStorage.write(Data([1]), key: "visitor-awaiting-welcome")
        _ = try await signIn()
    }

    // Only the explicit consent-checked welcome action may open the main interface.
    func enterApp() async throws {
        if session == nil { try await prepareVisitor() }
        try Task.checkCancellation()
        guard session != nil else { throw ClipoError.unauthorized }
        try SecureStorage.remove("visitor-awaiting-welcome")
        hasEnteredApp = true
    }

    @discardableResult func signIn() async throws -> VisitorSession {
        guard configuration.isReady else { throw ClipoError.configuration }
        if let storageFailure { throw storageFailure }
        if let loginTask { return try await loginTask.value }
        let generation = sessionGeneration
        let task = Task<VisitorSession, Error> { [self] in
            let device: String
            if let stored = try SecureStorage.read("installation"), let saved = String(data: stored, encoding: .utf8), !saved.isEmpty {
                device = saved
            } else {
                device = UUID().uuidString
                try SecureStorage.write(Data(device.utf8), key: "installation")
            }
            // The documented uniqueId may be empty. No third-party IP probe is necessary.
            let body = try JSONSerialization.data(withJSONObject: ["deviceCode": device, "source": configuration.bundleID, "uniqueId": ""])
            let result: VisitorSession = try await perform("/app-api/member/auth/app_tourist_login", method: "POST", body: body, authenticated: false)
            guard !result.accessToken.isEmpty, !result.userId.value.isEmpty else { throw ClipoError.invalidResponse }
            try Task.checkCancellation()
            guard generation == sessionGeneration else { throw CancellationError() }
            try SecureStorage.write(JSONEncoder().encode(result), key: "visitor")
            session = result
            return result
        }
        loginTask = task
        defer { loginTask = nil }
        return try await task.value
    }

    func signOut() throws {
        try SecureStorage.remove("visitor")
        sessionGeneration = UUID()
        loginTask?.cancel()
        loginTask = nil
        session = nil
        hasEnteredApp = false
        storageFailure = nil
    }

    // Explicitly local simulation until a server deletion contract is supplied.
    // Keep local media and immutable purchase recovery records intact.
    func resetLocalAccount() throws {
        let installation = try SecureStorage.read("installation")
        try SecureStorage.remove("installation")
        do {
            try signOut()
        } catch {
            if let installation { try SecureStorage.write(installation, key: "installation") }
            throw error
        }
    }

    func releaseConfiguration() async throws -> ReleaseConfiguration {
        guard let session else { throw ClipoError.unauthorized }
        return try await perform("/app-api/flow/release-package/getV2", query: [
            "platform": "IOS", "name": configuration.bundleID, "version": configuration.version,
            "lang": Bundle.main.preferredLocalizations.first ?? "en", "userId": session.userId.value,
            "time": TimeZone.current.identifier, "input": UITextInputMode.activeInputModes.compactMap(\.primaryLanguage).joined(separator: ",")
        ], authenticated: false)
    }
    func channels(links: [String]) async throws -> [LandingInfo] {
        let body = try JSONSerialization.data(withJSONObject: links.filter { $0.nilIfBlank != nil }.map {
            ["externalLinks": $0, "packageName": configuration.bundleID]
        })
        return try await perform("/app-api/flow/land-page/info_by_links_list", method: "POST", body: body, authenticated: false)
    }
    func resolve(_ link: String, password: String) async throws -> LandingInfo {
        try await perform("/app-api/flow/land-page/info_by_links", query: [
            "externalLinks": link, "password": password, "packageName": configuration.bundleID],
            missingDataMessage: "No content was returned for this link. Check the code, including uppercase and lowercase letters, or try again later.")
    }
    func channelPage(link: String, page: Int) async throws -> ChannelPage {
        try await perform("/app-api/flow/land-page/list_by_links_page", query: [
            "externalLinks": link, "pageNo": String(max(1, page)), "pageSize": "20", "packageName": configuration.bundleID])
    }
    func feed(query: String, feedID: String?, cursor: String?) async throws -> FeedResponse {
        guard let session else { throw ClipoError.unauthorized }
        var queryItems = ["userId": session.userId.value, "packageName": configuration.bundleID, "pageSize": "10"]
        if let feedID { queryItems["feedId"] = feedID }
        if let cursor { queryItems["cursor"] = cursor }
        if let query = query.nilIfBlank { queryItems["query"] = query }
        return try await perform("/app-api/flow/search-check", query: queryItems)
    }

    func rights() async throws -> UserRights {
        try await perform("/app-api/member/user/get")
    }
    // Payment requests use the immutable order owner. They never silently rebind to a renewed guest.
    func paymentRequest(path: String, body: [String: Any], owner: VisitorSession) async throws -> Data {
        guard configuration.isReady, let base = configuration.apiBaseURL else { throw ClipoError.configuration }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(owner.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw ClipoError.invalidResponse }
        if http.statusCode == 401 { throw ClipoError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw ClipoError.service("Purchase service is unavailable (\(http.statusCode)).") }
        struct Status: Decodable { let code: Int; let msg: String? }
        let status = try JSONDecoder().decode(Status.self, from: data)
        guard status.code == 0 else { throw ClipoError.service(status.msg ?? "Purchase confirmation failed.") }
        return data
    }

    private func perform<Value: Decodable>(_ path: String, method: String = "GET", query: [String: String] = [:],
                                           body: Data? = nil, authenticated: Bool = true, retry: Bool = true,
                                           missingDataMessage: String? = nil) async throws -> Value {
        guard configuration.isReady, let base = configuration.apiBaseURL,
              var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw ClipoError.configuration }
        var effectiveQuery = query
        // A renewed visitor can have a different user ID.
        if authenticated, effectiveQuery["userId"] != nil { effectiveQuery["userId"] = session?.userId.value }
        components.queryItems = effectiveQuery.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw ClipoError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let usedToken = session?.accessToken
        if authenticated {
            guard let usedToken else { throw ClipoError.unauthorized }
            request.setValue("Bearer \(usedToken)", forHTTPHeaderField: "Authorization")
        }
        let generation = sessionGeneration
        let (data, response) = try await send(request)
        try Task.checkCancellation()
        if authenticated, generation != sessionGeneration { throw CancellationError() }
        guard let response = response as? HTTPURLResponse else { throw ClipoError.invalidResponse }
        #if DEBUG
        // Never log tokens, passwords, query values, user IDs or response bodies.
        diagnostics.debug("\(method, privacy: .public) \(path, privacy: .public) HTTP \(response.statusCode)")
        #endif
        if response.statusCode == 401, authenticated {
            guard retry else { throw ClipoError.unauthorized }
            if session?.accessToken == usedToken { try await signIn() }
            return try await perform(path, method: method, query: query, body: body, authenticated: true, retry: false,
                                     missingDataMessage: missingDataMessage)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ClipoError.service("The service is unavailable (\(response.statusCode)). Please try again.")
        }
        let result: APIEnvelope<Value>
        do { result = try JSONDecoder().decode(APIEnvelope<Value>.self, from: data) }
        catch {
            #if DEBUG
            diagnostics.error("\(path, privacy: .public): response decoding failed")
            #endif
            throw ClipoError.invalidResponse
        }
        #if DEBUG
        diagnostics.debug("\(path, privacy: .public): business code \(result.code), data present \(result.data != nil)")
        #endif
        guard result.code == 0 else { throw ClipoError.service(result.msg?.nilIfBlank ?? "The request could not be completed.") }
        guard let value = result.data else {
            if let missingDataMessage { throw ClipoError.service(missingDataMessage) }
            throw ClipoError.invalidResponse
        }
        return value
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await transport.data(for: request) }
        catch {
            #if DEBUG
            let code = (error as NSError).code
            diagnostics.error("\(request.url?.path ?? "", privacy: .public): transport failed (\(code))")
            #endif
            throw ClipoError.connectionFailure(error)
        }
    }
}
