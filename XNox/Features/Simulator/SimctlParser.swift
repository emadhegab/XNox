import Foundation

/// Pure parsing helpers for `xcrun simctl` output and CoreSimulator plists.
/// Kept stateless so they can be unit-tested with small fixtures.
nonisolated enum SimctlParser {
    /// `device.plist` keys that may hold the last-booted/used timestamp, in priority order.
    static let lastUsedKeys = [
        "lastBootedAt",
        "lastBootedDate",
        "lastUsedAt",
    ]

    static func readableRuntimeName(from runtimeIdentifier: String) -> String {
        runtimeIdentifier
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }

    static func readableDeviceTypeName(from identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimDeviceType.", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }

    static func parseRootJSONDictionary(from output: String, label: String) throws -> [String: Any] {
        guard let data = output.data(using: .utf8) else {
            throw SimulatorControlError.invalidJSON("simctl \(label) output is not UTF-8")
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw SimulatorControlError.invalidJSON(error.localizedDescription)
        }

        guard let root = jsonObject as? [String: Any] else {
            throw SimulatorControlError.invalidJSON("simctl \(label) JSON root is not an object")
        }

        return root
    }

    static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    static func boolValue(_ value: Any?) -> Bool? {
        if let boolean = value as? Bool {
            return boolean
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = Self.stringValue(value) {
            switch string.lowercased() {
            case "1", "true", "yes", "available":
                return true
            case "0", "false", "no", "unavailable":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    static func dictionaryValue(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func arrayValue(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    static func availabilityFlag(from payload: [String: Any]) -> Bool {
        if let explicitAvailability = Self.boolValue(payload["isAvailable"]) {
            return explicitAvailability
        }

        if let availability = Self.stringValue(payload["availability"]) {
            let normalized = availability.lowercased()
            if normalized.contains("unavailable") || normalized.contains("not available") {
                return false
            }
            if normalized.contains("available") {
                return true
            }
        }

        if let availabilityError = Self.stringValue(payload["availabilityError"]) {
            return availabilityError.isEmpty
        }

        return true
    }

    static func availabilityDetails(from payload: [String: Any]) -> (isAvailable: Bool, issue: String?) {
        let isAvailable = Self.availabilityFlag(from: payload)
        guard !isAvailable else {
            return (true, nil)
        }

        if let availabilityError = Self.stringValue(payload["availabilityError"]), !availabilityError.isEmpty {
            return (false, availabilityError)
        }

        if let availability = Self.stringValue(payload["availability"]), !availability.isEmpty {
            return (false, availability)
        }

        return (false, "Unavailable in CoreSimulator")
    }

    static func simulatorLastUsedDate(from plistDictionary: [String: Any]) -> Date? {
        for key in lastUsedKeys {
            guard let rawValue = plistDictionary[key] else {
                continue
            }
            if let parsedDate = Self.parseDate(fromPlistValue: rawValue) {
                return parsedDate
            }
        }
        return nil
    }

    static func parseDate(fromPlistValue value: Any) -> Date? {
        if let date = value as? Date {
            return date
        }
        if let stringValue = value as? String {
            let isoWithFraction = ISO8601DateFormatter()
            isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoWithFraction.date(from: stringValue) {
                return date
            }

            let isoBasic = ISO8601DateFormatter()
            isoBasic.formatOptions = [.withInternetDateTime]
            if let date = isoBasic.date(from: stringValue) {
                return date
            }
        }
        if let timestamp = value as? TimeInterval, timestamp > 0 {
            let seconds = timestamp > 4_102_444_800 ? (timestamp / 1_000) : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        if let number = value as? NSNumber {
            let timestamp = number.doubleValue
            guard timestamp > 0 else { return nil }
            let seconds = timestamp > 4_102_444_800 ? (timestamp / 1_000) : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    static func uniqueRuntimes(_ runtimes: [SimulatorRuntime]) -> [SimulatorRuntime] {
        var seenIdentifiers = Set<String>()
        return runtimes.filter { runtime in
            seenIdentifiers.insert(runtime.identifier).inserted
        }
    }

    static func parseRuntimesFromPlainList(_ output: String) -> [SimulatorRuntime] {
        let parsedRuntimes = output
            .split(separator: "\n")
            .compactMap { line -> SimulatorRuntime? in
                let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.contains("SimRuntime."),
                      let identifierStart = text.range(of: "com.apple.CoreSimulator.SimRuntime.") else {
                    return nil
                }

                let identifier = String(text[identifierStart.lowerBound...])
                    .split(separator: " ")
                    .first
                    .map(String.init) ?? ""
                guard !identifier.isEmpty else { return nil }

                let name = text.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? Self.readableRuntimeName(from: identifier)
                let isAvailable = !text.localizedCaseInsensitiveContains("unavailable")

                return SimulatorRuntime(
                    identifier: identifier,
                    name: name,
                    version: nil,
                    isAvailable: isAvailable
                )
            }
        return Self.uniqueRuntimes(parsedRuntimes)
            .filter(\.isAvailable)
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            }
    }

    static func parseDeviceTypesFromPlainList(_ output: String) -> [SimulatorDeviceType] {
        var seenIdentifiers = Set<String>()

        return output
            .split(separator: "\n")
            .compactMap { line in
                let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.contains("SimDeviceType."),
                      let identifierStart = text.range(of: "com.apple.CoreSimulator.SimDeviceType.") else {
                    return nil
                }

                let identifier = String(text[identifierStart.lowerBound...])
                    .split(separator: ")")
                    .first
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                guard !identifier.isEmpty,
                      seenIdentifiers.insert(identifier).inserted else {
                    return nil
                }

                let name = text.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? Self.readableDeviceTypeName(from: identifier)

                return SimulatorDeviceType(identifier: identifier, name: name)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}
