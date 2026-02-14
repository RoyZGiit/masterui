import SwiftUI
import AppKit

// MARK: - GroupChatDebugLogView

struct GroupChatDebugLogView: View {
    @ObservedObject var chat: GroupChatSession

    @State private var tailLines: [String] = []
    @State private var filterText: String = ""
    @State private var autoScroll = true
    @State private var showCopiedPath = false
    @State private var fileOffset: UInt64 = 0

    private static let maxDisplayLines = 500
    private let refreshTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    private var logPath: String {
        GroupChatHistoryStore.shared.debugLogFilePath(for: chat)
    }

    private var displayedLines: [String] {
        let normalizedFilter = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFilter.isEmpty else { return tailLines }
        return tailLines.filter { $0.localizedCaseInsensitiveContains(normalizedFilter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(displayedLines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: tailLines.count) {
                    if autoScroll, let last = displayedLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .onAppear { loadTail() }
        .onReceive(refreshTimer) { _ in loadIncremental() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Debug Log")
                .font(.system(size: 12, weight: .semibold))

            TextField("Filter", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(width: 180)

            Toggle("Auto scroll", isOn: $autoScroll)
                .toggleStyle(.switch)
                .font(.system(size: 11))

            Spacer()

            Button {
                NSWorkspace.shared.selectFile(logPath, inFileViewerRootedAtPath: "")
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(logPath, forType: .string)
                showCopiedPath = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopiedPath = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showCopiedPath ? "checkmark" : "doc.on.doc")
                    Text(showCopiedPath ? "Copied" : "Copy Path")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .help(logPath)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    // MARK: - Incremental file reading

    /// Initial load: read last N lines from file.
    private func loadTail() {
        let url = URL(fileURLWithPath: logPath)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            tailLines = []
            fileOffset = 0
            return
        }
        defer { try? handle.close() }

        let endOffset = handle.seekToEndOfFile()
        let readSize: UInt64 = min(endOffset, 256 * 1024)
        let startPos = endOffset - readSize
        handle.seek(toFileOffset: startPos)
        let data = handle.readData(ofLength: Int(readSize))
        fileOffset = endOffset

        if let text = String(data: data, encoding: .utf8) {
            var lines = text.components(separatedBy: .newlines)
            if startPos > 0 { lines.removeFirst() }
            if lines.last?.isEmpty == true { lines.removeLast() }
            if lines.count > Self.maxDisplayLines {
                lines = Array(lines.suffix(Self.maxDisplayLines))
            }
            tailLines = lines
        }
    }

    /// Incremental: read only new bytes appended since last read.
    private func loadIncremental() {
        let url = URL(fileURLWithPath: logPath)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let endOffset = handle.seekToEndOfFile()
        guard endOffset > fileOffset else {
            if endOffset < fileOffset { loadTail() }
            return
        }

        handle.seek(toFileOffset: fileOffset)
        let data = handle.readData(ofLength: Int(endOffset - fileOffset))
        fileOffset = endOffset

        if let text = String(data: data, encoding: .utf8) {
            var newLines = text.components(separatedBy: .newlines)
            if newLines.last?.isEmpty == true { newLines.removeLast() }
            guard !newLines.isEmpty else { return }

            var combined = tailLines + newLines
            if combined.count > Self.maxDisplayLines {
                combined = Array(combined.suffix(Self.maxDisplayLines))
            }
            tailLines = combined
        }
    }
}