import Foundation

struct GitHubCLITokenProvider: AuthTokenProvider {
    func fetchToken() throws -> GitHubAuthToken {
        let token: String
        do {
            token = try ProcessRunner.runAndCaptureStdout(
                executable: "/usr/bin/env",
                arguments: ["gh", "auth", "token"]
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            let msg = error.userFacingMessage
            if msg.localizedCaseInsensitiveContains("no such file")
                || msg.localizedCaseInsensitiveContains("not found")
                || msg.localizedCaseInsensitiveContains("env: gh")
            {
                throw SimpleError(message: "GitHub CLI (gh) not installed")
            }
            if msg.localizedCaseInsensitiveContains("gh auth login")
                || msg.localizedCaseInsensitiveContains("not logged")
                || msg.localizedCaseInsensitiveContains("authentication")
                || msg.localizedCaseInsensitiveContains("credentials")
            {
                throw SimpleError(message: "GitHub CLI not authenticated (run: gh auth login)")
            }
            throw error
        }

        guard !token.isEmpty else {
            throw SimpleError(message: "gh returned empty token")
        }
        return GitHubAuthToken(token: token, source: "gh")
    }
}

private enum ProcessRunner {
    static func runAndCaptureStdout(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw SimpleError(message: err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Command failed" : err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out
    }
}
