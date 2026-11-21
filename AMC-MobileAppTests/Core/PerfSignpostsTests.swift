import Foundation
import Testing
@testable import AMC_MobileApp

struct PerfSignpostsTests {
    private struct Boom: Error, Equatable {}

    @Test func measureReturnsTheBodyValue() async throws {
        let sync = PerfSignposts.measure("test.sync") { 21 * 2 }
        #expect(sync == 42)
        let async = try await PerfSignposts.measure("test.async") { () async throws -> String in
            try await Task.sleep(for: .milliseconds(1))
            return "ok"
        }
        #expect(async == "ok")
    }

    @Test func measurePropagatesTheError() async {
        #expect(throws: Boom.self) {
            try PerfSignposts.measure("test.syncError") { () throws -> Int in throw Boom() }
        }
        await #expect(throws: Boom.self) {
            try await PerfSignposts.measure("test.asyncError") { () async throws -> Int in throw Boom() }
        }
    }

    @Test func intervalEndsOnlyOnce() {
        let interval = PerfSignposts.begin("test.interval")
        let first = interval.end()
        #expect(interval.end() == nil)
        // En Debug (tests), la mesure est active : la première fin renvoie une durée.
        #expect(PerfSignposts.isEnabled == (first != nil))
    }

    @Test func millisecondsConvertsDurations() {
        #expect(PerfSignposts.milliseconds(.milliseconds(1_250)) == 1_250)
        #expect(PerfSignposts.milliseconds(.microseconds(500)) == 0.5)
    }

    @Test func processStartDateIsInThePast() throws {
        let start = try #require(PerfSignposts.processStartDate())
        #expect(start <= .now)
    }
}
