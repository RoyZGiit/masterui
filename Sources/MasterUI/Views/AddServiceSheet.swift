import SwiftUI

// MARK: - AddServiceSheet

/// Sheet for adding a new AI target - either from presets or custom.
struct AddServiceSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AddMode = .preset
    @State private var customName: String = ""
    @State private var customBundleID: String = ""
    
    // CLI Fields
    @State private var customCLIPath: String = ""
    @State private var customCLIArgs: String = "" // Space separated
    @State private var customCLIWorkDir: String = ""
    
    @State private var customIconSymbol: String = "bubble.left.fill"
    @State private var customColorHex: String = "#007AFF"
    @State private var selectedPresets: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add AI Target")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            // Mode picker
            Picker("", selection: $mode) {
                Text("From Presets").tag(AddMode.preset)
                Text("GUI App").tag(AddMode.customGUI)
                Text("CLI Tool").tag(AddMode.customCLI)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)

            // Content
            if mode == .preset {
                presetList
            } else if mode == .customGUI {
                customGUIForm
            } else {
                customCLIForm
            }

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Add") {
                    addTargets()
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!canAdd)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 550)
    }

    // MARK: - Preset List

    private var presetList: some View {
        List {
            let existingBundleIDs = Set(appState.targets.map { $0.bundleID })

            ForEach(PresetTargets.all) { preset in
                let isExisting = existingBundleIDs.contains(preset.bundleID)

                HStack(spacing: 12) {
                    Image(systemName: preset.iconSymbol)
                        .foregroundStyle(Color(hex: preset.colorHex) ?? .accentColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name)
                            .font(.system(size: 13, weight: .medium))
                        Text(preset.bundleID)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isExisting {
                        Text("Added")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { selectedPresets.contains(preset.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedPresets.insert(preset.id)
                                } else {
                                    selectedPresets.remove(preset.id)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
                .opacity(isExisting ? 0.5 : 1.0)
            }
        }
    }

    // MARK: - Custom GUI Form

    private var customGUIForm: some View {
        Form {
            Section("App Information") {
                TextField("Name", text: $customName)
                    .textFieldStyle(.roundedBorder)

                TextField("Bundle ID", text: $customBundleID)
                    .textFieldStyle(.roundedBorder)
                    .help("e.g., com.example.aiapp")
            }

            Section("Appearance") {
                TextField("SF Symbol", text: $customIconSymbol)
                    .textFieldStyle(.roundedBorder)

                TextField("Color Hex", text: $customColorHex)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                Text("After adding, use 'Pick Elements' in Settings to configure fields.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
    }
    
    // MARK: - Custom CLI Form

    private var customCLIForm: some View {
        Form {
            Section("CLI Information") {
                TextField("Name", text: $customName)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Executable Path", text: $customCLIPath)
                    .textFieldStyle(.roundedBorder)
                    .help("Full path, e.g., /usr/local/bin/claude")
                
                TextField("Arguments", text: $customCLIArgs)
                    .textFieldStyle(.roundedBorder)
                    .help("Space separated, e.g., --chat")
                
                TextField("Working Directory", text: $customCLIWorkDir)
                    .textFieldStyle(.roundedBorder)
                    .help("Optional, defaults to home")
            }

            Section("Appearance") {
                TextField("SF Symbol", text: $customIconSymbol)
                    .textFieldStyle(.roundedBorder)

                TextField("Color Hex", text: $customColorHex)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
    }

    // MARK: - Logic

    private var canAdd: Bool {
        switch mode {
        case .preset:
            return !selectedPresets.isEmpty
        case .customGUI:
            return !customName.isEmpty && !customBundleID.isEmpty
        case .customCLI:
            return !customName.isEmpty && !customCLIPath.isEmpty
        }
    }

    private func addTargets() {
        if mode == .preset {
            for preset in PresetTargets.all where selectedPresets.contains(preset.id) {
                appState.addTarget(preset)
            }
        } else if mode == .customGUI {
            let target = AITarget(
                name: customName,
                type: .guiApp,
                bundleID: customBundleID,
                iconSymbol: customIconSymbol,
                colorHex: customColorHex
            )
            appState.addTarget(target)
        } else if mode == .customCLI {
            let args = customCLIArgs.split(separator: " ").map { String($0) }
            let target = AITarget(
                name: customName,
                type: .cliTool,
                executablePath: customCLIPath,
                arguments: args,
                workingDirectory: customCLIWorkDir.isEmpty ? nil : customCLIWorkDir,
                iconSymbol: "terminal.fill",
                colorHex: customColorHex
            )
            appState.addTarget(target)
        }
    }
}

// MARK: - AddMode

enum AddMode {
    case preset
    case customGUI
    case customCLI
}
