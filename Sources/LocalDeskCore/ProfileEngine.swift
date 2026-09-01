import Foundation

public struct ProfileEngine {
    public init() {}

    public func matchingProfile(
        bundleIdentifier: String?,
        configuration: LocalDeskConfiguration
    ) -> Profile? {
        guard configuration.automaticSwitchingEnabled else { return nil }
        if let bundleIdentifier,
           let match = configuration.profiles.first(where: {
               $0.isEnabled && $0.bundleIdentifiers.contains(bundleIdentifier)
           }) {
            return match
        }
        guard let defaultProfileID = configuration.defaultProfileID else { return nil }
        return configuration.profiles.first(where: { $0.id == defaultProfileID && $0.isEnabled })
    }
}
