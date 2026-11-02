import AppKit
import Foundation

@MainActor
final class SimulatorAttachmentBootstrap {
    static let shared = SimulatorAttachmentBootstrap()

    private var didStart = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var startupTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?

    private init() {}

    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true

        registerWorkspaceObservers()

        startupTask = Task { [weak self] in
            await self?.performInitialRestoreAndSync()
        }
    }

    private func registerWorkspaceObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated { [weak self] in
                    guard let self else { return }
                    guard Self.isSimulatorNotification(notification) else { return }
                    self.scheduleAttachedSync()
                }
            }
        )

        workspaceObservers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated { [weak self] in
                    guard let self else { return }
                    guard Self.isSimulatorNotification(notification) else { return }
                    self.scheduleAttachedSync()
                }
            }
        )
    }

    private func performInitialRestoreAndSync() async {
        let viewModel = SimulatorViewModel.shared
        let restoredSimulators = await viewModel.restorePersistedAttachedSimulatorsOnAppLaunch()
        let restoredUDIDs = Set(restoredSimulators.map(\.udid))
        SimulatorActionsPanelManager.shared.synchronizeAttachedSimulators(
            restoredSimulators,
            viewModel: viewModel,
            preferredFramesByUDID: viewModel.attachedSimulatorFrames(for: restoredUDIDs)
        )

        // Simulator windows can appear late after app/login startup.
        for _ in 0 ..< 16 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await synchronizeAttachedSimulators()
        }
    }

    private func scheduleAttachedSync() {
        let viewModel = SimulatorViewModel.shared
        guard !viewModel.persistedAttachedSimulatorUDIDs.isEmpty else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            await self?.synchronizeAttachedSimulators()
        }
    }

    private func synchronizeAttachedSimulators() async {
        let viewModel = SimulatorViewModel.shared
        let attachedBootedSimulators = viewModel.simulators.filter { simulator in
            simulator.isBooted && viewModel.persistedAttachedSimulatorUDIDs.contains(simulator.udid)
        }
        let attachedBootedUDIDs = Set(attachedBootedSimulators.map(\.udid))
        SimulatorActionsPanelManager.shared.synchronizeAttachedSimulators(
            attachedBootedSimulators,
            viewModel: viewModel,
            preferredFramesByUDID: viewModel.attachedSimulatorFrames(for: attachedBootedUDIDs)
        )
    }

    private static func isSimulatorNotification(_ notification: Notification) -> Bool {
        guard let runningApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return false
        }
        return runningApplication.bundleIdentifier == "com.apple.iphonesimulator"
    }
}
