import AppKit
import Foundation

enum UpdateInstallError: LocalizedError {
    case mountFailed
    case appNotFoundInDMG
    case signatureInvalid
    case stagingFailed
    case destinationNotWritable

    var errorDescription: String? {
        switch self {
        case .mountFailed:
            return "Could not open the downloaded installer."
        case .appNotFoundInDMG:
            return "The installer did not contain Browser Picker."
        case .signatureInvalid:
            return "The downloaded update failed signature verification and was rejected."
        case .stagingFailed:
            return "Could not prepare the update for installation."
        case .destinationNotWritable:
            return "Browser Picker can't update itself in its current location."
        }
    }
}

/// Mounts a downloaded DMG, verifies the contained app is signed by the
/// expected Developer ID team, stages a verified copy, then performs an
/// in-place swap + relaunch via a detached shell script.
struct UpdateInstaller {
    private static let appName = "BrowserPicker.app"

    // MARK: - Stage

    /// Mounts `dmgURL`, verifies the signature, copies the app to a staging
    /// directory, then detaches the image. Returns the staged `.app` URL.
    func prepareStagedApp(fromDMG dmgURL: URL) throws -> URL {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("bp-mount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        try attach(dmg: dmgURL, at: mountPoint)
        defer { detach(mountPoint) }

        let appInDMG = mountPoint.appendingPathComponent(Self.appName)
        guard FileManager.default.fileExists(atPath: appInDMG.path) else {
            throw UpdateInstallError.appNotFoundInDMG
        }

        try verifySignature(of: appInDMG)

        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bp-staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stagedApp = stagingDir.appendingPathComponent(Self.appName)

        guard runDitto(from: appInDMG, to: stagedApp) else {
            throw UpdateInstallError.stagingFailed
        }

        try verifySignature(of: stagedApp)

        return stagedApp
    }

    // MARK: - Install

    /// Swaps the running app bundle with `stagedApp` and relaunches.
    ///
    /// This never returns on success — it terminates the current process so
    /// the detached script can replace the bundle while nothing holds it open.
    func installAndRelaunch(stagedApp: URL, into destination: URL) throws {
        try verifySignature(of: stagedApp)
        let parent = destination.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateInstallError.destinationNotWritable
        }

        let script = """
        #!/bin/sh
        PID="$1"
        SRC="$2"
        DEST="$3"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        rm -rf "$DEST" && ditto "$SRC" "$DEST"
        open "$DEST"
        rm -rf "$(dirname "$SRC")"
        rm -f "$0"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bp-swap-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            stagedApp.path,
            destination.path
        ]
        try process.run()

        Task { @MainActor in NSApp.terminate(nil) }
    }

    // MARK: - hdiutil helpers

    private func attach(dmg: URL, at mountPoint: URL) throws {
        let result = run("/usr/bin/hdiutil", [
            "attach", dmg.path,
            "-nobrowse", "-noautoopen",
            "-mountpoint", mountPoint.path
        ])
        guard result == 0 else { throw UpdateInstallError.mountFailed }
    }

    private func detach(_ mountPoint: URL) {
        _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
    }

    private func runDitto(from source: URL, to destination: URL) -> Bool {
        run("/usr/bin/ditto", [source.path, destination.path]) == 0
    }

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    // MARK: - Signature verification

    /// Require the original release identity as well as a valid signature so
    /// updates cannot introduce a build-specific TCC permission identity.
    private func verifySignature(of appURL: URL) throws {
        guard ReleaseIdentity.isValid(at: appURL) else {
            throw UpdateInstallError.signatureInvalid
        }
    }
}
