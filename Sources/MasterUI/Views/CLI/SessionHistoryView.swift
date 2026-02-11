import SwiftUI

// MARK: - SessionHistoryView

/// Displays the cleaned conversation history for a CLI session.
struct SessionHistoryView: View {
    @ObservedObject var session: CLISession

    var body: some View {
        if session.history.turns.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(session.history.turns) { turn in
                            TurnView(turn: turn)
                                .id(turn.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: session.history.turns.count) {
                    if let last = session.history.turns.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No History Yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Interact with the terminal and conversation\nturns will appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - TurnView

/// Renders a single turn: user input bubble + assistant output bubble.
private struct TurnView: View {
    let turn: SessionTurn

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: turn.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // User input
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("You")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(timeString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text(turn.input)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Assistant output
            VStack(alignment: .leading, spacing: 4) {
                Text("Assistant")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(turn.output)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
