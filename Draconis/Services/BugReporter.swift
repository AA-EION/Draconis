import Foundation
import Sentry

/// Snapshot of Draconis's state at bug-report time, used to build Sentry
/// event context. All fields are `Sendable` so the struct can be passed
/// across actor boundaries after being built on the MainActor.
public struct BugReportContext: Sendable {
    // App
    var appVersion: String
    // CrossOver
    var crossOverInstalled: Bool
    // Active bottle (nil if no bottle selected)
    var bottleExists: Bool
    var hasNorthstar: Bool
    var hasTitanfall2: Bool
    var hasSteam: Bool
    var hasEAApp: Bool
    var hasEpicGames: Bool
    var hasMaxima: Bool
    var northstarVersion: String?
    var maximaRole: String
    var maximaInstalledVersion: String?
    var maximaSetupPhaseLabel: String
    // Visible errors
    var lastLaunchError: String?
    var lastUpdateError: String?
    var maximaError: String?
    // Sanitized console output (home dir replaced with ~)
    var recentLogs: [String]
}

extension BugReportContext {
    /// Build a context snapshot from the current AppEnvironment state.
    /// Must be called on the MainActor so DebugLog.shared.lines is accessible.
    @MainActor
    static func capture(from env: AppEnvironment) -> BugReportContext {
        let home = NSHomeDirectory()
        let logs: [String] = DebugLog.shared.lines.suffix(60).map { line in
            let text = "[\(line.level.rawValue.uppercased())] [\(line.scope)] \(line.message)"
            return text.replacingOccurrences(of: home, with: "~")
        }

        let bottle = env.selectedBottle

        let phaseLabel: String
        switch env.maximaSetupPhase {
        case .idle:                                   phaseLabel = "idle"
        case .installingGame(_, let slug, _):         phaseLabel = "installing(\(slug))"
        case .finishing:                              phaseLabel = "finishing"
        case .done:                                   phaseLabel = "done"
        case .failed(let msg):
            phaseLabel = "failed: \(msg.replacingOccurrences(of: home, with: "~"))"
        }

        return BugReportContext(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            crossOverInstalled: env.crossOverInstalled,
            bottleExists: bottle != nil,
            hasNorthstar:  bottle?.hasNorthstar  ?? false,
            hasTitanfall2: bottle?.hasTitanfall2 ?? false,
            hasSteam:      bottle?.hasSteam      ?? false,
            hasEAApp:      bottle?.hasEAApp      ?? false,
            hasEpicGames:  bottle?.hasEpicGames  ?? false,
            hasMaxima:     bottle?.hasMaxima     ?? false,
            northstarVersion:      bottle?.northstarVersion,
            maximaRole:            bottle?.maximaRole.rawValue ?? "none",
            maximaInstalledVersion: env.maximaInstalledVersion,
            maximaSetupPhaseLabel: phaseLabel,
            lastLaunchError: env.lastLaunchError,
            lastUpdateError: env.lastUpdateError,
            maximaError:    env.maximaError,
            recentLogs: Array(logs)
        )
    }
}

/// Submits a user-written bug report to Sentry with full context.
/// Uses the `SentryUserFeedback` API to link a description + optional contact
/// to the associated context event so Sentry displays them together.
public actor BugReporter {
    public static let shared = BugReporter()

    public struct Report: Sendable {
        public var description: String
        public var reporterName: String?
        public var reporterContact: String?
    }

    public func submit(_ report: Report, context: BugReportContext) {
        // 1. Capture a structured event carrying all context so it appears
        //    in Sentry's issue timeline with full environment data.
        let event = SentryEvent(level: .info)
        event.message = SentryMessage(formatted: "User Bug Report")
        event.tags = buildTags(from: context)
        event.extra = buildExtra(from: context)

        let eventId = SentrySDK.capture(event: event)

        // 2. Attach user-written feedback to the event — this surfaces in
        //    Sentry's "User Feedback" section alongside the event detail.
        let feedback = SentryUserFeedback(eventId: eventId)
        feedback.name     = report.reporterName?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Anonymous"
        feedback.email    = report.reporterContact?.trimmingCharacters(in: .whitespaces) ?? ""
        feedback.comments = report.description
        SentrySDK.captureUserFeedback(feedback)
    }

    // MARK: - Private helpers

    private func buildTags(from ctx: BugReportContext) -> [String: String] {
        var t: [String: String] = [:]
        t["app.version"]        = ctx.appVersion
        t["crossover.installed"] = ctx.crossOverInstalled ? "true" : "false"
        t["bottle.exists"]      = ctx.bottleExists      ? "true" : "false"
        t["bottle.hasTF2"]      = ctx.hasTitanfall2     ? "true" : "false"
        t["bottle.hasNS"]       = ctx.hasNorthstar      ? "true" : "false"
        t["bottle.hasSteam"]    = ctx.hasSteam          ? "true" : "false"
        t["bottle.hasEA"]       = ctx.hasEAApp          ? "true" : "false"
        t["bottle.hasMaxima"]   = ctx.hasMaxima         ? "true" : "false"
        t["maxima.role"]        = ctx.maximaRole
        t["maxima.phase"]       = ctx.maximaSetupPhaseLabel
        if let v = ctx.northstarVersion       { t["northstar.version"] = v }
        if let v = ctx.maximaInstalledVersion { t["maxima.version"] = v }
        return t
    }

    private func buildExtra(from ctx: BugReportContext) -> [String: Any] {
        var x: [String: Any] = [:]
        if let e = ctx.lastLaunchError  { x["error.launch"]  = e }
        if let e = ctx.lastUpdateError  { x["error.update"]  = e }
        if let e = ctx.maximaError      { x["error.maxima"]  = e }
        x["console.last60"] = ctx.recentLogs.joined(separator: "\n")
        return x
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
