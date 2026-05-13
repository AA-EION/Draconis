import Foundation

/// URLSessionDownloadDelegate bridge that exposes per-chunk progress to an
/// async caller. Used by NorthstarUpdater (and anywhere else we need progress
/// during a long download).
final class DownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    typealias Progress = NorthstarUpdater.Progress
    typealias ProgressHandler = @Sendable (Progress) -> Void

    enum DLError: Error {
        case badResponse(Int)
        case missingFile
    }

    private let url: URL
    private let progress: ProgressHandler?
    private var continuation: CheckedContinuation<URL, Error>?

    init(url: URL, progress: ProgressHandler?) {
        self.url = url
        self.progress = progress
    }

    /// One-shot async download with progress.
    static func download(
        from url: URL, progress: ProgressHandler?
    ) async throws -> URL {
        let coordinator = DownloadCoordinator(url: url, progress: progress)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.httpAdditionalHeaders = ["User-Agent": "Draconis-Launcher"]
        let session = URLSession(
            configuration: config,
            delegate: coordinator,
            delegateQueue: nil
        )
        return try await withCheckedThrowingContinuation { cc in
            coordinator.continuation = cc
            session.downloadTask(with: url).resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = max(totalBytesExpectedToWrite, 1)
        let frac = Double(totalBytesWritten) / Double(total)
        progress?(Progress(
            phase: .downloading,
            fraction: frac,
            detail: "\(Self.bytes(totalBytesWritten)) / \(Self.bytes(totalBytesExpectedToWrite))"
        ))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // We have to move the file out of the temp location BEFORE returning,
        // because URLSession deletes it immediately after this delegate returns.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: tmp)
            continuation?.resume(returning: tmp)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // didFinishDownloadingTo already resumed; this catches errors only.
        if let error, continuation != nil {
            continuation?.resume(throwing: error)
            continuation = nil
        }
        session.finishTasksAndInvalidate()
    }

    private static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
