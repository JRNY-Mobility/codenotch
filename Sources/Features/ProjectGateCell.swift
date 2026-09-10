import SwiftUI

/// The project gate cell: one ring in the notch fleet that reads the WIP cap.
///
/// Reuses the same `ProviderRing` shape as providers — `usedFraction` is the
/// active share of the cap, the glyph is a simple count mark, and the tooltip
/// lists every project with a Complete / Defer action per row.
struct ProjectGateCell: View {
    /// The store the cell reads from; owned by the view model.
    let store: ProjectStore
    /// Re-reads on each body evaluation; the cell is refreshed by the fleet's
    /// poller, so counts stay live while the app runs.
    @Environment(\.self) private var environment

    private var state: ProjectGateState { store.gateState() }
    private var fraction: Double { Double(state.active) / Double(max(state.cap, 1)) }

    var body: some View {
        ProviderRing(
            usedFraction: fraction,
            glyph: .gate,
            isStale: false,
            isBlocked: state.isAtCap,
            activity: nil,
            isRefreshing: false,
            localPerformance: nil,
            weeklyFraction: nil,
            weeklyRing: .off
        )
        .accessibilityLabel("Project gate \(state.active) of \(state.cap) active")
    }
}

/// The gate's entry in the tooltip card: count line plus one row per project
/// with Complete and Defer actions wired back into the store.
struct ProjectGateTooltip: View {
    let store: ProjectStore
    let onChanged: () -> Void

    private var state: ProjectGateState { store.gateState() }
    private var projects: [Project] { store.list() }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.px(8)) {
            HStack {
                Text("Project Gate")
                    .font(.headline)
                Spacer()
                Text("\(state.active)/\(state.cap) active")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(state.isAtCap ? .red : .secondary)
            }

            if projects.isEmpty {
                Text("No projects yet — run `codenotch project add \"title\"` to open one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(projects) { project in
                    ProjectRow(project: project, store: store, onChanged: onChanged)
                }
            }
        }
        .padding(Design.px(10))
    }
}

private struct ProjectRow: View {
    let project: Project
    let store: ProjectStore
    let onChanged: () -> Void

    private var statusText: String {
        switch project.status {
        case .active: return "active"
        case .deferred: return "deferred"
        case .completed: return "done"
        }
    }

    var body: some View {
        HStack(spacing: Design.px(8)) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(project.title)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if project.status != .completed {
                Button("Done") {
                    _ = store.complete(id: project.id)
                    onChanged()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            if project.status == .active {
                Button("Defer") {
                    // Defer to tomorrow by default from the UI; the CLI offers
                    // the exact date. A slot is freed either way.
                    _ = store.defer(id: project.id, until: Date().addingTimeInterval(86_400))
                    onChanged()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private var statusColor: Color {
        switch project.status {
        case .active: return .orange
        case .deferred: return .blue
        case .completed: return .green
        }
    }
}
