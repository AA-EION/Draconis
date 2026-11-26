import Foundation

public enum LogLevel: String, Sendable, CaseIterable, Identifiable {
    case info, ok, warn, error, run
    public var id: String { rawValue }
}

/// Logging used by the core. Each app installs a sink (its console view);
/// without one, lines go to stderr in debug builds.
public enum Log {
    public typealias Sink = @Sendable (LogLevel, String, String) -> Void

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _sink: Sink?

    public static var sink: Sink? {
        get { lock.lock(); defer { lock.unlock() }; return _sink }
        set { lock.lock(); _sink = newValue; lock.unlock() }
    }

    public static func info(_ scope: String, _ msg: String)  { write(.info,  scope, msg) }
    public static func ok(_ scope: String, _ msg: String)    { write(.ok,    scope, msg) }
    public static func warn(_ scope: String, _ msg: String)  { write(.warn,  scope, msg) }
    public static func error(_ scope: String, _ msg: String) { write(.error, scope, msg) }
    public static func run(_ scope: String, _ msg: String)   { write(.run,   scope, msg) }

    public static func write(_ level: LogLevel, _ scope: String, _ msg: String) {
        if let sink { sink(level, scope, msg); return }
        #if DEBUG
        FileHandle.standardError.write(Data("\(level.rawValue.uppercased()) \(scope): \(msg)\n".utf8))
        #endif
    }
}
