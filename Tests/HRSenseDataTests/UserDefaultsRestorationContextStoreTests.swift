import XCTest
@testable import HRSenseCore
@testable import HRSenseData

final class UserDefaultsRestorationContextStoreTests: XCTestCase {
    func test_load_returnsNilWhenNoContextSaved() {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        let store = UserDefaultsRestorationContextStore(userDefaults: userDefaults)

        XCTAssertNil(store.load())
    }

    func test_saveAndLoad_roundTripsContext() {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        let store = UserDefaultsRestorationContextStore(userDefaults: userDefaults)
        let context = RestorationContext(
            peripheralIdentifier: UUID(),
            model: "M2",
            protocolVersion: 2,
            capabilities: 0xA5,
            lastSuccessfulHandshakeAt: Date(timeIntervalSince1970: 1_720_000_000)
        )

        store.save(context)

        XCTAssertEqual(store.load(), context)
    }

    func test_clear_removesPersistedContext() {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        let store = UserDefaultsRestorationContextStore(userDefaults: userDefaults)
        let context = RestorationContext(
            peripheralIdentifier: UUID(),
            model: "M2",
            protocolVersion: 2,
            capabilities: 0xA5,
            lastSuccessfulHandshakeAt: Date()
        )

        store.save(context)
        store.clear()

        XCTAssertNil(store.load())
    }
}
