import Foundation

/// Downloads a file with `URLSession`, reporting fractional progress.
///
/// The download runs on a dedicated session whose delegate forwards byte
/// progress; the returned URL points at a stable temp file the caller owns.
final class UpdateDownloader: NSObject {
    private var progressHandler: ((Double) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()

    /// Downloads `url`, invoking `onProgress` (0...1) on the main actor, and
    /// returns a temp file URL that persists until the caller removes it.
    func download(_ url: URL, onProgress: @escaping (Double) -> Void) async throws -> URL {
        progressHandler = onProgress
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }
}

extension UpdateDownloader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let handler = progressHandler
        Task { @MainActor in handler?(fraction) }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The system removes `location` once this delegate returns, so move it
        // to a stable temp file synchronously here.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserPicker-update-\(UUID().uuidString).dmg")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
