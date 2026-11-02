import Foundation
import Testing
@testable import XNox

/// Drives `SimulatorControlService` with a fake runner and temp directories only.
/// Nothing here may reach the real `simctl` or the real CoreSimulator directory.
@MainActor
struct SimulatorControlServiceTests {
    private let udid = "0A1B2C3D-4E5F-6789-ABCD-EF0123456789"

    private func makeService(
        _ runner: FakeCommandRunner,
        devicesDirectory: URL? = nil
    ) -> SimulatorControlService {
        SimulatorControlService(
            runner: runner,
            eraseBackoffMicroseconds: 0,
            devicesDirectory: devicesDirectory ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("xnox-sim-\(UUID().uuidString)", isDirectory: true)
        )
    }

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xnox-sim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func createPassesNameDeviceTypeAndRuntime() async throws {
        let runner = FakeCommandRunner { _, _ in "NEW-UDID\n" }
        let result = try await makeService(runner).createSimulator(
            name: "My Phone", deviceTypeIdentifier: "type.id", runtimeIdentifier: "runtime.id"
        )
        #expect(result == "NEW-UDID")
        #expect(runner.simctlCalls == [["create", "My Phone", "type.id", "runtime.id"]])
    }

    @Test func deleteShutsDownThenDeletes() async throws {
        let runner = FakeCommandRunner()
        try await makeService(runner).deleteSimulator(udid: udid)
        #expect(runner.simctlCalls == [["shutdown", udid], ["delete", udid]])
    }

    @Test func eraseRetriesThenThrowsWithoutDelete() async {
        let runner = FakeCommandRunner { _, args in
            if args.contains("erase") { throw CommandError.failed(command: "erase", message: "busy") }
            return ""
        }
        await #expect(throws: CommandError.self) {
            try await makeService(runner).eraseSimulator(udid: udid)
        }
        let calls = runner.simctlCalls
        #expect(calls.filter { $0.first == "erase" }.count == 6)
        #expect(!calls.contains { $0.first == "delete" })
    }

    @Test func eraseSucceedsOnFirstTry() async throws {
        let runner = FakeCommandRunner()
        try await makeService(runner).eraseSimulator(udid: udid)
        #expect(runner.simctlCalls == [["shutdown", udid], ["erase", udid]])
    }

    @Test func bootToleratesAlreadyBooted() async throws {
        let runner = FakeCommandRunner { _, args in
            if args.dropFirst().first == "boot" {
                throw CommandError.failed(command: "boot", message: "Unable to boot device in current state: Booted")
            }
            return ""
        }
        try await makeService(runner).bootSimulator(udid: udid)
        #expect(runner.simctlCalls.first == ["boot", udid])
        #expect(runner.simctlCalls.contains(["bootstatus", udid, "-b"]))
    }

    @Test func bootPropagatesOtherFailures() async {
        let runner = FakeCommandRunner { _, args in
            if args.dropFirst().first == "boot" { throw CommandError.failed(command: "boot", message: "nope") }
            return ""
        }
        await #expect(throws: CommandError.self) {
            try await makeService(runner).bootSimulator(udid: udid)
        }
    }

    @Test func setLocaleRunsDefaultsAndWritesPlistIntoTempDirectory() async throws {
        let devices = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: devices) }
        let runner = FakeCommandRunner()
        try await makeService(runner, devicesDirectory: devices)
            .setLocale(udid: udid, localeIdentifier: " de-DE ")

        let calls = runner.simctlCalls
        #expect(calls.contains(["spawn", udid, "defaults", "write", "NSGlobalDomain", "AppleLocale", "de_DE"]))
        #expect(calls.contains(["spawn", udid, "defaults", "write", "NSGlobalDomain", "AppleLanguages", "-array", "de"]))

        let plistURL = devices.appendingPathComponent("\(udid)/data/Library/Preferences/.GlobalPreferences.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["AppleLocale"] as? String == "de_DE")
        #expect(plist["AppleLanguages"] as? [String] == ["de"])
    }

    @Test func statusBarOverrideClearsThenAppliesWifiArguments() async throws {
        let runner = FakeCommandRunner()
        let config = SimulatorStatusBarOverrideConfig(
            time: "9:41", network: .wifi, wifiBars: 3, cellularBars: 4,
            batteryState: .charged, batteryLevel: 150
        )
        try await makeService(runner).overrideStatusBar(udid: udid, config: config)
        #expect(runner.simctlCalls == [
            ["status_bar", udid, "clear"],
            ["status_bar", udid, "override", "--time", "9:41", "--batteryState", "discharging",
             "--batteryLevel", "100", "--dataNetwork", "wifi", "--wifiMode", "active",
             "--wifiBars", "3", "--cellularMode", "notSupported", "--cellularBars", "0"],
        ])
    }

    @Test func statusBarClearArguments() async throws {
        let runner = FakeCommandRunner()
        try await makeService(runner).clearStatusBar(udid: udid)
        #expect(runner.simctlCalls == [["status_bar", udid, "clear"]])
    }

    @Test func invalidUDIDThrowsAndRunsNothing() async {
        let runner = FakeCommandRunner()
        let service = makeService(runner)
        let bad = "--all; rm"
        let config = SimulatorStatusBarOverrideConfig(
            time: "9:41", network: .wifi, wifiBars: 3, cellularBars: 4,
            batteryState: .charged, batteryLevel: 50
        )
        await #expect(throws: SimulatorControlError.self) { try await service.bootSimulator(udid: bad) }
        await #expect(throws: SimulatorControlError.self) { try await service.eraseSimulator(udid: bad) }
        await #expect(throws: SimulatorControlError.self) { try await service.deleteSimulator(udid: bad) }
        await #expect(throws: SimulatorControlError.self) { try await service.renameSimulator(udid: "all", name: "x") }
        await #expect(throws: SimulatorControlError.self) { try await service.setLocale(udid: bad, localeIdentifier: "en_US") }
        await #expect(throws: SimulatorControlError.self) { try await service.openURL(udid: bad, rawURL: "https://x") }
        await #expect(throws: SimulatorControlError.self) { try await service.addMedia(udid: bad, filePaths: ["/tmp/a.png"]) }
        await #expect(throws: SimulatorControlError.self) { try await service.overrideStatusBar(udid: bad, config: config) }
        await #expect(throws: SimulatorControlError.self) { try await service.clearStatusBar(udid: bad) }
        #expect(runner.calls.isEmpty)
    }

    @Test func loadCatalogParsesFixturesAndMarksMissingDeviceDirectory() async throws {
        let devices = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: devices) }
        try FileManager.default.createDirectory(
            at: devices.appendingPathComponent(udid), withIntermediateDirectories: true
        )
        let runtimeID = "com.apple.CoreSimulator.SimRuntime.iOS-18-0"
        let deviceUDID = udid
        let missing = "11111111-2222-3333-4444-555555555555"
        let runner = FakeCommandRunner { _, args in
            switch Array(args.dropFirst().prefix(3)) {
            case ["list", "runtimes", "--json"]:
                return #"{"runtimes":[{"identifier":"\#(runtimeID)","name":"iOS 18.0","version":"18.0","isAvailable":true}]}"#
            case ["list", "devicetypes", "--json"]:
                return #"{"devicetypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-16","name":"iPhone 16"}]}"#
            case ["list", "devices", "--json"]:
                return #"""
                {"devices":{"\#(runtimeID)":[
                  {"name":"iPhone 16","udid":"\#(deviceUDID)","state":"Booted","isAvailable":true,
                   "deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-16"},
                  {"name":"Ghost","udid":"\#(missing)","state":"Shutdown","isAvailable":true}
                ]}}
                """#
            default:
                return ""
            }
        }
        let catalog = try await makeService(runner, devicesDirectory: devices).loadCatalog()
        #expect(catalog.warnings.isEmpty)
        #expect(catalog.runtimes.map(\.identifier) == [runtimeID])
        #expect(catalog.deviceTypes.map(\.name) == ["iPhone 16"])
        #expect(catalog.simulators.map(\.name) == ["iPhone 16", "Ghost"])
        #expect(catalog.simulators[0].isAvailable && catalog.simulators[0].isBooted)
        #expect(!catalog.simulators[1].isAvailable)
        #expect(catalog.simulators[1].availabilityIssue == "Device files are missing")
    }
}
