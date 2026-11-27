import Foundation
import Combine
@_exported import DraconisCore

/// In-app console log. Every long-running operation (download, extract, launch,
/// HTTP call) appends here so the user can open the Console view and see what
/// Draconis is actually doing on their behalf.
@MainActor
public final class DebugLog: ObservableObject {
    public static let shared = DebugLog()

    public typealias Level = LogLevel

    public struct Line: Identifiable, Hashable, Sendable {
        public let id = UUID()
        public let timestamp: Date
        public let level: Level
        public let scope: String          // e.g. "northstar.install"
        public let message: String
    }

    @Published public private(set) var lines: [Line] = []
    private let maxLines = 2_000

    private init() {
        Log.sink = { level, scope, message in
            Task { @MainActor in DebugLog.shared.log(level, scope: scope, message) }
        }
    }

    public func log(_ level: Level, scope: String, _ message: String) {
        let line = Line(
            timestamp: Date(), level: level, scope: scope, message: message
        )
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        #if DEBUG
        let stamp = ISO8601DateFormatter().string(from: line.timestamp)
        print("[\(stamp)] \(level.rawValue.uppercased()) \(scope): \(message)")
        #endif
    }

    // MARK: - Convenience wrappers

    public func info(_ scope: String, _ msg: String)  { log(.info,  scope: scope, msg) }
    public func ok(_ scope: String, _ msg: String)    { log(.ok,    scope: scope, msg) }
    public func warn(_ scope: String, _ msg: String)  { log(.warn,  scope: scope, msg) }
    public func error(_ scope: String, _ msg: String) { log(.error, scope: scope, msg) }
    public func run(_ scope: String, _ msg: String)   { log(.run,   scope: scope, msg) }

    public func clear() { lines.removeAll() }
}

extension LogLevel {
    public var symbol: String {
        switch self {
        case .info:  return "info.circle"
        case .ok:    return "checkmark.seal"
        case .warn:  return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        case .run:   return "terminal"
        }
    }
}
