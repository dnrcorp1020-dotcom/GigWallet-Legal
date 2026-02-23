import Foundation
import Security
import UIKit

/// Lightweight async/await API client for the GigWallet backend
@Observable
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // Backend URL - change to production URL when deploying
    #if DEBUG
    var baseURL = "http://localhost:8080"
    #else
    var baseURL = "https://api.gigwallet.app"
    #endif

    var authToken: String? {
        didSet {
            // Persist token to Keychain whenever it changes
            if let token = authToken {
                KeychainHelper.save(key: "gigwallet_auth_token", value: token)
            } else {
                KeychainHelper.delete(key: "gigwallet_auth_token")
            }
        }
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = JSONEncoder()
        // Backend expects camelCase keys (deviceId, publicToken, etc.) — no conversion needed

        // Restore token from Keychain on launch
        self.authToken = KeychainHelper.load(key: "gigwallet_auth_token")
    }

    // MARK: - Auto-Authentication

    /// Ensures the client has a valid auth token.
    /// For Firebase-authenticated users: retrieves a Firebase ID token (auto-refreshes if expired).
    /// For anonymous/skip users: falls back to device-based registration with the backend.
    func ensureAuthenticated() async throws {
        // If the user is signed in with Firebase, always use a fresh Firebase ID token
        let isFirebaseAuth = await MainActor.run { FirebaseAuthManager.shared.isAuthenticated }

        if isFirebaseAuth {
            let token = try await FirebaseAuthManager.shared.getIDToken()
            authToken = token
            return
        }

        // Fallback: device-based registration for anonymous users
        if authToken != nil { return }

        let deviceId = await MainActor.run {
            UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        }

        let response: AuthResponse = try await request(.register(deviceId: deviceId, email: nil))
        authToken = response.token
    }

    /// Clears the stored auth token (used on sign-out).
    func clearAuthToken() {
        authToken = nil
    }

    // MARK: - Generic Request

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        var request = URLRequest(url: endpoint.url(base: baseURL))
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = endpoint.body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = try? decoder.decode(APIErrorResponse.self, from: data)
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorBody?.error)
        }

        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Keychain Helper

private enum KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.dnrcorp.gigwallet",
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.dnrcorp.gigwallet",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.dnrcorp.gigwallet",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.dnrcorp.gigwallet",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Endpoint Definition

struct APIEndpoint {
    let path: String
    let method: HTTPMethod
    let body: Encodable?
    let queryItems: [URLQueryItem]?

    init(path: String, method: HTTPMethod = .get, body: Encodable? = nil, queryItems: [URLQueryItem]? = nil) {
        self.path = path
        self.method = method
        self.body = body
        self.queryItems = queryItems
    }

    func url(base: String) -> URL {
        guard var components = URLComponents(string: base + path) else {
            // Fallback: percent-encode the path and try again
            let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            if let fallback = URL(string: base + encoded) { return fallback }
            // Last resort: return a safe placeholder URL (will fail at network layer, not crash)
            return URL(string: base) ?? URL(string: "https://api.gigwallet.app") ?? URL(fileURLWithPath: "/")
        }
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url ?? URL(string: base) ?? URL(string: "https://api.gigwallet.app") ?? URL(fileURLWithPath: "/")
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - Plaid Endpoints

extension APIEndpoint {
    static func createLinkToken() -> APIEndpoint {
        APIEndpoint(path: "/api/plaid/create-link-token", method: .post)
    }

    static func exchangeToken(publicToken: String, institutionId: String?, institutionName: String?) -> APIEndpoint {
        APIEndpoint(
            path: "/api/plaid/exchange-token",
            method: .post,
            body: ExchangeTokenBody(publicToken: publicToken, institutionId: institutionId, institutionName: institutionName)
        )
    }

    static func syncTransactions(plaidItemId: String) -> APIEndpoint {
        APIEndpoint(
            path: "/api/plaid/sync-transactions",
            method: .post,
            body: SyncTransactionsBody(plaidItemId: plaidItemId)
        )
    }

    static var plaidItems: APIEndpoint {
        APIEndpoint(path: "/api/plaid/items")
    }

    static func removePlaidItem(id: String) -> APIEndpoint {
        APIEndpoint(path: "/api/plaid/items/\(id)", method: .delete)
    }
}

// MARK: - Sync Endpoints

extension APIEndpoint {
    static func gigIncome(platform: String? = nil, from: String? = nil, to: String? = nil) -> APIEndpoint {
        var queryItems: [URLQueryItem] = []
        if let platform { queryItems.append(URLQueryItem(name: "platform", value: platform)) }
        if let from { queryItems.append(URLQueryItem(name: "from", value: from)) }
        if let to { queryItems.append(URLQueryItem(name: "to", value: to)) }
        return APIEndpoint(path: "/api/sync/gig-income", queryItems: queryItems.isEmpty ? nil : queryItems)
    }

    static func reviewTransaction(id: String, isGigIncome: Bool, platform: String?) -> APIEndpoint {
        APIEndpoint(
            path: "/api/sync/transactions/\(id)/review",
            method: .patch,
            body: ReviewTransactionBody(isGigIncome: isGigIncome, platform: platform)
        )
    }

    static var platformDiscovery: APIEndpoint {
        APIEndpoint(path: "/api/sync/platform-discovery")
    }

    /// Fetches non-gig bank transactions that could be business expenses (deductions).
    /// Returns charges/debits from the user's linked bank accounts.
    static func expenseCandidates(from: String? = nil, to: String? = nil, limit: Int? = nil) -> APIEndpoint {
        var queryItems: [URLQueryItem] = []
        if let from { queryItems.append(URLQueryItem(name: "from", value: from)) }
        if let to { queryItems.append(URLQueryItem(name: "to", value: to)) }
        if let limit { queryItems.append(URLQueryItem(name: "limit", value: String(limit))) }
        return APIEndpoint(path: "/api/sync/expense-candidates", queryItems: queryItems.isEmpty ? nil : queryItems)
    }
}

// MARK: - Argyle Endpoints

extension APIEndpoint {
    /// Creates an Argyle user (or returns existing) + user_token + link_key for the SDK
    static func createArgyleUser() -> APIEndpoint {
        APIEndpoint(path: "/api/argyle/create-user", method: .post)
    }

    /// Refreshes the Argyle user token (tokens expire after ~1 hour)
    static func refreshArgyleToken() -> APIEndpoint {
        APIEndpoint(path: "/api/argyle/refresh-token", method: .post)
    }

    /// Triggers a gig sync from Argyle API → backend database
    static func syncArgyleGigs() -> APIEndpoint {
        APIEndpoint(path: "/api/argyle/sync-gigs", method: .post)
    }

    /// Fetches stored Argyle gigs with optional filters
    static func argyleGigs(platform: String? = nil, from: String? = nil, to: String? = nil, limit: Int? = nil) -> APIEndpoint {
        var queryItems: [URLQueryItem] = []
        if let platform { queryItems.append(URLQueryItem(name: "platform", value: platform)) }
        if let from { queryItems.append(URLQueryItem(name: "from", value: from)) }
        if let to { queryItems.append(URLQueryItem(name: "to", value: to)) }
        if let limit { queryItems.append(URLQueryItem(name: "limit", value: String(limit))) }
        return APIEndpoint(path: "/api/argyle/gigs", queryItems: queryItems.isEmpty ? nil : queryItems)
    }

    /// Lists connected Argyle accounts (gig platforms)
    static var argyleAccounts: APIEndpoint {
        APIEndpoint(path: "/api/argyle/accounts")
    }

    /// Disconnects an Argyle account
    static func removeArgyleAccount(id: String) -> APIEndpoint {
        APIEndpoint(path: "/api/argyle/accounts/\(id)", method: .delete)
    }
}

// MARK: - Auth Endpoints

extension APIEndpoint {
    static func register(deviceId: String, email: String?) -> APIEndpoint {
        APIEndpoint(
            path: "/api/auth/register",
            method: .post,
            body: RegisterBody(deviceId: deviceId, email: email)
        )
    }

    static func registerOAuth(provider: String, providerUserId: String, email: String?, identityToken: String?) -> APIEndpoint {
        APIEndpoint(
            path: "/api/auth/oauth",
            method: .post,
            body: OAuthRegisterBody(
                provider: provider,
                providerUserId: providerUserId,
                email: email,
                identityToken: identityToken
            )
        )
    }

    static func updateProfile(firstName: String?, lastName: String?, email: String?, phoneNumber: String?) -> APIEndpoint {
        APIEndpoint(
            path: "/api/auth/profile",
            method: .put,
            body: UpdateProfileBody(
                firstName: firstName,
                lastName: lastName,
                email: email,
                phoneNumber: phoneNumber
            )
        )
    }

    /// Syncs a Firebase-authenticated user with the backend.
    /// The backend verifies the Firebase ID token and creates/updates the user record.
    static func firebaseSync(firebaseUID: String, email: String?, displayName: String?, provider: String) -> APIEndpoint {
        APIEndpoint(
            path: "/api/auth/firebase-sync",
            method: .post,
            body: FirebaseSyncBody(
                firebaseUid: firebaseUID,
                email: email,
                displayName: displayName,
                provider: provider
            )
        )
    }
}

// MARK: - Request Bodies

private struct ExchangeTokenBody: Encodable {
    let publicToken: String
    let institutionId: String?
    let institutionName: String?
}

private struct SyncTransactionsBody: Encodable {
    let plaidItemId: String
}

private struct ReviewTransactionBody: Encodable {
    let isGigIncome: Bool
    let platform: String?
}

private struct RegisterBody: Encodable {
    let deviceId: String
    let email: String?
}

private struct OAuthRegisterBody: Encodable {
    let provider: String
    let providerUserId: String
    let email: String?
    let identityToken: String?
}

private struct UpdateProfileBody: Encodable {
    let firstName: String?
    let lastName: String?
    let email: String?
    let phoneNumber: String?
}

private struct FirebaseSyncBody: Encodable {
    let firebaseUid: String
    let email: String?
    let displayName: String?
    let provider: String
}

// MARK: - Response Types

struct LinkTokenResponse: Decodable {
    let linkToken: String
    let expiration: String
}

struct ExchangeTokenResponse: Decodable {
    let plaidItemId: String
    let institutionName: String?
    let accounts: [PlaidAccount]
}

struct PlaidAccount: Decodable, Identifiable {
    let id: String
    let name: String
    let type: String
    let subtype: String?
    let mask: String?
}

struct SyncTransactionsResponse: Decodable {
    let synced: Int
    let removed: Int
    let gigIncomeFound: Int
    let matches: [TransactionMatch]
    let platformSummary: [PlatformSummary]
}

struct TransactionMatch: Decodable, Identifiable {
    var id: String { "\(platform)-\(date)-\(amount)" }
    let platform: String
    let confidence: Double
    let amount: Double
    let date: String
    let name: String?
    let merchantName: String?
}

struct PlatformSummary: Decodable, Identifiable {
    var id: String { platform }
    let platform: String
    let category: String?
    let totalAmount: Double
    let transactionCount: Int
    let avgConfidence: Double
    let firstSeen: String
    let lastSeen: String
}

struct GigIncomeResponse: Decodable {
    let transactions: [GigTransaction]
    let summary: GigIncomeSummary
}

struct GigTransaction: Decodable, Identifiable {
    let id: String
    let amount: Double
    let date: String
    let name: String?
    let merchantName: String?
    let platform: String?
    let confidence: Double
    let isReviewed: Bool
}

struct GigIncomeSummary: Decodable {
    let totalGigIncome: Double
    let transactionCount: Int
}

struct PlaidItemsResponse: Decodable {
    let items: [PlaidItem]
}

struct PlaidItem: Decodable, Identifiable {
    let id: String
    let institutionName: String?
    let status: String
    let lastSyncedAt: String?
    let createdAt: String
}

struct PlatformDiscoveryResponse: Decodable {
    let discoveredPlatforms: [DiscoveredPlatform]
}

struct DiscoveredPlatform: Decodable, Identifiable {
    var id: String { platform }
    let platform: String
    let transactionCount: Int
    let totalAmount: Double
    let avgConfidence: Double
    let firstSeen: String
    let lastSeen: String
    let isActive: Bool
}

struct AuthResponse: Decodable {
    let userId: String
    let token: String
}

// MARK: - Expense Candidate Response Types

struct ExpenseCandidatesResponse: Decodable {
    let transactions: [ExpenseCandidateTransaction]
    let summary: ExpenseCandidateSummary
}

struct ExpenseCandidateTransaction: Decodable, Identifiable {
    let id: String
    let amount: Double
    let date: String
    let name: String?
    let merchantName: String?
    let plaidCategory: String?
}

struct ExpenseCandidateSummary: Decodable {
    let totalExpenses: Double
    let transactionCount: Int
}

// MARK: - Argyle Response Types

struct ArgyleUserResponse: Decodable {
    let userToken: String
    let linkKey: String
    let sandbox: Bool
}

struct ArgyleSyncResponse: Decodable {
    let synced: Int
    let totalGigs: Int?
    let platforms: [String]
    let totalEarnings: Double
    let platformSummary: [String: ArgylePlatformDetail]?

    /// Per-platform detail from backend's ArgyleGigMapper.summarize()
    struct ArgylePlatformDetail: Decodable {
        let totalEarnings: Double?
        let gigCount: Int?
        let totalTips: Double?
        let totalFees: Double?
    }

    /// Converts the backend dictionary into an array of ArgylePlatformSummary for UI use.
    var platformSummaries: [ArgylePlatformSummary] {
        guard let summary = platformSummary else {
            // Fallback: create minimal summaries from platform names only
            return platforms.map { ArgylePlatformSummary(platform: $0, gigCount: 0, totalEarnings: 0) }
        }
        return summary.map { key, value in
            ArgylePlatformSummary(
                platform: key,
                gigCount: value.gigCount ?? 0,
                totalEarnings: value.totalEarnings ?? 0
            )
        }
    }
}

struct ArgylePlatformSummary: Decodable, Identifiable {
    var id: String { platform }
    let platform: String
    let gigCount: Int
    let totalEarnings: Double

    /// Manual init for constructing from sync response dictionary
    init(platform: String, gigCount: Int, totalEarnings: Double) {
        self.platform = platform
        self.gigCount = gigCount
        self.totalEarnings = totalEarnings
    }
}

struct ArgyleGig: Decodable, Identifiable {
    let id: String
    let argyleGigId: String?
    let employer: String
    let platform: String
    let status: String?
    let gigType: String?
    let startDatetime: String?
    let endDatetime: String?
    let durationSeconds: Int?
    let distance: Double?
    let distanceUnit: String?
    let totalCharge: Double?
    let fees: Double?
    let pay: Double?
    let tips: Double?
    let bonus: Double?
    let total: Double?
    let startLat: Double?
    let startLng: Double?
    let endLat: Double?
    let endLng: Double?
    let isImported: Bool?
}

struct ArgyleGigResponse: Decodable {
    let gigs: [ArgyleGig]
    let summary: ArgyleGigSummary?

    struct ArgyleGigSummary: Decodable {
        let totalGigs: Int
        let totalEarnings: Double
    }
}

struct ArgyleAccount: Decodable, Identifiable {
    let id: String
    let argyleAccountId: String?
    let employer: String
    let platform: String?
    let status: String
    let lastSyncedAt: String?
    let createdAt: String
}

struct ArgyleAccountResponse: Decodable {
    let accounts: [ArgyleAccount]
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code, let message):
            return message ?? "HTTP error \(code)"
        case .decodingError(let error):
            return "Data error: \(error.localizedDescription)"
        }
    }
}

struct APIErrorResponse: Decodable {
    let error: String
}
