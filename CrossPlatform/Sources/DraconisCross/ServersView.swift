import DraconisCore
import SwiftCrossUI

struct ServersView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Search servers, maps, playlists…", text: $model.serverFilter).frame(width: 320)
                Button(model.serversLoading ? "Loading…" : "Refresh") { Task { await model.refreshServers() } }.fixedSize()
                Spacer()
                Text("\(model.filteredServers.count) SERVERS").stencil()
            }
            if model.serversLoading && model.servers.isEmpty {
                ProgressView("Querying the master server…")
            }
            ForEach(model.filteredServers) { server in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.hasPassword ? "🔒 \(server.displayName)" : server.displayName)
                            .font(.system(size: 15, weight: .semibold))
                        if !server.displayDescription.isEmpty {
                            Text(server.displayDescription).foregroundColor(Theme.secondary)
                        }
                        Text("\(server.map) · \(server.playlist)\(server.region.map { " · \($0)" } ?? "")")
                            .foregroundColor(Theme.faint)
                    }
                    Spacer()
                    Text("\(server.playerCount)/\(server.maxPlayers)").font(.system(size: 18, weight: .bold))
                }
                .glassCard(radius: 14)
            }
        }
        .task { if model.servers.isEmpty { await model.refreshServers() } }
    }
}
