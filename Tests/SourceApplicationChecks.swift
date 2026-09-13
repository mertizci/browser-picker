import AppKit
import Carbon
@testable import BrowserPicker

@main
struct SourceApplicationChecks {
    @MainActor
    static func main() throws {
        let url = URL(string: "https://example.com/work/item")!
        let mail = RuleMatcher(kind: .sourceApplication, value: "com.apple.mail", applicationName: "Mail")
        assert(mail.matches(url: url, sourceApp: "com.apple.mail"))
        assert(mail.matches(url: url, sourceApp: "COM.APPLE.MAIL"))
        assert(!mail.matches(url: url, sourceApp: "com.apple.mail.helper"))
        assert(!mail.matches(url: url, sourceApp: "com.apple.Safari"))
        assert(!mail.matches(url: url, sourceApp: nil))
        var notMail = mail
        notMail.isNegated = true
        assert(notMail.matches(url: url, sourceApp: "com.apple.Safari"))
        assert(!notMail.matches(url: url, sourceApp: "com.apple.mail"))
        assert(!notMail.matches(url: url, sourceApp: nil))
        assert(!notMail.matches(url: url, sourceApp: ""))
        assert(mail.summary == "Source application: Mail")
        print("PASS: source applications match exact bundle IDs; NOT does not match an unknown sender")

        let event = NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kInternetEventClass),
            eventID: AEEventID(kAEGetURL), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        assert(SourceApplicationResolver.bundleIdentifier(from: event) == nil)
        assert(SourceApplicationResolver.bundleIdentifier(from: nil) == nil)
        let sender = NSAppleEventDescriptor(int32: 42)
        assert(SourceApplicationResolver.bundleIdentifier(senderPID: sender, resolvePID: { $0 == 42 ? "com.apple.mail" : nil }) == "com.apple.mail")
        assert(SourceApplicationResolver.bundleIdentifier(senderPID: sender, resolvePID: { _ in nil }) == nil)
        assert(SourceApplicationResolver.bundleIdentifier(senderPID: NSAppleEventDescriptor(int32: 0), resolvePID: { _ in assertionFailure(); return nil }) == nil)
        print("PASS: Apple event sender PID is resolved; missing/exited senders remain unknown")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let work = BrowserProfile(id: "work", displayName: "Work", browser: .chrome)
        let personal = BrowserProfile(id: "private", displayName: "Private", browser: .firefox)
        let target = RouteTarget(browser: .chrome, profileId: work.id)
        let rule = RoutingRule(name: "Mail work links", priority: 0,
            matchers: [mail, RuleMatcher(kind: .pathPrefix, value: "/work/")], matchMode: .all, target: target)
        let config = folder.appendingPathComponent("config.json")
        let store = SettingsStore(configURL: config, discoverProfiles: { [work, personal] })
        store.reloadProfiles()
        store.addRule(rule)
        store.setDefaultTarget(RouteTarget(browser: personal.browser, profileId: personal.id))
        assert(RuleTester.test(url: url, store: store, sourceApp: "com.apple.mail").matchedRuleID == rule.id)
        assert(RuleTester.test(url: url, store: store, sourceApp: "com.apple.Safari").matchedRuleID == nil)
        assert(RuleTester.test(url: url, store: store).matchedRuleID == nil)
        assert(RuleTester.test(url: URL(string: "https://example.com/personal/")!, store: store, sourceApp: "com.apple.mail").matchedRuleID == nil)
        var either = rule
        either.matchMode = .any
        assert(either.matches(url: URL(string: "https://other.test")!, sourceApp: "com.apple.mail"))
        assert(either.matches(url: url, sourceApp: nil))
        try store.duplicateRule(id: rule.id)
        let reloaded = SettingsStore(configURL: config)
        assert(reloaded.settings.rules.count == 2)
        assert(reloaded.settings.rules.allSatisfy { $0.matchers == rule.matchers })
        try store.setProfileEnabled(false, for: work)
        assert(RuleTester.test(url: url, store: store, sourceApp: "com.apple.mail").matchedRuleID == nil)
        let legacy = Data(#"{"kind":"urlContains","value":"example.com"}"#.utf8)
        let decoded = try JSONDecoder().decode(RuleMatcher.self, from: legacy)
        assert(decoded.applicationName == nil)
        print("PASS: source rules compose with AND/OR, persist and duplicate, respect disabled profiles, and work in the tester")

        let fixtureURL = folder.appendingPathComponent("Mail.app")
        let contents = fixtureURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "com.example.mail", "CFBundleDisplayName": "Company Mail"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let app = InstalledApplication(url: fixtureURL)!
        assert(app.id == "com.example.mail" && app.name == "Company Mail")
        assert(app.matches(search: "mail") && app.matches(search: "COMPANY mail") && app.matches(search: "com.example"))
        assert(!app.matches(search: "Safari"))
        assert(InstalledApplication(url: folder) == nil)
        let helper = fixtureURL.appendingPathComponent("Contents/Helper.app/Contents")
        try FileManager.default.createDirectory(at: helper, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: helper.appendingPathComponent("Info.plist"))
        assert(InstalledApplication(url: helper.deletingLastPathComponent()) == nil)
        let background = folder.appendingPathComponent("Background.app/Contents")
        try FileManager.default.createDirectory(at: background, withIntermediateDirectories: true)
        let backgroundInfo: [String: Any] = ["CFBundleIdentifier": "com.example.background", "LSBackgroundOnly": true]
        try PropertyListSerialization.data(fromPropertyList: backgroundInfo, format: .xml, options: 0).write(to: background.appendingPathComponent("Info.plist"))
        assert(InstalledApplication(url: background.deletingLastPathComponent()) == nil)
        print("PASS: app picker discovers bundle names/IDs and filters case-insensitively by multiple search terms")
    }
}
