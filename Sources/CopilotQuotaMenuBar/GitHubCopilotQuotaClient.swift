import Foundation

struct PremiumInteractionsQuota: Sendable {
    let login: String
    let entitlement: Int?
    let remaining: Int?
    let unlimited: Bool
    let fetchedAt: Date
}

final class GitHubCopilotQuotaClient: @unchecked Sendable {
    private let authProvider: AuthTokenProvider

    init(authProvider: AuthTokenProvider) {
        self.authProvider = authProvider
    }

    func fetchPremiumInteractionsQuota() async throws -> PremiumInteractionsQuota {
        let token = try authProvider.fetchToken().token

        var req = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/user")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("2025-05-01", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue(AppMetadata.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SimpleError(message: "Network error")
        }
        guard http.statusCode == 200 else {
            throw SimpleError(message: http.statusCode == 401 ? "Unauthorized (sign in again)" : "HTTP \(http.statusCode)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let user = try decoder.decode(CopilotInternalUser.self, from: data)

        let premium = user.quotaSnapshots?.premiumInteractions
        return PremiumInteractionsQuota(
            login: user.login ?? "—",
            entitlement: premium?.entitlement,
            remaining: premium?.remaining,
            unlimited: premium?.unlimited ?? false,
            fetchedAt: Date()
        )
    }
}

private struct CopilotInternalUser: Codable {
    let login: String?
    let quotaSnapshots: QuotaSnapshots?
}

private struct QuotaSnapshots: Codable {
    let premiumInteractions: QuotaSnapshot?
}

private struct QuotaSnapshot: Codable {
    let entitlement: Int?
    let remaining: Int?
    let unlimited: Bool?
}
