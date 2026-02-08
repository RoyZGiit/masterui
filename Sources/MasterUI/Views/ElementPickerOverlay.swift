import AppKit
import SwiftUI

// MARK: - ElementPickerOverlay

/// An interactive overlay that lets users click on UI elements in other apps
/// to configure input/output element locators for a custom AI target.
struct ElementPickerOverlay: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveredElementInfo: ElementInfo?
    @State private var mouseLocation: CGPoint = .zero
    @State private var selectedInputLocator: ElementLocator?
    @State private var selectedOutputLocator: ElementLocator?

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Instructions
                instructionsCard

                Spacer()

                // Hovered element info
                if let info = hoveredElementInfo {
                    elementInfoCard(info)
                }

                // Action buttons
                actionButtons
            }
            .padding(24)
        }
        .onAppear {
            startTracking()
        }
        .onDisappear {
            stopTracking()
        }
    }

    // MARK: - Instructions

    private var instructionsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: appState.pickerStep == .selectInput ? "text.cursor" : "text.bubble")
                .font(.system(size: 24))
                .foregroundStyle(.white)

            Text(appState.pickerStep == .selectInput
                 ? "Click on the AI app's INPUT field"
                 : "Click on the AI app's OUTPUT area")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Move your mouse over the target element and click to select it.\nPress Escape to cancel.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(.ultraThinMaterial.opacity(0.8))
        .background(Color.accentColor.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Element Info Card

    private func elementInfoCard(_ info: ElementInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Detected Element")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Group {
                infoRow("Role", info.role)
                infoRow("Title", info.title)
                infoRow("Identifier", info.identifier)
                infoRow("Description", info.description)
                infoRow("Value", String(info.value.prefix(100)))
            }
        }
        .padding(16)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                cancelPicker()
            }
            .keyboardShortcut(.escape, modifiers: [])

            if hoveredElementInfo != nil {
                Button(appState.pickerStep == .selectInput ? "Select as Input" : "Select as Output") {
                    confirmSelection()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Tracking

    private var trackingTimer: Timer? {
        nil // Managed externally
    }

    private func startTracking() {
        // Poll mouse position and inspect element underneath
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { timer in
            guard appState.isPickingElement else {
                timer.invalidate()
                return
            }

            let location = NSEvent.mouseLocation
            // Convert from bottom-left to top-left coordinate system
            guard let screen = NSScreen.main else { return }
            let flippedY = screen.frame.height - location.y

            if let element = AccessibilityService.shared.elementAtPosition(CGPoint(x: location.x, y: flippedY)) {
                let info = ElementInfo(
                    role: element.role ?? "",
                    title: element.title ?? "",
                    identifier: element.identifier ?? "",
                    description: element.axDescription ?? "",
                    value: element.value ?? ""
                )
                DispatchQueue.main.async {
                    self.hoveredElementInfo = info
                    self.mouseLocation = location
                }
            }
        }
    }

    private func stopTracking() {
        // Timer will self-invalidate when isPickingElement becomes false
    }

    private func confirmSelection() {
        guard let info = hoveredElementInfo else { return }

        let locator = ElementLocator(
            role: info.role.isEmpty ? nil : info.role,
            identifier: info.identifier.isEmpty ? nil : info.identifier,
            titlePattern: info.title.isEmpty ? nil : NSRegularExpression.escapedPattern(for: info.title),
            descriptionPattern: info.description.isEmpty ? nil : NSRegularExpression.escapedPattern(for: info.description),
            deepSearch: true
        )

        if appState.pickerStep == .selectInput {
            selectedInputLocator = locator
            appState.pickerStep = .selectOutput
        } else {
            selectedOutputLocator = locator

            // Save both locators to the target
            if let targetID = appState.pickerTargetID,
               let inputLocator = selectedInputLocator {
                if var target = appState.targets.first(where: { $0.id == targetID }) {
                    target.inputLocator = inputLocator
                    target.outputLocator = locator
                    appState.updateTarget(target)
                }
            }

            // Done
            finishPicker()
        }
    }

    private func cancelPicker() {
        finishPicker()
    }

    private func finishPicker() {
        appState.isPickingElement = false
        appState.pickerStep = .selectInput
        appState.pickerTargetID = nil
    }
}

// MARK: - ElementInfo

struct ElementInfo {
    let role: String
    let title: String
    let identifier: String
    let description: String
    let value: String
}
