import Foundation

/// Microsoft registered vendor names for OS/2 `achVendID` values.
/// https://learn.microsoft.com/en-us/typography/vendors/
enum FontVendorRegistry {
    private static let byID: [String: String] = loadRegistry()

    static func registeredName(forVendorID vendorID: String) -> String? {
        let id = vendorID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return nil }
        return byID[id] ?? byID[id.uppercased()]
    }

    private static func loadRegistry() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "FontVendorRegistry", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
