import SwiftUI
import AppKit

/// Live tail of every action Draconis takes — exposed so the user can verify
/// what the launcher is doing, especially during installs / launches.
struct ConsoleView: View {
    @ObservedObject private var log = DebugLog.shared
    @State private var autoscroll: Bool = true
    @State private var filter: DebugLog.Level? = nil

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.2)
            list
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("CONSOLE").stencilLabel(size: 12)
            Spacer()

            // Level filter
            Menu {
                Button("All") { filter = nil }
                ForEach(DebugLog.Level.allCases) { lvl in
                    Button {
                        filter = lvl
                    } label: {
                        Label(lvl.rawValue.uppercased(), systemImage: lvl.symbol)
                    }
                }
            } label: {
                Label(filter?.rawValue.uppercased() ?? "ALL",
                      systemImage: filter?.symbol ?? "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)

            Toggle(isOn: $autoscroll) {
                Label("Autoscroll", systemImage: "arrow.down.to.line")
            }
            .toggleStyle(.button)
            .buttonStyle(.glass)

            Button {
                copyToClipboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.glass)

            Button(role: .destructive) {
                log.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.glass)
        }
        .padding(14)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { line in
                        ConsoleLineView(line: line)
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: log.lines.count) { _, _ in
                guard autoscroll, let last = filtered.last else { return }
                withAnimation(.linear(duration: 0.15)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .glassEffect(.regular.tint(.black.opacity(0.18)),
                     in: .rect(cornerRadius: 14))
        .padding([.horizontal, .bottom], 14)
    }

    private var filtered: [DebugLog.Line] {
        guard let f = filter else { return log.lines }
        return log.lines.filter { $0.level == f }
    }

    private func copyToClipboard() {
        let text = filtered.map(formatLine).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func formatLine(_ line: DebugLog.Line) -> String {
        let ts = ISO8601DateFormatter().string(from: line.timestamp)
        return "\(ts) [\(line.level.rawValue.uppercased())] \(line.scope): \(line.message)"
    }
}

private struct ConsoleLineView: View {
    let line: DebugLog.Line

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeString)
                .font(TF.mono(10))
                .foregroundStyle(.primary.opacity(0.72))
                .frame(width: 64, alignment: .leading)
            Image(systemName: line.level.symbol)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(line.scope)
                .font(TF.mono(10))
                .foregroundStyle(.primary.opacity(0.70))
                .frame(width: 130, alignment: .leading)
            Text(line.message)
                .font(TF.mono(11))
                .foregroundStyle(.primary.opacity(0.92))
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }

    private var color: Color {
        switch line.level {
        case .info:  return .blue
        case .ok:    return .green
        case .warn:  return .orange
        case .error: return .red
        case .run:   return .purple
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: line.timestamp)
    }
}
