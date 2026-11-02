import Testing
@testable import XNox

struct XcodesOutputParserTests {
    @Test
    func parseInstalledDetectsSelectedAndSortsNewestFirst() {
        let output = """
        26.2 (17C52) (Selected)\t/Applications/Xcode.app
        16.4 (16F6)\t/Applications/Xcode-16.4.app
        """

        let installations = XcodesOutputParser.parseInstalled(output)

        #expect(installations.count == 2)
        #expect(installations.map(\.version) == ["26.2", "16.4"])
        #expect(installations[0].isSelected)
        #expect(installations[0].path == "/Applications/Xcode.app")
    }

    @Test
    func parseAvailableDetectsMarkersAndSortsNewestFirst() {
        let output = """
        15.4 (15F31d)
        16.3 Beta 2 (16E5200a)
        16.4 (16F6) (Installed)
        16.5 (16G80) (Selected)
        """

        let releases = XcodesOutputParser.parseAvailable(output)

        #expect(releases.map(\.version) == ["16.5", "16.4", "16.3 Beta 2", "15.4"])

        let selected = releases.first(where: { $0.version == "16.5" })
        #expect(selected?.isSelected == true)
        #expect(selected?.isInstalled == true)

        let installed = releases.first(where: { $0.version == "16.4" })
        #expect(installed?.isInstalled == true)
        #expect(installed?.isSelected == false)
    }

    @Test
    func parseAvailableHandlesCheckmarkAndReleaseCandidateVariants() {
        let output = """
        ✓ 16.6 Release Candidate (16G90) Installed
        * 16.5 (16G70) Selected
        """

        let releases = XcodesOutputParser.parseAvailable(output)

        #expect(releases.map(\.version) == ["16.6 Release Candidate", "16.5"])
        #expect(releases.first(where: { $0.version == "16.6 Release Candidate" })?.isInstalled == true)
        #expect(releases.first(where: { $0.version == "16.5" })?.isSelected == true)
    }

    @Test
    func mergeAvailableAddsInstalledOnlyVersions() {
        let available = [
            XcodeRelease(version: "16.5", isPrerelease: false),
        ]
        let installed = [
            XcodeInstallation(version: "16.4", path: "/Applications/Xcode-16.4.app", isSelected: false),
        ]

        let merged = XcodesOutputParser.mergedAvailableReleases(available: available, installed: installed)

        #expect(merged.map(\.version) == ["16.5", "16.4"])
        #expect(merged.first(where: { $0.version == "16.4" })?.isInstalled == true)
    }

    @Test
    func versionOrderingPrefersStableAndHigherPrereleaseNumbers() {
        #expect(XcodeVersionOrdering.isNewer("16.4", than: "16.4 Beta 2"))
        #expect(!XcodeVersionOrdering.isNewer("16.4 Beta 2", than: "16.4"))
        #expect(XcodeVersionOrdering.isNewer("16.5 Beta 3", than: "16.5 Beta 2"))
        #expect(XcodeVersionOrdering.isNewer("16.5", than: "16.4.1"))
    }
}
