import SwiftUI

// MARK: - SettingsView

/// The settings interface with CLI toggle + JSON editor.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .targets

    var body: some View {
        TabView(selection: $selectedTab) {
            targetsTab
                .tabItem {
                    Label("CLI Tools", systemImage: "terminal")
                }
                .tag(SettingsTab.targets)

            shortcutsTab
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag(SettingsTab.shortcuts)

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(minWidth: 550, minHeight: 400)
    }

    // MARK: - Targets Tab

    @State private var jsonConfigText: String = ""
    @State private var jsonValidationStatus: JSONValidationStatus = .empty
    @State private var hasUnsavedChanges: Bool = false

    private var targetsTab: some View {
        VStack(spacing: 0) {
            // Toggle
            HStack {
                Toggle("Enable CLI Tools", isOn: $appState.cliEnabled)
                    .toggleStyle(.switch)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // JSON Editor
            VStack(spacing: 0) {
                HStack {
                    Text("CLI Tool Configuration")
                        .font(.headline)
                    Spacer()
                    Text("File: \(appState.configFilePath)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

                JSONTextEditor(
                    text: $jsonConfigText,
                    onTextChange: {
                        validateJSON()
                        hasUnsavedChanges = true
                    },
                    onTextDidEndEditing: {
                        formatJSONIfValid()
                    },
                    onSaveCommand: {
                        saveConfig()
                    },
                    onFormatCommand: {
                        formatJSONIfValid()
                    }
                )
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
            }

            Divider()
                .padding(.top, 8)

            // Status + Actions
            HStack(spacing: 12) {
                // Validation status
                switch jsonValidationStatus {
                case .valid(let count):
                    Label("\(count) tool(s) configured", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                case .error(let message):
                    Label(message, systemImage: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                case .empty:
                    Label("Enter JSON configuration", systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Reset to Defaults") {
                    jsonConfigText = appState.defaultConfigJSON()
                    validateJSON()
                    hasUnsavedChanges = true
                }
                .controlSize(.small)

                Button("Format JSON") {
                    formatJSONIfValid()
                }
                .controlSize(.small)
                .disabled(jsonConfigText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Cmd+Shift+F")

                Button("Save & Apply") {
                    saveConfig()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSave)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onAppear {
            loadConfigForEditing()
        }
    }

    private var canSave: Bool {
        if case .valid = jsonValidationStatus {
            return hasUnsavedChanges
        }
        return false
    }

    private func loadConfigForEditing() {
        let configs = appState.loadCLIConfigs()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(configs),
           let text = String(data: data, encoding: .utf8) {
            jsonConfigText = text
        } else {
            jsonConfigText = appState.defaultConfigJSON()
        }
        validateJSON()
        hasUnsavedChanges = false
    }

    private func validateJSON() {
        if jsonConfigText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            jsonValidationStatus = .empty
            return
        }
        do {
            let configs = try parseConfigs(from: jsonConfigText)
            jsonValidationStatus = .valid(count: configs.count)
        } catch {
            jsonValidationStatus = .error(error.localizedDescription)
        }
    }

    private func parseConfigs(from text: String) throws -> [CLIToolConfig] {
        guard let data = text.data(using: .utf8) else {
            throw JSONEditorError.invalidEncoding
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
        } catch let syntaxError as NSError {
            let message = syntaxError.localizedDescription
            throw JSONEditorError.invalidSyntax("Invalid JSON syntax: \(message)")
        }
        do {
            return try JSONDecoder().decode([CLIToolConfig].self, from: data)
        } catch let decodingError as DecodingError {
            throw JSONEditorError.schemaError(readableDecodingError(decodingError))
        } catch {
            throw JSONEditorError.schemaError("Schema mismatch: \(error.localizedDescription)")
        }
    }

    private func readableDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing required key '\(key.stringValue)' at \(codingPathString(context.codingPath))"
        case .typeMismatch(_, let context):
            return "Type mismatch at \(codingPathString(context.codingPath)): \(context.debugDescription)"
        case .valueNotFound(_, let context):
            return "Missing value at \(codingPathString(context.codingPath)): \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "Invalid value at \(codingPathString(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private func codingPathString(_ path: [CodingKey]) -> String {
        if path.isEmpty { return "root" }
        return path.map { key in
            if let index = key.intValue {
                return "[\(index)]"
            }
            return key.stringValue
        }
        .joined(separator: ".")
        .replacingOccurrences(of: ".[", with: "[")
    }

    private func formatJSONIfValid() {
        guard case .valid = jsonValidationStatus else { return }
        guard let data = jsonConfigText.data(using: .utf8) else { return }
        guard
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let formattedData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let formattedText = String(data: formattedData, encoding: .utf8)
        else {
            return
        }
        guard formattedText != jsonConfigText else { return }
        jsonConfigText = formattedText
        hasUnsavedChanges = true
        validateJSON()
    }

    private func saveConfig() {
        formatJSONIfValid()
        guard let configs = try? parseConfigs(from: jsonConfigText) else {
            return
        }
        appState.applyCLIConfigs(configs)
        hasUnsavedChanges = false
        validateJSON()
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTab: some View {
        Form {
            Section("Global Shortcuts") {
                HStack {
                    Text("Toggle Panel:")
                    Spacer()
                    Text("Cmd + Shift + Space")
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            Section {
                Text("Global shortcut is currently fixed to Cmd+Shift+Space.\nCustomization will be available in a future update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("MasterUI")
                .font(.title)
                .fontWeight(.bold)

            Text("Universal AI Chat Aggregator")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Version 1.0.0")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()
                .frame(width: 200)

            Text("Aggregate AI chat inputs from multiple apps into one unified interface.\nPowered by macOS Accessibility API.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Supporting Types

enum SettingsTab {
    case targets
    case shortcuts
    case about
}

enum JSONValidationStatus {
    case valid(count: Int)
    case error(String)
    case empty
}

enum JSONEditorError: LocalizedError {
    case invalidEncoding
    case invalidSyntax(String)
    case schemaError(String)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Invalid UTF-8 encoding"
        case .invalidSyntax(let message):
            return message
        case .schemaError(let message):
            return "Invalid config structure: \(message)"
        }
    }
}
