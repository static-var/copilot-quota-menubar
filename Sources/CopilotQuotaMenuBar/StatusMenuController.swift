import AppKit
import Foundation

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let menu = NSMenu()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private let userItem = NSMenuItem(title: "User: —", action: nil, keyEquivalent: "")
    private let quotaItem = NSMenuItem(title: "Premium requests: —", action: nil, keyEquivalent: "")
    private let updatedItem = NSMenuItem(title: "Last updated: —", action: nil, keyEquivalent: "")

    private let progressView = QuotaProgressView()
    private let progressItem = NSMenuItem()

    private lazy var quotaClient = GitHubCopilotQuotaClient(
        authProvider: AuthTokenProviderChain(providers: [
            VSCodeAuthTokenProvider(),
            GitHubCLITokenProvider(),
        ])
    )

    private var refreshTimer: Timer?

    private let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let openBillingItem = NSMenuItem(title: "Open Copilot Usage (GitHub)…", action: #selector(openBilling), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")

    private var setupSectionItems: [NSMenuItem] = []
    private let setupHeaderItem = NSMenuItem(title: "Setup required", action: nil, keyEquivalent: "")
    private let installVSCodeItem = NSMenuItem(title: "Install VS Code…", action: #selector(openVSCode), keyEquivalent: "")
    private let installGitHubCLIItem = NSMenuItem(title: "Install GitHub CLI (gh)…", action: #selector(openGitHubCLI), keyEquivalent: "")
    private let ghAuthHelpItem = NSMenuItem(title: "Sign in with gh…", action: #selector(openGHAuthHelp), keyEquivalent: "")

    func start() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Copilot quota")
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
        }

        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        buildMenu()

        // Auto-start on login by default (user can disable from the menu).
        do {
            try LaunchAgentManager.shared.ensureEnabledByDefault(executablePath: ProcessInfo.processInfo.arguments[0])
        } catch {
            NSApp.presentError(error)
        }
        syncLaunchAtLoginMenuState()

        Task { await refresh() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh() }
        }
    }

    private func buildMenu() {
        let header = NSMenuItem(title: AppMetadata.displayName, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(userItem)
        menu.addItem(quotaItem)

        progressItem.view = progressView
        menu.addItem(progressItem)
        menu.addItem(updatedItem)

        menu.addItem(.separator())

        refreshItem.target = self
        menu.addItem(refreshItem)

        openBillingItem.target = self
        menu.addItem(openBillingItem)

        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        setupHeaderItem.isEnabled = false
        installVSCodeItem.target = self
        installGitHubCLIItem.target = self
        ghAuthHelpItem.target = self

        menu.addItem(.separator())

        quitItem.target = self
        menu.addItem(quitItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Make the custom view match the menu's width so the % label aligns like native menu items.
        progressView.frame.size.width = menu.size.width
        progressView.needsLayout = true
    }

    @objc private func refreshNow() {
        Task { await refresh() }
    }

    private func refresh() async {
        quotaItem.title = "Premium requests: Loading…"
        updatedItem.title = "Last updated: —"
        progressView.setIndeterminate()

        do {
            let premium = try await quotaClient.fetchPremiumInteractionsQuota()
            render(premium)
        } catch {
            renderError(error)
        }
    }

    private func render(_ quota: PremiumInteractionsQuota) {
        hideSetupSection()
        userItem.title = "User: \(quota.login)"

        if quota.unlimited {
            quotaItem.title = "Premium requests: Unlimited"
            progressView.setUnlimited()
        } else if let remaining = quota.remaining, let entitlement = quota.entitlement {
            quotaItem.title = "Premium requests: \(remaining) / \(entitlement) remaining"
            progressView.setRemaining(remaining: remaining, entitlement: entitlement)
        } else {
            quotaItem.title = "Premium requests: —"
            progressView.setIndeterminate()
        }

        updatedItem.title = "Last updated: \(DateFormatter.shortTime.string(from: quota.fetchedAt))"
    }

    private func renderError(_ error: Error) {
        userItem.title = "User: —"
        quotaItem.title = "Premium requests: \(error.userFacingMessage)"
        updatedItem.title = "Last updated: —"
        progressView.setIndeterminate()
        updateSetupSection(for: error)
    }

    private func updateSetupSection(for error: Error) {
        if let chainError = error as? AuthTokenProviderChainError {
            showSetupSection(failures: chainError.failures)
            return
        }
        if error.userFacingMessage.localizedCaseInsensitiveContains("Unauthorized") {
            showSetupSection(failures: nil)
            return
        }
        hideSetupSection()
    }

    private func showSetupSection(failures: [AuthTokenProviderChainError.Failure]?) {
        hideSetupSection()

        guard let updatedIndex = menu.items.firstIndex(of: updatedItem) else { return }

        var items: [NSMenuItem] = []
        items.append(.separator())
        items.append(setupHeaderItem)

        if let failures, !failures.isEmpty {
            for failure in failures {
                let item = NSMenuItem(title: "\(failure.provider): \(failure.message)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                items.append(item)
            }
        } else {
            let item = NSMenuItem(title: "Sign in via VS Code or GitHub CLI.", action: nil, keyEquivalent: "")
            item.isEnabled = false
            items.append(item)
        }

        items.append(installVSCodeItem)
        items.append(installGitHubCLIItem)
        items.append(ghAuthHelpItem)

        for (offset, item) in items.enumerated() {
            menu.insertItem(item, at: updatedIndex + 1 + offset)
        }
        setupSectionItems = items
    }

    private func hideSetupSection() {
        guard !setupSectionItems.isEmpty else { return }
        for item in setupSectionItems {
            menu.removeItem(item)
        }
        setupSectionItems.removeAll()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            let next = !LaunchAgentManager.shared.isEnabled
            try LaunchAgentManager.shared.setEnabled(next, executablePath: ProcessInfo.processInfo.arguments[0])
            syncLaunchAtLoginMenuState()
        } catch {
            NSApp.presentError(error)
        }
    }

    private func syncLaunchAtLoginMenuState() {
        launchAtLoginItem.state = LaunchAgentManager.shared.isEnabled ? .on : .off
    }

    @objc private func openVSCode() {
        NSWorkspace.shared.open(URL(string: "https://code.visualstudio.com/")!)
    }

    @objc private func openGitHubCLI() {
        NSWorkspace.shared.open(URL(string: "https://cli.github.com/")!)
    }

    @objc private func openGHAuthHelp() {
        NSWorkspace.shared.open(URL(string: "https://cli.github.com/manual/gh_auth_login")!)
    }

    @objc private func openBilling() {
        // GitHub’s UI is the official source of truth; the menu shows a lightweight snapshot.
        NSWorkspace.shared.open(URL(string: "https://github.com/settings/billing")!)
    }

    @objc private func quit() {
        // If the LaunchAgent is loaded, unload it so "Quit" doesn't relaunch the app.
        // The plist stays in ~/Library/LaunchAgents so it can start again on next login.
        LaunchAgentManager.shared.stopForThisSessionIfLoaded()
        NSApp.terminate(nil)
    }
}

private final class QuotaProgressView: NSView {
    private static let defaultSize = NSSize(width: 300, height: 52)

    private let stack = NSStackView()
    private let label = NSTextField(labelWithString: "Remaining")
    private let row = NSStackView()
    private let bar = NSProgressIndicator()
    private let percentLabel = NSTextField(labelWithString: "—")

    override var intrinsicContentSize: NSSize { Self.defaultSize }

    override init(frame frameRect: NSRect) {
        // NSMenuItem.view uses the view's frame size; a zero-sized view won't render.
        super.init(frame: NSRect(origin: .zero, size: Self.defaultSize))

        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .labelColor

        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false

        bar.isIndeterminate = false
        bar.controlSize = .small
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 1
        bar.doubleValue = 0
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        percentLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        percentLabel.textColor = .labelColor
        percentLabel.alignment = .right
        percentLabel.setContentHuggingPriority(.required, for: .horizontal)
        percentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addArrangedSubview(bar)
        row.addArrangedSubview(percentLabel)

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(row)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            percentLabel.widthAnchor.constraint(equalToConstant: 56),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setIndeterminate() {
        label.stringValue = "Remaining"
        percentLabel.stringValue = "—"
        bar.isIndeterminate = true
        bar.startAnimation(nil)
    }

    func setUnlimited() {
        label.stringValue = "Remaining: Unlimited"
        percentLabel.stringValue = "∞"
        bar.stopAnimation(nil)
        bar.isIndeterminate = false
        bar.maxValue = 1
        bar.doubleValue = 1
    }

    func setRemaining(remaining: Int, entitlement: Int) {
        label.stringValue = "Remaining: \(remaining) / \(entitlement)"
        if entitlement > 0 {
            let pct = (Double(remaining) / Double(entitlement)) * 100
            percentLabel.stringValue = String(format: "%.1f%%", pct)
        } else {
            percentLabel.stringValue = "—"
        }
        bar.stopAnimation(nil)
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = Double(entitlement)
        bar.doubleValue = Double(remaining)
    }
}

private extension DateFormatter {
    static let shortTime: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        df.dateStyle = .none
        return df
    }()
}
