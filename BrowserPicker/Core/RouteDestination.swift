import Foundation

/// One place a link can be sent: a profile, or a single space inside it. Spaces
/// turn one profile into several destinations, so pickers list destinations
/// rather than profiles.
struct RouteDestination: Identifiable, Hashable {
    let profile: BrowserProfile
    let space: BrowserSpace?

    var target: RouteTarget {
        RouteTarget(browser: profile.browser, profileId: profile.id, spaceId: space?.id)
    }

    var id: RouteTarget { target }

    /// A space names only itself: the group it sits in names its container.
    var title: String {
        if let space { return space.name }
        return profile.spaces.isEmpty ? profile.displayName : "Current Space"
    }

    /// `nil` for a space, whose group heading already places it.
    var subtitle: String? {
        guard space == nil else { return nil }
        guard !profile.spaces.isEmpty else { return profile.browser.displayName }
        // Which profile's open space this is, since a browser with spaces can
        // have several profiles holding them.
        return "\(profile.browser.displayName) · \(profile.displayName)"
    }
}

/// Destinations under one heading.
///
/// Zen puts every space in a container and calls that container the space's
/// *profile*, so containers are the level users know: they head the groups and
/// their spaces are the rows. Destinations with no space to place — plain
/// profiles, and the open space of a profile that has spaces — share the single
/// leading group, which carries no heading.
struct RouteDestinationGroup: Identifiable {
    let id: String
    let title: String?
    let destinations: [RouteDestination]

    static func all(in profiles: [BrowserProfile]) -> [RouteDestinationGroup] {
        guard !profiles.isEmpty else { return [] }

        let profilesWithSpaces = profiles.filter { !$0.spaces.isEmpty }
        // A heading names only what its group needs to be told apart: the
        // browser once several are listed, the profile once several of that
        // browser's profiles hold spaces.
        let namesBrowser = Set(profiles.map(\.browser)).count > 1
        let spacedProfileCounts = Dictionary(grouping: profilesWithSpaces, by: \.browser)
            .mapValues(\.count)

        let profileGroup = RouteDestinationGroup(
            id: "profiles",
            title: nil,
            destinations: profiles.map { RouteDestination(profile: $0, space: nil) }
        )

        return [profileGroup] + profilesWithSpaces.flatMap { profile in
            containerGroups(
                in: profile,
                namesBrowser: namesBrowser,
                namesProfile: (spacedProfileCounts[profile.browser] ?? 0) > 1
            )
        }
    }

    private static func containerGroups(
        in profile: BrowserProfile,
        namesBrowser: Bool,
        namesProfile: Bool
    ) -> [RouteDestinationGroup] {
        profile.spacesByContainer.map { container, spaces in
            RouteDestinationGroup(
                id: "\(profile.id)/\(container)",
                title: [
                    namesBrowser ? profile.browser.displayName : nil,
                    namesProfile ? profile.displayName : nil,
                    container
                ]
                    .compactMap { $0 }
                    .joined(separator: " · "),
                destinations: spaces.map { RouteDestination(profile: profile, space: $0) }
            )
        }
    }
}

extension BrowserProfile {
    /// Reads as "Zen · Work · work": the browser, then — when a space is
    /// targeted — the space's container and the space, which is how Zen itself
    /// nests them. Without a space it is the browser and this profile.
    func routeLabel(spaceId: String? = nil) -> String {
        guard let space = space(id: spaceId) else {
            return "\(browser.displayName) · \(displayName)"
        }
        return "\(browser.displayName) · \(space.nestedLabel)"
    }
}
