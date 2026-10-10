import Foundation
import XCTest
@testable import HikariCore

final class PlaybackItemHealthTests: XCTestCase {
    func testPersistentMissingItemRecoversAfterGracePeriod() {
        var health = PlaybackItemHealth()
        let start = Date(timeIntervalSince1970: 100)

        XCTAssertFalse(health.needsRecovery(hasItem: false, itemFailed: false, now: start))
        XCTAssertFalse(health.needsRecovery(hasItem: false, itemFailed: false, now: start.addingTimeInterval(4)))
        XCTAssertTrue(health.needsRecovery(hasItem: false, itemFailed: false, now: start.addingTimeInterval(5)))
    }

    func testItemReturnClearsMissingInterval() {
        var health = PlaybackItemHealth()
        let start = Date(timeIntervalSince1970: 100)

        XCTAssertFalse(health.needsRecovery(hasItem: false, itemFailed: false, now: start))
        XCTAssertFalse(health.needsRecovery(hasItem: true, itemFailed: false, now: start.addingTimeInterval(4)))
        XCTAssertFalse(health.needsRecovery(hasItem: false, itemFailed: false, now: start.addingTimeInterval(10)))
        XCTAssertTrue(health.needsRecovery(hasItem: false, itemFailed: false, now: start.addingTimeInterval(15)))
    }

    func testFailedItemRecoversImmediately() {
        var health = PlaybackItemHealth()
        XCTAssertTrue(health.needsRecovery(hasItem: true, itemFailed: true, now: Date()))
    }
}
