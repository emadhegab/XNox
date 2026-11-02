import Testing
@testable import XNox

/// Pure-function checks for the "Simulators unavailable" empty state; never runs simctl.
struct SimulatorLoadErrorTests {
    @Test func warningWithNoDevicesIsAnError() {
        let error = SimulatorViewModel.loadError(warnings: ["Simulators unavailable: boom"], simulatorCount: 0)
        #expect(error == "Simulators unavailable: boom")
    }

    @Test func warningWithDevicesIsNotAnError() {
        #expect(SimulatorViewModel.loadError(warnings: ["Runtimes unavailable: x"], simulatorCount: 2) == nil)
    }

    @Test func noWarningIsNotAnError() {
        #expect(SimulatorViewModel.loadError(warnings: [], simulatorCount: 0) == nil)
    }
}
