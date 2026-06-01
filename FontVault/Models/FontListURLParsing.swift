import Foundation

enum FontListURLParsing {
  /// Returns a URL when `string` is an absolute http/https link.
  static func validHTTPURL(from string: String) -> URL? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard let url = URL(string: trimmed),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else { return nil }
    return url
  }
}

extension FontListColumn {
  var isWebURLColumn: Bool {
    switch self {
    case .licenseURL, .manufacturerURL, .designerURL:
      return true
    default:
      return false
    }
  }
}
