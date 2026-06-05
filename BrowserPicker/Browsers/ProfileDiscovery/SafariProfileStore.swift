import Foundation
import SQLite3

struct SafariProfileRecord {
    static let defaultID = "DefaultProfile"

    let id: String
    let displayName: String
    let menuName: String
}

enum SafariProfileStore {
    private static let defaultProfileID = SafariProfileRecord.defaultID
    private static let defaultMenuName = "Personal"

    private static var databaseCandidates: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db"),
            home.appendingPathComponent("Library/Safari/SafariTabs.db")
        ]
    }

    static var canReadDatabase: Bool {
        for url in databaseCandidates {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            var database: OpaquePointer?
            let openResult = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
            defer {
                if let database {
                    sqlite3_close(database)
                }
            }

            guard openResult == SQLITE_OK, database != nil else { continue }

            var statement: OpaquePointer?
            let prepareResult = sqlite3_prepare_v2(
                database,
                "SELECT 1 FROM bookmarks LIMIT 1",
                -1,
                &statement,
                nil
            )
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }

            if prepareResult == SQLITE_OK {
                return true
            }
        }
        return false
    }

    static func discoverProfiles() -> [SafariProfileRecord] {
        for url in databaseCandidates where FileManager.default.isReadableFile(atPath: url.path) {
            let profiles = readProfiles(from: url.path)
            if !profiles.isEmpty { return profiles }
        }
        return []
    }

    private static func readProfiles(from path: String) -> [SafariProfileRecord] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { return [] }
        defer { sqlite3_close(database) }

        let query = """
            SELECT title, external_uuid
            FROM bookmarks
            WHERE type = 1 AND subtype = 2
            ORDER BY title
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        var profiles: [SafariProfileRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let uuidPointer = sqlite3_column_text(statement, 1) else { continue }
            let uuid = String(cString: uuidPointer)
            let title: String
            if let titlePointer = sqlite3_column_text(statement, 0) {
                title = String(cString: titlePointer)
            } else {
                title = ""
            }

            let record = profileRecord(title: title, uuid: uuid)
            profiles.append(record)
        }

        if profiles.isEmpty {
            return [defaultProfileRecord()]
        }

        return profiles.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private static func profileRecord(title: String, uuid: String) -> SafariProfileRecord {
        if uuid == defaultProfileID || title.isEmpty {
            return SafariProfileRecord(
                id: defaultProfileID,
                displayName: defaultMenuName,
                menuName: defaultMenuName
            )
        }

        return SafariProfileRecord(
            id: uuid,
            displayName: title,
            menuName: title
        )
    }

    private static func defaultProfileRecord() -> SafariProfileRecord {
        SafariProfileRecord(
            id: defaultProfileID,
            displayName: defaultMenuName,
            menuName: defaultMenuName
        )
    }
}
