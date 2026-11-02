import Foundation
import Combine
import SwiftUI

@MainActor
final class XcodeManagerViewModel: ObservableObject {
    @Published var installed: [XcodeInstallation] = []
    @Published var available: [XcodeRelease] = []
    @Published var selectedVersion: String?
    @Published var installProgress: [String] = []
    @Published var installProgressVersion: String?
    @Published var installStartedAt: Date?
    @Published var installPromptHint: String?
    @Published var pendingInstallInput = ""
    @Published var isInstallInputSecure = false
    @Published var statusMessage = "Ready"
    @Published var isLoading = false
    @Published var isInstalling = false
    @Published var isCancellingInstall = false

    private let service: any XcodeManaging
    private let activityCenter: GlobalActivityCenter
    private let historyRecorder: any OperationHistoryRecording
    private var installHeartbeatTask: Task<Void, Never>?
    private var lastInstallOutputAt: Date?
    private var lastHeartbeatLogAt: Date?
    private var didShowLongSilenceHint = false
    private var activeInstallActivityID: UUID?

    init(
        service: any XcodeManaging,
        activityCenter: GlobalActivityCenter,
        historyRecorder: (any OperationHistoryRecording)? = nil
    ) {
        self.service = service
        self.activityCenter = activityCenter
        self.historyRecorder = historyRecorder ?? OperationHistoryRecorder.shared
    }

    convenience init(activityCenter: GlobalActivityCenter? = nil) {
        let sharedActivityCenter = activityCenter ?? GlobalActivityCenter()
        self.init(service: XcodesCLIService(), activityCenter: sharedActivityCenter)
    }

    func load(force: Bool = false) async {
        guard force || !isInstalling else { return }

        isLoading = true
        defer { isLoading = false }

        let previousSelection = selectedVersion
        var loadWarnings: [String] = []
        var loadedInstalled: [XcodeInstallation] = []
        var loadedAvailable: [XcodeRelease] = []

        do {
            loadedInstalled = try await service.installedXcodes()
        } catch {
            loadWarnings.append("Installed versions: \(singleLine(error.localizedDescription))")
        }

        do {
            loadedAvailable = try await service.availableXcodes()
        } catch {
            loadWarnings.append("Available versions: \(singleLine(error.localizedDescription))")
        }

        installed = loadedInstalled.sorted {
            XcodeVersionOrdering.isNewer($0.version, than: $1.version)
        }

        if loadedAvailable.isEmpty {
            loadedAvailable = installed.map { installation in
                XcodeRelease(
                    version: installation.version,
                    isPrerelease: XcodeVersionOrdering.isPrerelease(installation.version),
                    isInstalled: true,
                    isSelected: installation.isSelected
                )
            }
        }

        available = XcodesOutputParser.mergedAvailableReleases(
            available: loadedAvailable,
            installed: installed
        )

        if let previousSelection,
           available.contains(where: { $0.version == previousSelection }) {
            selectedVersion = previousSelection
        } else if let activelySelected = available.first(where: \.isSelected)?.version {
            selectedVersion = activelySelected
        } else {
            selectedVersion = available.first?.version
        }

        if available.isEmpty {
            statusMessage = loadWarnings.isEmpty
                ? "No Xcode versions found."
                : "Unable to load Xcode versions. \(loadWarnings.joined(separator: " "))"
        } else if loadWarnings.isEmpty {
            statusMessage = "Loaded \(available.count) Xcode versions."
        } else {
            statusMessage = "Loaded with warnings. \(loadWarnings.joined(separator: " "))"
        }
    }

    var isBusy: Bool {
        isLoading || isInstalling
    }

    var installElapsedLabel: String {
        guard let installStartedAt else { return "00:00" }
        return Self.formatElapsed(Date().timeIntervalSince(installStartedAt))
    }

    var canInstallSelected: Bool {
        selectedVersion != nil && !isSelectedVersionInstalled
    }

    var canSelectSelected: Bool {
        selectedVersion != nil && isSelectedVersionInstalled && !isSelectedVersionActive
    }

    var canUninstallSelected: Bool {
        selectedVersion != nil && isSelectedVersionInstalled
    }

    var canSendInstallInput: Bool {
        isInstalling
            && !isCancellingInstall
            && !pendingInstallInput.trimmingCharacters(in: .newlines).isEmpty
    }

    var canCancelInstall: Bool {
        isInstalling && !isCancellingInstall
    }

    var shouldShowPasswordVisibilityToggle: Bool {
        isInstallInputSecure || (installPromptHint?.lowercased().contains("password") ?? false)
    }

    var shouldUseOneTimeCodeAutofill: Bool {
        let hint = installPromptHint?.lowercased() ?? ""
        if containsOneTimeCodeContext(hint) {
            return true
        }

        // Fallback: use recent install output context because xcodes prompt wording can vary.
        let recentContext = installProgress.suffix(8).joined(separator: " ").lowercased()
        return containsOneTimeCodeContext(recentContext)
    }

    func canInstall(_ release: XcodeRelease) -> Bool {
        let flags = releaseFlags(for: release.version, fallback: release)
        return !isBusy && !flags.isInstalled
    }

    func canSelect(_ release: XcodeRelease) -> Bool {
        let flags = releaseFlags(for: release.version, fallback: release)
        return !isBusy && flags.isInstalled && !flags.isSelected
    }

    func canUninstall(_ release: XcodeRelease) -> Bool {
        let flags = releaseFlags(for: release.version, fallback: release)
        return !isBusy && flags.isInstalled
    }

    func shouldShowInstallDetails(for version: String) -> Bool {
        installProgressVersion == version && (isInstalling || !installProgress.isEmpty)
    }

    func selectVersion(_ version: String) {
        selectedVersion = version
    }

    func install(version: String) async {
        selectedVersion = version
        await installSelected()
    }

    func select(version: String) async {
        selectedVersion = version
        await selectSelected()
    }

    func uninstall(version: String) async {
        selectedVersion = version
        await uninstallSelected()
    }

    func installSelected() async {
        guard let version = selectedVersion else {
            statusMessage = "Select a version from the list first."
            return
        }

        let activityID = activityCenter.begin(
            title: "Installing Xcode \(version)",
            detail: "Preparing installation...",
            source: "Xcodes"
        )
        let historyID = historyRecorder.start(
            feature: "Xcodes",
            command: "xcodes install \(version) --select",
            summary: "Installing Xcode \(version)."
        )
        activeInstallActivityID = activityID
        defer {
            activityCenter.finish(id: activityID)
            if activeInstallActivityID == activityID {
                activeInstallActivityID = nil
            }
        }

        isCancellingInstall = false
        isInstalling = true
        installProgress = []
        installProgressVersion = version
        installStartedAt = .now
        lastInstallOutputAt = nil
        lastHeartbeatLogAt = nil
        didShowLongSilenceHint = false
        installPromptHint = nil
        pendingInstallInput = ""
        isInstallInputSecure = false
        appendInstallProgress("Starting install for Xcode \(version).", isFromTool: false)
        appendInstallProgress(
            "If prompted for Apple ID or 2FA code, enter it below and press Send.",
            isFromTool: false
        )
        appendInstallProgress("For administrator access, macOS will show a native system prompt.", isFromTool: false)
        appendInstallProgress("Waiting for xcodes output...", isFromTool: false)
        startInstallHeartbeat(for: version)
        defer { isInstalling = false }

        statusMessage = "Installing Xcode \(version)..."
        do {
            let stream = try service.installWithProgress(
                version: version,
                selectAfterInstall: true,
                requiresAdministratorPrivileges: true
            )
            for try await line in stream {
                appendInstallProgress(line)
            }
            await load(force: true)
            selectedVersion = version
            statusMessage = "Installed and selected Xcode \(version)."
            historyRecorder.complete(
                id: historyID,
                status: .success,
                summary: "Installed and selected Xcode \(version).",
                exitCode: 0
            )
        } catch is CancellationError {
            appendInstallProgress("Install cancelled.", isFromTool: false)
            statusMessage = "Install cancelled for Xcode \(version)."
            historyRecorder.complete(
                id: historyID,
                status: .failed,
                summary: "Install cancelled for Xcode \(version).",
                exitCode: 1
            )
        } catch {
            if isCancellingInstall {
                appendInstallProgress("Install cancelled.", isFromTool: false)
                statusMessage = "Install cancelled for Xcode \(version)."
                historyRecorder.complete(
                    id: historyID,
                    status: .failed,
                    summary: "Install cancelled for Xcode \(version).",
                    exitCode: 1
                )
            } else {
                let message = singleLine(error.localizedDescription)
                statusMessage = "Install failed for Xcode \(version). \(message)"
                historyRecorder.complete(
                    id: historyID,
                    status: .failed,
                    summary: "Install failed for Xcode \(version). \(message)",
                    exitCode: 1
                )
            }
        }

        finishInstallHeartbeat()
    }

    func cancelInstall() {
        guard canCancelInstall else { return }
        isCancellingInstall = true
        appendInstallProgress("Cancelling install...", isFromTool: false)
        statusMessage = "Cancelling install..."
        if let activityID = activeInstallActivityID {
            activityCenter.update(id: activityID, detail: "Cancelling install...")
        }
        service.cancelInstall()
    }

    func signOut() async {
        guard !isBusy else { return }

        statusMessage = "Signing out from xcodes..."
        let historyID = historyRecorder.start(
            feature: "Xcodes",
            command: "xcodes signout",
            summary: "Signing out from xcodes."
        )
        do {
            try await service.signOut()
            statusMessage = "Signed out from xcodes."
            historyRecorder.complete(
                id: historyID,
                status: .success,
                summary: "Signed out from xcodes.",
                exitCode: 0
            )
        } catch {
            statusMessage = "Sign out failed. \(singleLine(error.localizedDescription))"
            historyRecorder.complete(
                id: historyID,
                status: .failed,
                summary: statusMessage,
                exitCode: 1
            )
        }
    }

    func sendInstallInput() {
        let text = pendingInstallInput.trimmingCharacters(in: .newlines)
        guard !text.isEmpty else { return }

        do {
            try service.sendInstallInput(text)
            let hint = installPromptHint?.lowercased() ?? ""
            if hint.contains("password") || isInstallInputSecure {
                appendInstallProgress("Sent password input.", isFromTool: false)
            } else if hint.contains("verification") || hint.contains("2fa") || hint.contains("code") {
                appendInstallProgress("Sent verification code.", isFromTool: false)
            } else {
                appendInstallProgress("Sent input to xcodes.", isFromTool: false)
            }
            pendingInstallInput = ""
        } catch {
            appendInstallProgress("Failed to send input: \(singleLine(error.localizedDescription))", isFromTool: false)
        }
    }

    func selectSelected() async {
        guard let version = selectedVersion else {
            statusMessage = "Select a version from the list first."
            return
        }

        statusMessage = "Selecting Xcode \(version)..."
        let historyID = historyRecorder.start(
            feature: "Xcodes",
            command: "xcodes select \(version)",
            summary: "Selecting Xcode \(version)."
        )
        do {
            try await service.select(versionOrPath: version)
            await load()
            selectedVersion = version
            statusMessage = "Selected Xcode \(version)."
            historyRecorder.complete(
                id: historyID,
                status: .success,
                summary: statusMessage,
                exitCode: 0
            )
        } catch {
            statusMessage = "Select failed for Xcode \(version). \(singleLine(error.localizedDescription))"
            historyRecorder.complete(
                id: historyID,
                status: .failed,
                summary: statusMessage,
                exitCode: 1
            )
        }
    }

    func uninstallSelected() async {
        guard let version = selectedVersion else {
            statusMessage = "Select a version from the list first."
            return
        }

        statusMessage = "Uninstalling Xcode \(version)..."
        let historyID = historyRecorder.start(
            feature: "Xcodes",
            command: "xcodes uninstall \(version) --empty-trash",
            summary: "Uninstalling Xcode \(version)."
        )
        do {
            try await service.uninstall(version: version, emptyTrash: true)
            await load()
            if selectedVersion == version {
                selectedVersion = available.first?.version
            }
            statusMessage = "Uninstalled Xcode \(version)."
            historyRecorder.complete(
                id: historyID,
                status: .success,
                summary: statusMessage,
                exitCode: 0
            )
        } catch {
            statusMessage = "Uninstall failed for Xcode \(version). \(singleLine(error.localizedDescription))"
            historyRecorder.complete(
                id: historyID,
                status: .failed,
                summary: statusMessage,
                exitCode: 1
            )
        }
    }

    private var selectedRelease: XcodeRelease? {
        guard let selectedVersion else { return nil }
        return available.first(where: { $0.version == selectedVersion })
    }

    private var selectedInstallation: XcodeInstallation? {
        guard let selectedVersion else { return nil }
        return installed.first(where: { $0.version == selectedVersion })
    }

    private var isSelectedVersionInstalled: Bool {
        if selectedInstallation != nil {
            return true
        }
        return selectedRelease?.isInstalled ?? false
    }

    private var isSelectedVersionActive: Bool {
        if selectedInstallation?.isSelected == true {
            return true
        }
        return selectedRelease?.isSelected ?? false
    }

    private func releaseFlags(for version: String, fallback: XcodeRelease? = nil) -> (isInstalled: Bool, isSelected: Bool) {
        let installedFlag = installed.contains(where: { $0.version == version })
            || fallback?.isInstalled == true
            || available.first(where: { $0.version == version })?.isInstalled == true
        let selectedFlag = installed.contains(where: { $0.version == version && $0.isSelected })
            || fallback?.isSelected == true
            || available.first(where: { $0.version == version })?.isSelected == true
        return (installedFlag, selectedFlag)
    }

    private func appendInstallProgress(_ line: String) {
        appendInstallProgress(line, isFromTool: true)
    }

    private func appendInstallProgress(_ line: String, isFromTool: Bool) {
        let cleaned = sanitizeProgressLine(line)
        guard !cleaned.isEmpty else { return }
        guard installProgress.last != cleaned else { return }

        if isFromTool {
            lastInstallOutputAt = .now
            if let promptHint = detectedPromptHint(from: cleaned) {
                installPromptHint = promptHint
                isInstallInputSecure = promptHint.lowercased().contains("password")
            }
        }

        installProgress.append(cleaned)
        if installProgress.count > 300 {
            installProgress.removeFirst(installProgress.count - 300)
        }

        if let activityID = activeInstallActivityID {
            activityCenter.update(id: activityID, detail: condensedProgressLine(cleaned))
        }

        statusMessage = cleaned
    }

    private func startInstallHeartbeat(for version: String) {
        installHeartbeatTask?.cancel()
        installHeartbeatTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.isInstalling {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard self.isInstalling else { break }
                guard let start = self.installStartedAt else { continue }

                let elapsed = Date().timeIntervalSince(start)
                let silentFor = Date().timeIntervalSince(self.lastInstallOutputAt ?? start)
                let elapsedLabel = Self.formatElapsed(elapsed)

                if silentFor >= 10 {
                    self.statusMessage = "Installing Xcode \(version)... \(elapsedLabel) elapsed (waiting for output)"
                }

                let now = Date()
                if silentFor >= 30 {
                    let shouldLog: Bool
                    if let lastHeartbeatLogAt = self.lastHeartbeatLogAt {
                        shouldLog = now.timeIntervalSince(lastHeartbeatLogAt) >= 30
                    } else {
                        shouldLog = true
                    }

                    if shouldLog {
                        self.lastHeartbeatLogAt = now
                        self.appendInstallProgress(
                            "Still running after \(elapsedLabel). xcodes has not emitted a new line yet.",
                            isFromTool: false
                        )
                    }
                }

                if silentFor >= 60 && !self.didShowLongSilenceHint {
                    self.didShowLongSilenceHint = true
                    self.appendInstallProgress(
                        "No output for over 60 seconds. xcodes might be downloading silently or waiting on authentication.",
                        isFromTool: false
                    )
                }
            }
        }
    }

    private func finishInstallHeartbeat() {
        installHeartbeatTask?.cancel()
        installHeartbeatTask = nil
        installStartedAt = nil
        lastInstallOutputAt = nil
        lastHeartbeatLogAt = nil
        didShowLongSilenceHint = false
        isCancellingInstall = false
        installPromptHint = nil
        pendingInstallInput = ""
        isInstallInputSecure = false
    }

    private func sanitizeProgressLine(_ line: String) -> String {
        let ansiPattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#
        let noANSI = line.replacingOccurrences(
            of: ansiPattern,
            with: "",
            options: .regularExpression
        )

        return noANSI
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func condensedProgressLine(_ line: String) -> String {
        let limit = 120
        guard line.count > limit else { return line }
        return "\(line.prefix(limit))..."
    }

    private static func formatElapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func detectedPromptHint(from line: String) -> String? {
        let lowered = line.lowercased()

        if lowered.contains("password") {
            return "Password"
        }

        if containsOneTimeCodeContext(lowered) {
            return "Verification Code"
        }

        if lowered.contains("apple id") && (lowered.contains(":") || lowered.contains("enter")) {
            return "Apple ID"
        }

        if lowered.hasSuffix(":") && lowered.count <= 80 {
            return line
        }
        return nil
    }

    private func containsOneTimeCodeContext(_ lowered: String) -> Bool {
        let hasCodeWord = lowered.range(of: #"\bcode\b"#, options: .regularExpression) != nil
        let hasPromptStyle = lowered.contains(":")
            || lowered.contains("enter")
            || lowered.contains("sent")
            || lowered.contains("device")
            || lowered.contains("receive")
            || lowered.contains("check")

        return lowered.contains("verification code")
            || lowered.contains("security code")
            || lowered.contains("one-time code")
            || lowered.contains("one time code")
            || lowered.contains("authenticator")
            || lowered.contains("two-factor")
            || lowered.contains("two factor")
            || lowered.contains("2fa")
            || lowered.contains("6-digit")
            || (hasCodeWord && hasPromptStyle)
    }

    private func singleLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
