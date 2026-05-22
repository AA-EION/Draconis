import SwiftUI

struct BugReportSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var description: String = ""
    @State private var reporterName: String = ""
    @State private var reporterContact: String = ""
    @State private var showingContext: Bool = false
    @State private var submitting: Bool = false
    @State private var submitted: Bool = false
    @State private var submitError: String?

    private var context: BugReportContext { BugReportContext.capture(from: env) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.primary.opacity(0.12))
            if submitted {
                successView
            } else {
                ScrollView {
                    formBody
                        .padding(24)
                }
            }
        }
        .frame(width: 560, height: submitted ? 320 : 580)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Report a Bug")
                    .font(TF.hero(18))
                Text("Your report goes to the Draconis development team.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Form

    private var formBody: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Auto-collected context summary
            contextSummary

            // Description (required)
            VStack(alignment: .leading, spacing: 6) {
                Label("What happened?", systemImage: "text.alignleft")
                    .font(.callout.weight(.semibold))
                TextEditor(text: $description)
                    .font(.callout)
                    .frame(minHeight: 100)
                    .padding(10)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.12))
                    )
                if description.isEmpty {
                    Text("Describe what you were doing and what went wrong…")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .padding(.top, -84)
                        .padding(.leading, 14)
                }
            }

            // Optional reporter info
            VStack(alignment: .leading, spacing: 6) {
                Label("Your name (optional)", systemImage: "person")
                    .font(.callout.weight(.semibold))
                TextField("Display name or alias", text: $reporterName)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Contact (optional)", systemImage: "envelope")
                    .font(.callout.weight(.semibold))
                TextField("Email, Discord tag, GitHub username, etc.", text: $reporterContact)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
                Text("Only used to follow up on your report. Never shared beyond the bug-tracking system.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let err = submitError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
            }

            // Submit / Cancel
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                Spacer()
                Button {
                    Task { await submit() }
                } label: {
                    if submitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Send Report", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.glass)
                .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting)
            }
        }
    }

    // MARK: - Context summary

    private var contextSummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showingContext.toggle() }
            } label: {
                HStack {
                    Label("Auto-collected context", systemImage: "info.circle")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Image(systemName: showingContext ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if showingContext {
                Divider().overlay(.primary.opacity(0.10))
                VStack(alignment: .leading, spacing: 4) {
                    contextRow("App version", context.appVersion)
                    contextRow("CrossOver installed", context.crossOverInstalled ? "Yes" : "No")
                    contextRow("Bottle exists", context.bottleExists ? "Yes" : "No")
                    if context.bottleExists {
                        contextRow("Has Titanfall 2", context.hasTitanfall2 ? "Yes" : "No")
                        contextRow("Has Northstar", context.hasNorthstar ? "Yes" : "No")
                        if let v = context.northstarVersion { contextRow("Northstar version", v) }
                        contextRow("Has Steam", context.hasSteam ? "Yes" : "No")
                        contextRow("Has EA App", context.hasEAApp ? "Yes" : "No")
                        contextRow("Has Maxima", context.hasMaxima ? "Yes" : "No")
                        contextRow("Maxima role", context.maximaRole)
                        if let v = context.maximaInstalledVersion { contextRow("Maxima version", v) }
                        contextRow("Maxima phase", context.maximaSetupPhaseLabel)
                    }
                    if let e = context.lastLaunchError { contextRow("Last launch error", e) }
                    if let e = context.lastUpdateError { contextRow("Last update error", e) }
                    if let e = context.maximaError     { contextRow("Last Maxima error", e) }
                    contextRow("Console lines included", "\(context.recentLogs.count)")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.10)))
    }

    private func contextRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
            Text("Report sent")
                .font(TF.hero(20))
            Text("Thank you. The Draconis team will review your report.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Close") { dismiss() }
                .buttonStyle(.glass)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Submit

    @MainActor
    private func submit() async {
        submitting = true
        submitError = nil
        let snap = BugReportContext.capture(from: env)
        let report = BugReporter.Report(
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            reporterName: reporterName.isEmpty ? nil : reporterName,
            reporterContact: reporterContact.isEmpty ? nil : reporterContact
        )
        await BugReporter.shared.submit(report, context: snap)
        submitting = false
        submitted = true
    }
}
