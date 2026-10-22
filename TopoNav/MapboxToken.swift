import Foundation

/// Reads the Mapbox access token that the build injects into Info.plist
/// from `Config/Secrets.xcconfig`.
enum MapboxToken {
    static let placeholder = "YOUR_MAPBOX_ACCESS_TOKEN"

    static var value: String? {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String else {
            return nil
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unresolved build variable or the example placeholder means it was never set.
        guard !trimmed.isEmpty, trimmed != placeholder, !trimmed.hasPrefix("$(") else {
            return nil
        }
        return trimmed
    }

    static var isConfigured: Bool { value != nil }
}
