import AppKit
import Carbon

enum SourceApplicationResolver {
    /// Read synchronously in the open-URL callback, before leaving the current Apple event.
    static func currentBundleIdentifier() -> String? {
        bundleIdentifier(from: NSAppleEventManager.shared().currentAppleEvent)
    }

    static func bundleIdentifier(
        from event: NSAppleEventDescriptor?,
        resolvePID: (pid_t) -> String? = { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
    ) -> String? {
        bundleIdentifier(senderPID: event?.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)), resolvePID: resolvePID)
    }

    static func bundleIdentifier(senderPID descriptor: NSAppleEventDescriptor?, resolvePID: (pid_t) -> String?) -> String? {
        guard let descriptor,
              let pid = descriptor.coerce(toDescriptorType: DescType(typeSInt32))?.int32Value,
              pid > 0 else { return nil }
        return resolvePID(pid)
    }
}
