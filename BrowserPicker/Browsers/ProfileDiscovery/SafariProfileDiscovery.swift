import Foundation

struct SafariProfileDiscovery: ProfileDiscovery {
    let browser: BrowserKind = .safari

    func discoverProfiles() -> [BrowserProfile] {
        guard FileManager.default.fileExists(atPath: browser.appPath) else { return [] }

        var recordsByID: [String: SafariProfileRecord] = [:]

        for record in SafariProfileStore.discoverProfiles() {
            recordsByID[record.id] = record
        }

        // Only read Safari's menu when Safari is already running — never launch it.
        if SafariRuntime.isRunning {
            for record in SafariMenuProfileScanner.discoverProfiles() {
                recordsByID[record.id] = record
            }
        }

        if recordsByID.isEmpty {
            recordsByID[SafariProfileRecord.defaultID] = defaultRecord()
        }

        return recordsByID.values
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { record in
                BrowserProfile(
                    id: record.id,
                    displayName: record.displayName,
                    browser: .safari,
                    profilePath: record.id,
                    internalName: record.menuName
                )
            }
    }

    private func defaultRecord() -> SafariProfileRecord {
        SafariProfileRecord(
            id: SafariProfileRecord.defaultID,
            displayName: "Personal",
            menuName: "Personal"
        )
    }
}
