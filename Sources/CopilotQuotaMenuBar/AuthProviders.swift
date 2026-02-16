import Foundation

struct GitHubAuthToken: Sendable {
    let token: String
    let source: String
}

protocol AuthTokenProvider: Sendable {
    func fetchToken() throws -> GitHubAuthToken
}

struct AuthTokenProviderChainError: LocalizedError, Sendable {
    struct Failure: Sendable {
        let provider: String
        let message: String
    }

    let failures: [Failure]

    var errorDescription: String? { "No GitHub auth token found" }
}

struct AuthTokenProviderChain: AuthTokenProvider {
    let providers: [any AuthTokenProvider]

    func fetchToken() throws -> GitHubAuthToken {
        var failures: [AuthTokenProviderChainError.Failure] = []
        for provider in providers {
            do { return try provider.fetchToken() } catch {
                failures.append(.init(provider: providerName(provider), message: error.userFacingMessage))
            }
        }
        guard !failures.isEmpty else {
            throw SimpleError(message: "No auth providers configured")
        }
        throw AuthTokenProviderChainError(failures: failures)
    }

    private func providerName(_ provider: any AuthTokenProvider) -> String {
        switch provider {
        case is VSCodeAuthTokenProvider:
            return "VS Code"
        case is GitHubCLITokenProvider:
            return "GitHub CLI (gh)"
        default:
            return String(describing: type(of: provider))
        }
    }
}

struct SimpleError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

extension Error {
    var userFacingMessage: String {
        if let e = self as? SimpleError { return e.message }
        if let e = self as? LocalizedError, let d = e.errorDescription { return d }
        return "Error"
    }
}
