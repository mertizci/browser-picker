import AppKit

struct InstalledApplication: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL

    init?(url: URL) {
        guard url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier, !identifier.isEmpty else { return nil }
        guard bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool != true,
              !url.deletingLastPathComponent().pathComponents.contains(where: { $0.hasSuffix(".app") }) else { return nil }
        // System implementation helpers are not apps users can choose as link sources.
        if url.path.hasPrefix("/System/Library/"),
           !url.path.hasPrefix("/System/Library/CoreServices/Applications/"),
           identifier != "com.apple.finder" { return nil }
        id = identifier
        name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        self.url = url
    }

    func matches(search: String) -> Bool {
        let terms = search.split(whereSeparator: \.isWhitespace)
        return terms.allSatisfy { term in
            name.localizedStandardContains(String(term)) || id.localizedStandardContains(String(term))
        }
    }
}

@MainActor
final class ApplicationCatalog: ObservableObject {
    static let shared = ApplicationCatalog()
    @Published private(set) var applications: [InstalledApplication] = []
    @Published private(set) var isLoading = false

    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private var scanned: [InstalledApplication] = []
    private var indexed: [InstalledApplication] = []

    func refresh() {
        if observers.isEmpty {
            query.predicate = NSPredicate(format: "kMDItemContentType == %@", "com.apple.application-bundle")
            query.searchScopes = [NSMetadataQueryLocalComputerScope]
            for notification in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
                observers.append(NotificationCenter.default.addObserver(forName: notification, object: query, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.readIndex() }
                })
            }
            query.start()
        }
        guard !isLoading else { return }
        isLoading = true
        // Scan standard folders too, so choosing apps works when Spotlight indexing is disabled.
        Task {
            let found = await Task.detached(priority: .userInitiated) { Self.scanStandardFolders() }.value
            scanned = found
            mergeApplications()
            isLoading = false
        }
    }

    private func readIndex() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        indexed = query.results.compactMap { result in
            guard let path = (result as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            let url = URL(fileURLWithPath: path)
            return InstalledApplication(url: url)
        }
        mergeApplications()
    }

    private func mergeApplications() {
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL.flatMap(InstalledApplication.init) }
        var byID: [String: InstalledApplication] = [:]
        for app in running + scanned + indexed where byID[app.id] == nil {
            byID[app.id] = app
        }
        applications = byID.values.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    nonisolated private static func scanStandardFolders() -> [InstalledApplication] {
        let roots = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
                     URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
                     URL(fileURLWithPath: "/System/Library/CoreServices/Applications")]
        return roots.flatMap { root -> [InstalledApplication] in
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
            return enumerator.compactMap { ($0 as? URL).flatMap(InstalledApplication.init) }
        }
    }
}
