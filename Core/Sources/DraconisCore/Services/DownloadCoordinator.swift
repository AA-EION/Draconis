import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// URLSessionDownloadDelegate bridge that exposes per-chunk progress to an
/// async caller. Every download shares one session that's never invalidated:
/// on Linux, invalidating a session from its own delegate callback frees
/// libcurl's handle while it's still in use and crashes the app
/// ("_MultiHandle deallocated with non-zero retain count").
public final class DownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    public typealias Progress = NorthstarUpdater.Progress
    public typealias ProgressHandler = @Sendable (Progress) -> Void

    public enum DLError: Error, LocalizedError {
        case badResponse(Int)

        public var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "The server returned HTTP \(code)."
            }
        }
    }

    private struct Job {
        let progress: ProgressHandler?
        let continuation: CheckedContinuation<URL, Error>
    }

    private static let shared = DownloadCoordinator()
    private let lock = NSLock()
    private var jobs: [Int: Job] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.httpAdditionalHeaders = ["User-Agent": "Draconis-Launcher"]
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// One-shot async download with progress.
    public static func download(
        from url: URL, progress: ProgressHandler? = nil
    ) async throws -> URL {
        try await shared.start(url, progress: progress)
    }

    private func start(_ url: URL, progress: ProgressHandler?) async throws -> URL {
        try await withCheckedThrowingContinuation { cc in
            lock.lock()
            let task = session.downloadTask(with: url)
            jobs[task.taskIdentifier] = Job(progress: progress, continuation: cc)
            lock.unlock()
            task.resume()
        }
    }

    private func job(_ task: URLSessionTask) -> Job? {
        lock.lock(); defer { lock.unlock() }
        return jobs[task.taskIdentifier]
    }

    private func finish(_ task: URLSessionTask, _ result: Result<URL, Error>) {
        lock.lock()
        let job = jobs.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        job?.continuation.resume(with: result)
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // totalBytesExpectedToWrite is -1 when the server omits Content-Length.
        // In that case report indeterminate progress showing only downloaded bytes.
        let unknown = totalBytesExpectedToWrite == NSURLSessionTransferSizeUnknown
                   || totalBytesExpectedToWrite <= 0
        guard let progress = job(downloadTask)?.progress else { return }
        if unknown {
            progress(Progress(
                phase: .downloading,
                fraction: -1,
                detail: Self.bytes(totalBytesWritten)
            ))
        } else {
            let frac = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progress(Progress(
                phase: .downloading,
                fraction: frac,
                detail: "\(Self.bytes(totalBytesWritten)) / \(Self.bytes(totalBytesExpectedToWrite))"
            ))
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(downloadTask, .failure(DLError.badResponse(http.statusCode)))
            return
        }
        // We have to move the file out of the temp location BEFORE returning,
        // because URLSession deletes it immediately after this delegate returns.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: tmp)
            finish(downloadTask, .success(tmp))
        } catch {
            finish(downloadTask, .failure(error))
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // didFinishDownloadingTo already resumed a successful download.
        finish(task, .failure(error ?? URLError(.unknown)))
    }

    private static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
