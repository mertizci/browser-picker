import Foundation
import SQLite3

enum FirefoxProfileGroupReader {
    private static var profileGroupsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/Profile Groups")
    }

    /// Maps relative profile paths (e.g. `Profiles/foo.default-release`) to user-visible names.
    static func selectableProfileNames() -> [String: String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: profileGroupsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var names: [String: String] = [:]
        for file in files where file.pathExtension == "sqlite" {
            let fromDatabase = readNames(from: file.path)
            for (path, name) in fromDatabase where names[path] == nil {
                names[path] = name
            }
        }
        return names
    }

    private static func readNames(from databasePath: String) -> [String: String] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { return [:] }
        defer { sqlite3_close(database) }

        let query = "SELECT path, name FROM Profiles"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [:] }
        defer { sqlite3_finalize(statement) }

        var names: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pathPointer = sqlite3_column_text(statement, 0),
                  let namePointer = sqlite3_column_text(statement, 1) else { continue }
            let path = String(cString: pathPointer)
            let name = String(cString: namePointer)
            names[path] = name
        }
        return names
    }
}
