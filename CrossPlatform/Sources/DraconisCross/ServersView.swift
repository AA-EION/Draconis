import DraconisCore
import SwiftCrossUI

struct ServersView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SearchField(placeholder: "Search servers, maps, playlists…", width: 320, query: $model.serverFilter)
                GlassButton(title: model.serversLoading ? "Loading…" : "Refresh", icon: "refresh-cw", size: 13) { Task { await model.refreshServers() } }
                Spacer()
                Stencil("\(model.filteredServers.count) servers")
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
                    Text("\(server.playerCount)/\(server.maxPlayers)").display(17)
                }
                .glassCard(radius: 14)
            }
        }
        .task { if model.servers.isEmpty { await model.refreshServers() } }
    }
}
