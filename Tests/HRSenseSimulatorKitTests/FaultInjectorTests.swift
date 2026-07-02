import XCTest
@testable import HRSenseSimulatorKit
import Foundation

final class FaultInjectorTests: XCTestCase {

    func test_noFaults_passesThrough() {
        let injector = FaultInjector()
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let result = injector.apply(data)
        XCTAssertNotNil(result)
        XCTAssertEqual(result, data)
    }

    func test_fullDropDropsAll() {
        let injector = FaultInjector()
        injector.dropProbability = 1.0

        let data = Data([0x01, 0x02, 0x03])
        // With prob=1.0, every call should drop
        var allNil = true
        for _ in 0..<20 {
            if injector.apply(data) != nil {
                allNil = false
                break
            }
        }
        XCTAssertTrue(allNil, "With dropProbability=1.0, all should be nil")
    }

    func test_crcCorruption_changesData() {
        let injector = FaultInjector()
        injector.corruptCRCProbability = 1.0

        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let result = injector.apply(data)
        XCTAssertNotNil(result)
        // At least one byte past position 2 should have changed
        if let result = result {
            let orig = [UInt8](data)
            let res = [UInt8](result)
            let changed = zip(orig.dropFirst(2), res.dropFirst(2)).contains { $0 != $1 }
            XCTAssertTrue(changed, "At least one byte should be corrupted with prob=1.0")
        }
    }
}
