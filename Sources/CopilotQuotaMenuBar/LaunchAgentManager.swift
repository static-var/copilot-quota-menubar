import Foundation

@MainActor
final class LaunchAgentManager {
    static let shared = LaunchAgentManager()

    private var label: String { AppMetadata.launchAgentLabel }

    private init() {}

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func ensureEnabledByDefault(executablePath: String) throws {
        // Always rewrite the plist so upgrades can adjust settings (e.g., KeepAlive).
        if isEnabled {
            try install(executablePath: executablePath)
            return
        }
        try setEnabled(true, executablePath: executablePath)
    }

    func setEnabled(_ enabled: Bool, executablePath: String) throws {
        if enabled {
            try install(executablePath: executablePath)
            try bootstrap()
        } else {
            try bootoutIfLoaded()
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    private func install(executablePath: String) throws {
        let launchAgentsDir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        let programArgumentsXML: String
        if let bundleId = Bundle.main.bundleIdentifier {
            programArgumentsXML = """
              <string>/usr/bin/open</string>
              <string>-b</string>
              <string>\(bundleId)</string>
            """
        } else {
            let exe = URL(fileURLWithPath: executablePath).standardizedFileURL.path
            programArgumentsXML = """
              <string>\(exe)</string>
            """
        }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
        \(programArgumentsXML)
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>ProcessType</key>
          <string>Interactive</string>
        </dict>
        </plist>
        """
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)
    }

    /// Stop the agent for this login session, without removing the plist (so it can start on next login).
    func stopForThisSessionIfLoaded() {
        guard isEnabled else { return }
        try? bootoutIfLoaded()
    }

    private func bootstrap() throws {
        let uid = String(getuid())
        _ = try ProcessRunner.run(
            executable: "/bin/launchctl",
            arguments: ["bootstrap", "gui/\(uid)", plistURL.path]
        )
    }

    private func bootoutIfLoaded() throws {
        let uid = String(getuid())
        do {
            _ = try ProcessRunner.run(
                executable: "/bin/launchctl",
                arguments: ["bootout", "gui/\(uid)", plistURL.path]
            )
        } catch {
            // If it wasn't loaded, bootout can fail; in that case we still want to remove the plist.
        }
    }
}

private enum ProcessRunner {
    static func run(executable: String, arguments: [String]) throws -> String {
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
            throw SimpleError(message: err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "launchctl failed" : err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out
    }
}
