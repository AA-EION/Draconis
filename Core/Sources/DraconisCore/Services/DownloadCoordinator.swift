import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// URLSessionDownloadDelegate bridge that exposes per-chunk progress to an
/// async caller.
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

    private let url: URL
    private let progress: ProgressHandler?
    private var continuation: CheckedContinuation<URL, Error>?

    init(url: URL, progress: ProgressHandler?) {
        self.url = url
        self.progress = progress
    }

    /// One-shot async download with progress.
    public static func download(
        from url: URL, progress: ProgressHandler? = nil
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
        if unknown {
            progress?(Progress(
                phase: .downloading,
                fraction: -1,
                detail: Self.bytes(totalBytesWritten)
            ))
        } else {
            let frac = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progress?(Progress(
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
            continuation?.resume(throwing: DLError.badResponse(http.statusCode))
            continuation = nil
            return
        }
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

    public func urlSession(
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
