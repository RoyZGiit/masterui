import SwiftUI

// MARK: - SettingsView

/// The settings interface for managing AI targets and app preferences.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .targets
    @State private var showAddSheet = false

    var body: some View {
        TabView(selection: $selectedTab) {
            targetsTab
                .tabItem {
                    Label("AI Targets", systemImage: "list.bullet")
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
        .sheet(isPresented: $showAddSheet) {
            AddServiceSheet()
                .environmentObject(appState)
        }
    }

    // MARK: - Targets Tab

    private var targetsTab: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Configured AI Targets")
                    .font(.headline)
                Spacer()
                Button(action: { showAddSheet = true }) {
                    Label("Add Target", systemImage: "plus")
                }
            }
            .padding()

            Divider()

            // Target list
            List {
                ForEach(appState.targets) { target in
                    TargetRow(target: target)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        appState.removeTarget(id: appState.targets[index].id)
                    }
                }
                .onMove { from, to in
                    appState.targets.move(fromOffsets: from, toOffset: to)
                }
            }

            Divider()

            // Accessibility status
            accessibilityStatus
        }
    }

    // MARK: - Target Row

    private struct TargetRow: View {
        let target: AITarget
        @EnvironmentObject var appState: AppState
        @State private var isExpanded = false

        var body: some View {
            DisclosureGroup(isExpanded: $isExpanded) {
                targetDetails
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: target.iconSymbol)
                        .foregroundStyle(Color(hex: target.colorHex) ?? .accentColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(target.name)
                                .font(.system(size: 13, weight: .medium))
                            if target.type == .cliTool {
                                Text("CLI")
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(target.type == .cliTool ? target.executablePath : target.bundleID)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if target.type == .guiApp {
                        let isRunning = AccessibilityService.shared.isAppRunning(bundleID: target.bundleID)
                        Circle()
                            .fill(isRunning ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                    } else {
                        let execExists = FileManager.default.isExecutableFile(atPath: target.executablePath)
                        Circle()
                            .fill(execExists ? Color.blue : Color.gray)
                            .frame(width: 8, height: 8)
                            .help(execExists ? "Executable found" : "Executable not found")
                    }

                    Toggle("", isOn: Binding(
                        get: { target.isEnabled },
                        set: { newValue in
                            var updated = target
                            updated.isEnabled = newValue
                            appState.updateTarget(updated)
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }

        private var targetDetails: some View {
            VStack(alignment: .leading, spacing: 8) {
                // Send method
                HStack {
                    Text("Send Method:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { target.sendMethod },
                        set: { newValue in
                            var updated = target
                            updated.sendMethod = newValue
                            appState.updateTarget(updated)
                        }
                    )) {
                        ForEach(SendMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 250)
                }

                // Element locator status
                HStack(spacing: 16) {
                    locatorStatus("Input", target.inputLocator)
                    locatorStatus("Output", target.outputLocator)
                }

                // Pick elements button
                Button(action: {
                    appState.pickerTargetID = target.id
                    appState.pickerStep = .selectInput
                    appState.isPickingElement = true
                }) {
                    Label("Pick Elements", systemImage: "scope")
                }
                .controlSize(.small)
                .help("Interactively select input/output elements in the target app")

                // Debug: dump AX tree
                Button(action: {
                    let tree = ElementFinder.shared.dumpTree(bundleID: target.bundleID)
                    print(tree)
                }) {
                    Label("Dump AX Tree (Console)", systemImage: "ladybug")
                }
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
            .padding(.leading, 36)
            .padding(.vertical, 4)
        }

        private func locatorStatus(_ label: String, _ locator: ElementLocator) -> some View {
            HStack(spacing: 4) {
                Image(systemName: locator.isConfigured ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(locator.isConfigured ? .green : .orange)
                    .font(.system(size: 11))
                Text("\(label): \(locator.role ?? "auto")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
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

    // MARK: - Accessibility Status

    private var accessibilityStatus: some View {
        HStack(spacing: 8) {
            let hasPermission = PermissionsManager.shared.hasAccessibilityPermission
            Image(systemName: hasPermission ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .foregroundStyle(hasPermission ? .green : .orange)

            Text(hasPermission ? "Accessibility access granted" : "Accessibility access required")
                .font(.system(size: 12))
                .foregroundColor(hasPermission ? .secondary : .orange)

            Spacer()

            if !hasPermission {
                Button("Open Settings") {
                    PermissionsManager.shared.openAccessibilitySettings()
                }
                .controlSize(.small)
            }
        }
        .padding()
    }
}

// MARK: - SettingsTab

enum SettingsTab {
    case targets
    case shortcuts
    case about
}
