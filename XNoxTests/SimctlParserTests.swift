import Foundation
import Testing
@testable import XNox

/// Fixture-based checks for the stateless simctl parsing helpers.
struct SimctlParserTests {
    @Test func rootJSONRejectsNonObjectAndGarbage() {
        #expect(throws: SimulatorControlError.self) { try SimctlParser.parseRootJSONDictionary(from: "[1]", label: "x") }
        #expect(throws: SimulatorControlError.self) { try SimctlParser.parseRootJSONDictionary(from: "nope", label: "x") }
        #expect((try? SimctlParser.parseRootJSONDictionary(from: #"{"a":1}"#, label: "x"))?["a"] as? Int == 1)
    }

    @Test func availabilityFlagAndDetails() {
        #expect(SimctlParser.availabilityFlag(from: ["isAvailable": true]))
        #expect(!SimctlParser.availabilityFlag(from: ["isAvailable": "no"]))
        #expect(!SimctlParser.availabilityFlag(from: ["availability": "(unavailable, runtime profile not found)"]))
        #expect(SimctlParser.availabilityFlag(from: [:]))
        let details = SimctlParser.availabilityDetails(from: ["isAvailable": false, "availabilityError": "broken"])
        #expect(!details.isAvailable && details.issue == "broken")
        #expect(SimctlParser.availabilityDetails(from: ["isAvailable": false]).issue == "Unavailable in CoreSimulator")
    }

    @Test func plainRuntimeListSkipsUnavailableAndSortsDescending() {
        let output = """
        == Runtimes ==
        iOS 17.5 (17.5 - 21F79) - com.apple.CoreSimulator.SimRuntime.iOS-17-5
        iOS 18.0 (18.0 - 22A3351) - com.apple.CoreSimulator.SimRuntime.iOS-18-0
        iOS 16.0 (16.0 - 20A360) - com.apple.CoreSimulator.SimRuntime.iOS-16-0 (unavailable, gone)
        """
        let runtimes = SimctlParser.parseRuntimesFromPlainList(output)
        #expect(runtimes.map(\.name) == ["iOS 18.0", "iOS 17.5"])
        #expect(runtimes.first?.identifier == "com.apple.CoreSimulator.SimRuntime.iOS-18-0")
    }

    @Test func plainDeviceTypeListDedupesAndSortsAscending() {
        let output = """
        == Device Types ==
        iPhone 16 (com.apple.CoreSimulator.SimDeviceType.iPhone-16)
        iPad Air (com.apple.CoreSimulator.SimDeviceType.iPad-Air)
        iPhone 16 (com.apple.CoreSimulator.SimDeviceType.iPhone-16)
        """
        let types = SimctlParser.parseDeviceTypesFromPlainList(output)
        #expect(types.map(\.name) == ["iPad Air", "iPhone 16"])
        #expect(types.last?.identifier == "com.apple.CoreSimulator.SimDeviceType.iPhone-16")
    }

    @Test func readableNamesStripPrefix() {
        #expect(SimctlParser.readableRuntimeName(from: "com.apple.CoreSimulator.SimRuntime.iOS-18-0") == "iOS 18 0")
        #expect(SimctlParser.readableDeviceTypeName(from: "com.apple.CoreSimulator.SimDeviceType.iPhone-16") == "iPhone 16")
    }

    @Test func lastUsedDateParsesISOAndEpoch() {
        let iso = SimctlParser.simulatorLastUsedDate(from: ["lastBootedAt": "2024-01-02T03:04:05Z"])
        #expect(iso == Date(timeIntervalSince1970: 1_704_164_645))
        #expect(SimctlParser.simulatorLastUsedDate(from: ["lastUsedAt": 1_704_164_645_000.0]) == Date(timeIntervalSince1970: 1_704_164_645))
        #expect(SimctlParser.simulatorLastUsedDate(from: ["other": 1]) == nil)
    }
}
