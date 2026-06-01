import Foundation
import GRDB

extension FontMetadataIssues: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}".databaseValue
        }
        return json.databaseValue
    }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> FontMetadataIssues? {
        guard let json = String.fromDatabaseValue(dbValue), !json.isEmpty else {
            return .empty
        }
        guard let data = json.data(using: .utf8) else { return .empty }
        return (try? JSONDecoder().decode(FontMetadataIssues.self, from: data)) ?? .empty
    }
}
