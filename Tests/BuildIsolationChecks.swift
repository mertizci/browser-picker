import Foundation
@testable import BrowserPicker

@main
struct BuildIsolationChecks {
    static func main() {
        precondition(BuildConfiguration.isDebugPreview, "Debug builds must not use release settings or enable release updates")
        precondition(BuildConfiguration.settingsDirectoryName == "BrowserPicker Debug")
        print("PASS: ordinary Debug builds isolate settings and disable release updates")
    }
}
