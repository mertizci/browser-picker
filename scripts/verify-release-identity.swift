import Foundation

@main
struct VerifyReleaseIdentity {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("Usage: verify-release-identity <BrowserPicker.app>\n", stderr)
            exit(2)
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        guard ReleaseIdentity.isValid(at: url) else {
            fputs("Release rejected: signature or permission identity differs from v1.0.20. Use the original bundle ID and Developer ID identity without a custom designated requirement.\n", stderr)
            exit(1)
        }
        print("Verified release signature and v1.0.20 permission identity: \(url.path)")
    }
}
