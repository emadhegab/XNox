import Testing
@testable import XNox

/// The `simulator.*` keys are persisted user data; renaming one silently resets users' settings.
struct SimulatorPreferenceKeyTests {
    @Test func keyStringsAreStable() {
        #expect(SimulatorViewModel.localeIdentifierKey == "simulator.localeIdentifier")
        #expect(SimulatorViewModel.urlToOpenKey == "simulator.urlToOpen")
        #expect(SimulatorViewModel.statusBarTimeKey == "simulator.statusBar.time")
        #expect(SimulatorViewModel.statusBarNetworkKey == "simulator.statusBar.network")
        #expect(SimulatorViewModel.statusBarWifiBarsKey == "simulator.statusBar.wifiBars")
        #expect(SimulatorViewModel.statusBarCellularBarsKey == "simulator.statusBar.cellularBars")
        #expect(SimulatorViewModel.statusBarBatteryStateKey == "simulator.statusBar.batteryState")
        #expect(SimulatorViewModel.statusBarBatteryLevelKey == "simulator.statusBar.batteryLevel")
    }
}
