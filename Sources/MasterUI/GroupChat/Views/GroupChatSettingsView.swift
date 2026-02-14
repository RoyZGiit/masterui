import SwiftUI
import AppKit

// MARK: - GroupChatSettingsView

struct GroupChatSettingsView: View {
    @ObservedObject private var config = GroupChatPromptConfig.shared

    @State private var showSaved = false
    @State private var showReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                promptTemplateSection
                passKeywordSection
                placeholderReference
                actionButtons
            }
            .padding(20)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Group Chat Prompt Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(GroupChatPromptConfig.configPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("These settings control the prompt injected into each participant's terminal during group chat rounds.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var promptTemplateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prompt Template")
                .font(.system(size: 12, weight: .medium))

            TextEditor(text: $config.promptTemplate)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1))
                )
        }
    }

    private var passKeywordSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pass Keyword")
                .font(.system(size: 12, weight: .medium))
            Text("When a participant replies with this exact text, it means they have nothing to contribute this round.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField("[PASS]", text: $config.passKeyword)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 200)
        }
    }

    private var placeholderReference: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Available Placeholders")
                .font(.system(size: 12, weight: .medium))

            VStack(alignment: .leading, spacing: 4) {
                placeholderRow("{{MY_NAME}}", "This participant's display name")
                placeholderRow("{{PARTICIPANTS}}", "Comma-separated list of other participants")
                placeholderRow("{{HISTORY_PATH}}", "Absolute path to the history JSON file")
                placeholderRow("{{NEW_MESSAGE_COUNT}}", "Number of new messages since last turn")
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.03))
            )
        }
    }

    private func placeholderRow(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 16) {
            Text(key)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .frame(width: 180, alignment: .leading)
            Text(desc)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                config.save()
                showSaved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showSaved = false }
            } label: {
                Text(showSaved ? "Saved" : "Save")
            }
            .buttonStyle(.borderedProminent)

            Button {
                config.reload()
            } label: {
                Text("Reload from Disk")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                showReset = true
            } label: {
                Text("Reset to Defaults")
            }
            .buttonStyle(.bordered)
            .alert("Reset prompt settings?", isPresented: $showReset) {
                Button("Reset", role: .destructive) { config.resetToDefaults() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will overwrite your custom prompt template and pass keyword with the built-in defaults.")
            }

            Spacer()

            Button {
                NSWorkspace.shared.selectFile(GroupChatPromptConfig.configPath, inFileViewerRootedAtPath: "")
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .buttonStyle(.plain)
        }
    }
}
