import Testing
@testable import XNox

struct StorageConfirmMessageTests {
    @Test func locationShowsPathAndSize() {
        let text = StorageConfirmMessage.location(pathLabel: "~/Library/Developer/Xcode/DerivedData", bytes: 2_000_000)
        #expect(text.contains("~/Library/Developer/Xcode/DerivedData"))
        #expect(text.contains(StorageViewModel.byteString(from: 2_000_000)))
    }

    @Test func deleteAllListsEveryLocationAndTotal() {
        let text = StorageConfirmMessage.deleteAll(
            locations: [("~/a", 1_000_000), ("~/b", 3_000_000)],
            totalBytes: 4_000_000
        )
        #expect(text.contains("~/a: \(StorageViewModel.byteString(from: 1_000_000))"))
        #expect(text.contains("~/b: \(StorageViewModel.byteString(from: 3_000_000))"))
        #expect(text.contains("Total: \(StorageViewModel.byteString(from: 4_000_000))"))
    }

    @Test func browserListsAllNamesWhenAtOrUnderCap() {
        let names = (1 ... 5).map { "item\($0)" }
        let text = StorageConfirmMessage.browser(names: names, totalBytes: 10_000_000)
        for name in names { #expect(text.contains(name)) }
        #expect(!text.contains("more"))
    }

    @Test func browserCapsNamesAndCountsRemainder() {
        let names = (1 ... 8).map { "item\($0)" }
        let text = StorageConfirmMessage.browser(names: names, totalBytes: 10_000_000)
        #expect(text.contains("item5"))
        #expect(!text.contains("item6"))
        #expect(text.contains("and 3 more"))
        #expect(text.contains(StorageViewModel.byteString(from: 10_000_000)))
    }
}
