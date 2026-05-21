import Testing
import Foundation
@testable import Compose

@Suite("SentSessionLog")
@MainActor
struct SentSessionLogTests {

    @Test
    func appendInsertsAtFront() {
        let log = SentSessionLog()
        log.append(uri: "a", body: "first")
        log.append(uri: "b", body: "second")

        #expect(log.entries.count == 2)
        #expect(log.entries[0].uri == "b")
        #expect(log.entries[1].uri == "a")
    }

    @Test
    func previewIsTrimmedToEightyCharsAndSingleLine() {
        let log = SentSessionLog()
        let body = String(repeating: "x", count: 100) + "\nignored"
        log.append(uri: "u", body: body)

        let preview = log.entries[0].preview
        #expect(preview.count == 80)
        #expect(preview.contains("\n") == false)
    }

    @Test
    func capDropsOldest() {
        let log = SentSessionLog()
        for i in 1...51 {
            log.append(uri: "u\(i)", body: "body \(i)")
        }
        #expect(log.entries.count == 50)
        #expect(log.entries.first?.uri == "u51")
        #expect(log.entries.last?.uri == "u2")
    }
}
