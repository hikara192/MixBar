import Foundation

/// Settings persistence (ADR-006): UserDefaults, bundle-ID keyed, schema
/// versioned, writes debounced 500 ms.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "mixbar.settings.v1"
    private let lock = NSLock()
    private var settings: [String: AppSetting] = [:]
    private var flushTask: Task<Void, Never>?
    private let schemaVersion = 1

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let schema = try? JSONDecoder().decode(SettingsSchema.self, from: data),
           schema.version == schemaVersion {
            settings = Dictionary(uniqueKeysWithValues: schema.apps.map { ($0.bundleID, $0) })
        }
        // Migration hook: older versions land here and are re-encoded on
        // first flush (fitness function 6: schema changes bump `version`).
    }

    public func desiredState() -> [AppIdentity: DesiredApp] {
        lock.lock(); defer { lock.unlock() }
        return Dictionary(uniqueKeysWithValues:
            settings.map { (AppIdentity(canonicalBundleID: $0.key), $0.value.desired) })
    }

    public func setting(for identity: AppIdentity) -> AppSetting? {
        lock.lock(); defer { lock.unlock() }
        return settings[identity.canonicalBundleID]
    }

    public func setGain(_ identity: AppIdentity, _ gain: Float) {
        mutate(identity) { $0.gain = max(0, min(1, gain)) }
    }

    public func setMuted(_ identity: AppIdentity, _ muted: Bool) {
        mutate(identity) { $0.muted = muted }
    }

    public func setAllAppsGain(_ identities: [AppIdentity], _ gain: Float) {
        for id in identities { setGain(id, gain) }
    }

    /// Writes pending changes immediately (tests, shutdown).
    public func flushNow() {
        lock.lock()
        let snapshot = settings
        flushTask?.cancel()
        flushTask = nil
        lock.unlock()
        let schema = SettingsSchema(version: schemaVersion, apps: snapshot.values.sorted { $0.bundleID < $1.bundleID })
        if let data = try? JSONEncoder().encode(schema) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: - Private

    private func mutate(_ identity: AppIdentity, _ change: (inout AppSetting) -> Void) {
        lock.lock()
        var setting = settings[identity.canonicalBundleID]
            ?? AppSetting(bundleID: identity.canonicalBundleID)
        change(&setting)
        if setting.remember {
            settings[identity.canonicalBundleID] = setting
        }
        flushTask?.cancel()
        let debounce: Duration = .milliseconds(500)
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.flushNow()
        }
        lock.unlock()
    }
}
