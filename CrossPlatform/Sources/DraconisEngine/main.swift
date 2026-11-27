import DraconisCore
import Foundation

// draconis-engine: Draconis's logic for Linux and Windows, without a window.
// The UI (Desktop/, Rust) starts it, sends commands as JSON lines on stdin and
// reads state, console lines, mods and servers as JSON lines on stdout.

CrashReports.enable()

@MainActor
final class Engine {
    let model = AppModel()
    let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    var lastState: EngineState?
    var packagesSent = -1
    var serversSent: [ServerInfo] = []

    func send(_ message: Message) {
        guard var data = try? encoder.encode(message) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    func start() {
        model.logSink = { [weak self] line in self?.send(.log(line)) }
        Thread.detachNewThread { [weak self] in
            let decoder = JSONDecoder()
            while let line = readLine() {
                guard let command = try? decoder.decode(Command.self, from: Data(line.utf8)) else { continue }
                Task { @MainActor in await self?.model.perform(command) }
            }
            exit(0) // the UI closed
        }
        Task { await model.bootstrap() }
        Task {
            while true {
                emit()
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    /// Send what changed since the last tick.
    func emit() {
        if model.packages.count != packagesSent {
            packagesSent = model.packages.count
            send(.packages(model.browsablePackages()))
        }
        let servers = model.serverList()
        if servers != serversSent {
            serversSent = servers
            send(.servers(servers))
        }
        let state = model.snapshot()
        if state != lastState {
            lastState = state
            send(.state(state))
        }
    }
}

MainActor.assumeIsolated {
    let engine = Engine()
    engine.start()
    withExtendedLifetime(engine) { dispatchMain() }
}
