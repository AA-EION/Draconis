import DraconisCore
import Foundation
import SwiftCrossUI

struct ConsoleView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Stencil("Console")
                Spacer()
                GlassButton(title: "Clear", icon: "x", size: 13) { model.console.removeAll() }
            }
            ForEach(model.console.suffix(400)) { line in
                Text("\(Self.time(line.time))  \(line.level.rawValue.uppercased())  \(line.scope): \(line.message)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(line.level == .error ? Color(red: 1, green: 0.5, blue: 0.5)
                                     : line.level == .ok ? Color(red: 0.6, green: 0.95, blue: 0.7) : Theme.secondary)
            }
        }
        .glassCard()
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
