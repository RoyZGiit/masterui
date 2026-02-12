import SwiftUI

// MARK: - ClosedSessionHistoryView

/// Read-only view of a closed session's conversation history.
struct ClosedSessionHistoryView: View {
    let closedSession: ClosedSession
    @State private var history: SessionHistory?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let history, !history.blocks.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(history.blocks) { block in
                            HistoryBlockView(block: block)
                        }
                    }
                    .padding(16)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
            } else {
                emptyState
            }
        }
        .onAppear {
            history = SessionHistoryStore.shared.load(sessionID: closedSession.id)
        }
        .onChange(of: closedSession.id) {
            history = SessionHistoryStore.shared.load(sessionID: closedSession.id)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "archivebox")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Text(closedSession.displayTitle)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Text("(closed)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Spacer()

            Text(closedSession.updatedAt, style: .date)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "archivebox")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No History")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("This closed session has no recorded conversation history.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
