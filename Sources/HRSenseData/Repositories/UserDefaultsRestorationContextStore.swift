import Foundation
import HRSenseCore

/// `UserDefaults`-backed storage for restoration eligibility.
///
/// This store keeps only the minimal identity negotiated after a successful
/// handshake so first launch naturally has no restore candidate.
public final class UserDefaultsRestorationContextStore: RestorationContextStore, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let storageKey = "com.hrsense.restoration-context"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load() -> RestorationContext? {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return nil
        }

        return try? decoder.decode(RestorationContext.self, from: data)
    }

    public func save(_ context: RestorationContext) {
        guard let data = try? encoder.encode(context) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }

    public func clear() {
        userDefaults.removeObject(forKey: storageKey)
    }
}
