import Foundation
import XCTest

@MainActor
extension XCTestCase {
    /// Polls until the supplied condition becomes true or times out.
    func assertEventually(
        timeout: TimeInterval = 2,
        pollInterval: TimeInterval = 0.02,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        XCTFail("Condition was not satisfied within \(timeout) seconds.", file: file, line: line)
    }
}
