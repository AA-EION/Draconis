import Darwin
import Foundation

/// Native `posix_spawn` wrapper that mimics what a shell does when it
/// `fork+setsid+exec`s a command. Solves a real, reproducible Wine /
/// CrossOver issue: `Foundation.Process` spawns via `posix_spawn`
/// without `POSIX_SPAWN_CLOEXEC_DEFAULT` or `POSIX_SPAWN_SETSID`, so
/// the child inherits:
///
///   * **Every non-O_CLOEXEC file descriptor** the parent had open —
///     Mach ports, IOSurface handles, AppKit / CoreFoundation
///     internals. A SwiftUI app holds dozens of these; Wine's macOS
///     driver gets confused by them and TF2 freezes after LSX
///     `GetAllGameInfo`.
///   * **The parent's session and process group** — Draconis is a
///     launchd-spawned `.app` session leader, and Wine's msync
///     (Mach-based synchronization) appears to need its own session
///     to behave correctly.
///
/// Empirical confirmation: the exact same `cxstart` invocation reaches
/// the Titanfall 2 main menu when run from `Terminal.app` (which spawns
/// via shell fork+setsid+exec) and freezes mid-launch when run via
/// `Foundation.Process` from a `.app`. After this wrapper lands, the
/// `.app`-launched chain matches Terminal's behavior.
///
/// This is the "native" way to fix the gap — no shell wrappers, no
/// helper binaries, no `script(1)` PTY tricks. Just `posix_spawn` with
/// the flags macOS exposes for exactly this case.
public enum CleanSpawn {

    public enum Error: Swift.Error, LocalizedError {
        case posixSpawnFailed(errno: Int32)
        case attrInitFailed
        case fileActionsInitFailed

        public var errorDescription: String? {
            switch self {
            case .posixSpawnFailed(let e):
                return "posix_spawn failed: \(String(cString: strerror(e)))"
            case .attrInitFailed:
                return "posix_spawnattr_init failed"
            case .fileActionsInitFailed:
                return "posix_spawn_file_actions_init failed"
            }
        }
    }

    /// macOS-only spawn flag: every FD that isn't registered via
    /// `posix_spawn_file_actions_*` is closed at exec. Defined in
    /// `<spawn.h>` but not imported into Swift's Darwin module.
    private static let POSIX_SPAWN_CLOEXEC_DEFAULT: Int32 = 0x4000

    /// `posix_spawn_attr` flag: child becomes session leader of a new
    /// session (equivalent to calling `setsid()` after fork). On macOS
    /// it's `POSIX_SPAWN_SETSID = 0x0400`, also not in Darwin's
    /// imported headers.
    private static let POSIX_SPAWN_SETSID: Int32 = 0x0400

    /// `responsibility_spawnattrs_setdisclaim` — Apple-private API
    /// (in libsystem, available since 10.14). Tells macOS that the
    /// spawned child should NOT be responsibility-attributed to the
    /// spawner. The child becomes its own responsible process, the
    /// way an app launched directly from `Terminal.app` or `Finder`
    /// is. This matters because:
    ///
    ///   * macOS's App Nap / power-throttling decisions cascade from
    ///     responsible parent → child. A `.app` in the background
    ///     drags its children's CPU / IO timers down with it, which
    ///     for a Wine-hosted game presents as a freeze a few seconds
    ///     into launch.
    ///   * TCC (Privacy) permissions are also attributed to the
    ///     responsible process. We don't need them, but inheriting
    ///     them can produce subtle differences in what the kernel
    ///     allows the child to do.
    ///
    /// Resolved via `dlsym` because there's no public header for it.
    /// The symbol has been stable since 10.14; if a future macOS
    /// removes it, `dlsym` returns nil and we silently no-op.
    private typealias DisclaimFn = @convention(c) (
        UnsafeMutablePointer<posix_spawnattr_t?>, Int32
    ) -> Int32

    private static let disclaimResponsibility: DisclaimFn? = {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "responsibility_spawnattrs_setdisclaim") else {
            return nil
        }
        return unsafeBitCast(symbol, to: DisclaimFn.self)
    }()

    /// Spawn a process detached from the parent's session and FD table.
    /// Returns the new process's PID. Caller is responsible for
    /// `waitpid()` or polling if it wants to track the child's
    /// lifetime.
    ///
    /// - Parameters:
    ///   - executable: absolute path to the binary to execute.
    ///   - arguments: argv (does NOT include the executable name —
    ///     this adds it as `argv[0]` automatically).
    ///   - environment: full env to pass; if nil, inherits the
    ///     current process's environment.
    ///   - stdinPath: path opened RDONLY as the child's stdin.
    ///     Defaults to `/dev/null`.
    ///   - stdoutPath: path opened WRONLY|APPEND|CREAT as the child's
    ///     stdout. Defaults to `/dev/null`.
    ///   - stderrPath: same, for stderr. If equal to `stdoutPath`,
    ///     stderr is dup2'd to the same FD (single log file).
    public static func spawn(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        stdinPath: String = "/dev/null",
        stdoutPath: String = "/dev/null",
        stderrPath: String? = nil
    ) throws -> pid_t {
        // 1. argv — C-string array, NULL-terminated.
        let argvStrings = [executable] + arguments
        var argv: [UnsafeMutablePointer<CChar>?] = argvStrings.map { strdup($0) }
        argv.append(nil)
        defer {
            for ptr in argv {
                if let ptr { free(ptr) }
            }
        }

        // 2. envp — same shape as argv. Inherit if not overridden.
        let envDict = environment ?? ProcessInfo.processInfo.environment
        let envStrings = envDict.map { "\($0.key)=\($0.value)" }
        var envp: [UnsafeMutablePointer<CChar>?] = envStrings.map { strdup($0) }
        envp.append(nil)
        defer {
            for ptr in envp {
                if let ptr { free(ptr) }
            }
        }

        // 3. file_actions — set up stdio redirects. Anything we don't
        //    register here gets closed by POSIX_SPAWN_CLOEXEC_DEFAULT,
        //    which is the whole point.
        var fileActions = posix_spawn_file_actions_t(bitPattern: 0)
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            throw Error.fileActionsInitFailed
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        _ = stdinPath.withCString { path in
            posix_spawn_file_actions_addopen(&fileActions, 0, path, O_RDONLY, 0)
        }
        _ = stdoutPath.withCString { path in
            posix_spawn_file_actions_addopen(&fileActions, 1, path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        }
        let stderrTarget = stderrPath ?? stdoutPath
        if stderrTarget == stdoutPath {
            // Same file — dup2 from fd 1 to keep ordering tidy.
            posix_spawn_file_actions_adddup2(&fileActions, 1, 2)
        } else {
            _ = stderrTarget.withCString { path in
                posix_spawn_file_actions_addopen(&fileActions, 2, path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
            }
        }

        // 4. attr — set the two flags that bring us in line with shell
        //    spawn semantics: clean FD table + new session.
        var attr = posix_spawnattr_t(bitPattern: 0)
        guard posix_spawnattr_init(&attr) == 0 else {
            throw Error.attrInitFailed
        }
        defer { posix_spawnattr_destroy(&attr) }

        let flags: Int16 = Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSID)
        posix_spawnattr_setflags(&attr, flags)

        // 5. Disclaim responsibility — child is its own responsible
        //    process. Without this, macOS keeps the child attributed
        //    to Draconis, dragging it into Draconis's App Nap /
        //    throttling state when Draconis isn't focused.
        if let disclaim = disclaimResponsibility {
            _ = disclaim(&attr, 1)
        }

        // 6. Spawn.
        var pid: pid_t = 0
        let result = posix_spawn(
            &pid,
            executable,
            &fileActions,
            &attr,
            argv,
            envp
        )
        guard result == 0 else {
            throw Error.posixSpawnFailed(errno: result)
        }
        return pid
    }
}
