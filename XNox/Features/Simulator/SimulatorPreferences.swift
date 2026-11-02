import Combine
import Foundation

/// Persists the simulator tool inputs (locale, URL, status bar) in `UserDefaults`.
/// The `simulator.*` key strings are user data on disk: do not rename them.
extension SimulatorViewModel {
    nonisolated static let localeIdentifierKey = "simulator.localeIdentifier"
    nonisolated static let urlToOpenKey = "simulator.urlToOpen"
    nonisolated static let statusBarTimeKey = "simulator.statusBar.time"
    nonisolated static let statusBarNetworkKey = "simulator.statusBar.network"
    nonisolated static let statusBarWifiBarsKey = "simulator.statusBar.wifiBars"
    nonisolated static let statusBarCellularBarsKey = "simulator.statusBar.cellularBars"
    nonisolated static let statusBarBatteryStateKey = "simulator.statusBar.batteryState"
    nonisolated static let statusBarBatteryLevelKey = "simulator.statusBar.batteryLevel"

    /// Restores saved values over the defaults; unset keys keep their defaults.
    func loadPersistedPreferences() {
        let defaults = UserDefaults.standard
        localeIdentifier = defaults.string(forKey: Self.localeIdentifierKey) ?? localeIdentifier
        urlToOpen = defaults.string(forKey: Self.urlToOpenKey) ?? urlToOpen
        statusBarTime = defaults.string(forKey: Self.statusBarTimeKey) ?? statusBarTime

        if let rawNetwork = defaults.string(forKey: Self.statusBarNetworkKey),
           let network = SimulatorStatusBarNetwork(rawValue: rawNetwork) {
            statusBarNetwork = network
        }

        if defaults.object(forKey: Self.statusBarWifiBarsKey) != nil {
            statusBarWifiBars = defaults.integer(forKey: Self.statusBarWifiBarsKey)
        }
        if defaults.object(forKey: Self.statusBarCellularBarsKey) != nil {
            statusBarCellularBars = defaults.integer(forKey: Self.statusBarCellularBarsKey)
        }

        if let rawBatteryState = defaults.string(forKey: Self.statusBarBatteryStateKey),
           let batteryState = SimulatorStatusBarBatteryState(rawValue: rawBatteryState) {
            statusBarBatteryState = batteryState
        }
        if defaults.object(forKey: Self.statusBarBatteryLevelKey) != nil {
            statusBarBatteryLevel = defaults.integer(forKey: Self.statusBarBatteryLevelKey)
        }
    }

    /// Writes every change of a persisted property back to `UserDefaults`.
    func configurePreferencePersistence() {
        $localeIdentifier
            .sink { UserDefaults.standard.set($0, forKey: Self.localeIdentifierKey) }
            .store(in: &cancellables)

        $urlToOpen
            .sink { UserDefaults.standard.set($0, forKey: Self.urlToOpenKey) }
            .store(in: &cancellables)

        $statusBarTime
            .sink { UserDefaults.standard.set($0, forKey: Self.statusBarTimeKey) }
            .store(in: &cancellables)

        $statusBarNetwork
            .sink { UserDefaults.standard.set($0.rawValue, forKey: Self.statusBarNetworkKey) }
            .store(in: &cancellables)

        $statusBarWifiBars
            .sink { UserDefaults.standard.set($0, forKey: Self.statusBarWifiBarsKey) }
            .store(in: &cancellables)

        $statusBarCellularBars
            .sink { UserDefaults.standard.set($0, forKey: Self.statusBarCellularBarsKey) }
            .store(in: &cancellables)

        $statusBarBatteryState
            .sink { UserDefaults.standard.set($0.rawValue, forKey: Self.statusBarBatteryStateKey) }
            .store(in: &cancellables)

        $statusBarBatteryLevel
            .sink { UserDefaults.standard.set($0, forKey: Self.statusBarBatteryLevelKey) }
            .store(in: &cancellables)
    }
}
