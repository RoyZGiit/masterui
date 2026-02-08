import SwiftUI

// MARK: - TargetPickerView

/// A dropdown picker to select which AI target to communicate with.
struct TargetPickerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Menu {
            // Enabled GUI targets (CLI targets are shown in Terminal mode)
            ForEach(appState.enabledTargets.filter { $0.type == .guiApp }) { target in
                Button(action: { appState.selectTarget(target.id) }) {
                    HStack {
                        Image(systemName: target.iconSymbol)
                        Text(target.name)

                        if appState.selectedTargetID == target.id {
                            Image(systemName: "checkmark")
                        }

                        let isRunning = AccessibilityService.shared.isAppRunning(bundleID: target.bundleID)
                        if !isRunning {
                            Text("(offline)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if appState.enabledTargets.isEmpty {
                Text("No targets configured")
                    .foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 6) {
                if let target = appState.selectedTarget {
                    Image(systemName: target.iconSymbol)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: target.colorHex) ?? .accentColor)
                    Text(target.name)
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12))
                    Text("Select Target")
                        .font(.system(size: 12, weight: .medium))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Color Extension for Hex

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgbValue)

        self.init(
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgbValue & 0x0000FF) / 255.0
        )
    }
}
