import Foundation

/// Runs AppleScript through `osascript`, which keeps browser automation out of
/// this process and lets callers surface the script's own error text.
enum AppleScriptRunner {
    /// Runs a script and throws when it fails, preferring the script's error
    /// message over `fallbackMessage`.
    static func run(_ source: String, fallbackMessage: String) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw BrowserPickerError.launchFailed(
                message?.isEmpty == false ? message! : fallbackMessage
            )
        }
    }

    /// Runs a script and returns its trimmed output, or `nil` when it fails.
    static func output(of source: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Escapes a value for use inside an AppleScript string literal.
    static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Renders values as an AppleScript list literal.
    static func list(_ values: [String]) -> String {
        guard !values.isEmpty else { return "{}" }
        return "{\(values.map { "\"\(escaped($0))\"" }.joined(separator: ", "))}"
    }
}
