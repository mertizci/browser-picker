import Foundation

/// A single downloadable file attached to a GitHub release.
struct ReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

/// The subset of a GitHub release we care about.
struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let assets: [ReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case assets
    }

    /// Human-facing release notes (markdown), falling back to an empty string.
    var releaseNotes: String { body ?? "" }

    /// The displayable version string (without a leading `v`).
    var displayVersion: String {
        SemanticVersion(tagName).map(\.description) ?? tagName
    }
}

enum GitHubReleaseError: LocalizedError {
    case invalidResponse
    case noDMGAsset

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Could not read the latest release information."
        case .noDMGAsset:
            return "The latest release does not include a downloadable installer."
        }
    }
}

/// Fetches release metadata from the GitHub REST API. Networking + decoding only.
struct GitHubReleaseService {
    static let repository = "mertizci/browser-picker"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
    }

    func latestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BrowserPicker", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GitHubReleaseError.invalidResponse
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// The first `.dmg` asset in a release, if any.
    func dmgAsset(in release: GitHubRelease) -> ReleaseAsset? {
        release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }
}
