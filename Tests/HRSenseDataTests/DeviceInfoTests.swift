import XCTest
@testable import HRSenseCore

final class DeviceInfoTests: XCTestCase {
    func test_init() {
        let id = UUID()
        let info = DeviceInfo(
            peripheralIdentifier: id, name: "Test", model: "M1",
            firmwareVersion: "1.0", protocolVersion: 1, capabilities: 0x2F
        )
        XCTAssertEqual(info.peripheralIdentifier, id)
        XCTAssertEqual(info.name, "Test")
        XCTAssertEqual(info.model, "M1")
        XCTAssertEqual(info.protocolVersion, 1)
    }
}
