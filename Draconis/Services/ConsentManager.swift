import Foundation
import Sentry

/// Manages the user's one-time acceptance of the Privacy & Data Notice.
///
/// Consent is persisted in `UserDefaults.standard` (which lives in
/// `~/Library/Preferences/org.draconis.launcher.plist`). If that file is
/// deleted — e.g. the user runs `defaults delete org.draconis.launcher` or
/// manually removes the plist — consent is treated as not given and the
/// notice is presented again on next launch.
///
/// `SentryConfig.boot()` must only be called after consent is established;
/// this enum handles the sequencing.
public enum ConsentManager {

    private static let acceptedKey = "privacyConsentAccepted"

    /// True if the user has previously accepted the privacy notice.
    public static var isAccepted: Bool {
        UserDefaults.standard.bool(forKey: acceptedKey)
    }

    /// Persist the user's acceptance and start Sentry. Safe to call multiple
    /// times — `SentryConfig.boot()` is idempotent.
    public static func accept() {
        UserDefaults.standard.set(true, forKey: acceptedKey)
        SentryConfig.boot()
        let event = Event(level: .info)
        event.message = SentryMessage(formatted: "privacy_consent_accepted")
        SentrySDK.capture(event: event)
    }

    /// Clears persisted consent. Called when the user declines — the app
    /// terminates immediately after, so this is mainly for future launches.
    public static func revoke() {
        UserDefaults.standard.removeObject(forKey: acceptedKey)
    }
}

/// Boots the Sentry SDK exactly once. Separate from `ConsentManager` so
/// both `DraconisApp.init()` (already-accepted users) and
/// `ConsentManager.accept()` (first-time users) can call it without
/// duplicating the configuration.
public enum SentryConfig {
    private static var booted = false

    public static func boot() {
        guard !booted else { return }
        booted = true
        SentrySDK.start { options in
            options.dsn = "https://4f4bf5f00a3d20204fea1aad3a20d72c@o4511434376871936.ingest.de.sentry.io/4511434386374736"
            #if DEBUG
            options.debug = true
            #endif
            options.sendDefaultPii = true
            options.tracesSampleRate = 1.0
        }
    }
}
