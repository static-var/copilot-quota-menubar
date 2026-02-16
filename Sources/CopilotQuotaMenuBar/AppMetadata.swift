import Foundation

enum AppMetadata {
    private static let defaultBundleIdentifier = "dev.staticvar.copilot-quota-menubar"
    private static let defaultDisplayName = "Copilot Quota"

    static var bundleIdentifier: String {
        env("COPILOT_QUOTA_BUNDLE_ID")
            ?? Bundle.main.bundleIdentifier
            ?? defaultBundleIdentifier
    }

    static var displayName: String {
        env("COPILOT_QUOTA_APP_NAME")
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? defaultDisplayName
    }

    static var userAgent: String {
        env("COPILOT_QUOTA_USER_AGENT") ?? bundleIdentifier
    }

    static var launchAgentLabel: String {
        env("COPILOT_QUOTA_LAUNCH_AGENT_LABEL") ?? bundleIdentifier
    }

    static var lockFileName: String {
        let raw = env("COPILOT_QUOTA_LOCK_FILE") ?? bundleIdentifier
        let safe = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return "\(safe).lock"
    }

    private static func env(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
    }
}

