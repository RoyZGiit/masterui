import SwiftUI

// MARK: - SessionHistoryView

/// Displays the cleaned conversation history for a CLI session.
struct SessionHistoryView: View {
    @ObservedObject var session: CLISession

    var body: some View {
        if session.history.blocks.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(session.history.blocks) { block in
                            HistoryBlockView(block: block)
                                .id(block.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: session.history.blocks.count) {
                    if let last = session.history.blocks.last {
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

// MARK: - HistoryBlockView

/// Renders a single history block with sender and timestamp metadata.
struct HistoryBlockView: View {
    let block: SessionBlock

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: block.timestamp)
    }

    private var senderLabel: String {
        block.role == .user ? "You" : "Assistant"
    }

    private var contentFont: Font {
        block.role == .user ? .system(size: 12) : .system(size: 12, design: .monospaced)
    }

    private var bubbleColor: Color {
        block.role == .user
            ? Color.accentColor.opacity(0.1)
            : Color(nsColor: .controlBackgroundColor).opacity(0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(senderLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timeString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Text(block.content)
                .font(contentFont)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(bubbleColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
