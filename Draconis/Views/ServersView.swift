import SwiftUI

struct ServersView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            header
            list
        }
        .task { await env.refreshServers() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search servers, maps, playlists…", text: $env.serverFilter)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)

            Button {
                Task { await env.refreshServers() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.glass)

            Spacer()

            Text("\(env.filteredServers.count) servers")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if env.serversLoading && env.servers.isEmpty {
                    ProgressView("Querying masterserver…").padding(40)
                } else if env.filteredServers.isEmpty {
                    Text("No servers match.")
                        .foregroundStyle(.secondary)
                        .padding(40)
                } else {
                    ForEach(env.filteredServers) { server in
                        ServerRow(server: server)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}

private struct ServerRow: View {
    let server: NorthstarServer

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(server.name)
                        .font(.headline)
                        .lineLimit(1)
                    if server.hasPassword {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if !server.description.isEmpty {
                    Text(server.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Label(server.map, systemImage: "map.fill")
                    Label(server.playlist, systemImage: "list.bullet.rectangle")
                    if let region = server.region, !region.isEmpty {
                        Label(region, systemImage: "globe")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(server.playerCount) / \(server.maxPlayers)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                Text("players")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
