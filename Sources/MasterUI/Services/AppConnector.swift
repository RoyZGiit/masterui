import Foundation

// MARK: - AppConnectorProtocol

/// Protocol defining how MasterUI communicates with a target AI application.
protocol AppConnectorProtocol {
    /// The target AI app configuration.
    var target: AITarget { get }

    /// Send a message to the target app.
    /// Returns true if the message was successfully injected.
    func sendMessage(_ text: String) async -> Bool

    /// Start monitoring for responses.
    /// The callback receives (responseText, isComplete).
    func startMonitoring(callback: @escaping (String, Bool) -> Void)

    /// Stop monitoring for responses.
    func stopMonitoring()

    /// Activate (bring to front) the target app.
    func activateApp()

    /// Check if the target app is currently running.
    var isAppRunning: Bool { get }
}

// MARK: - ConnectorManager

/// Manages all active app connectors.
class ConnectorManager: ObservableObject {
    static let shared = ConnectorManager()

    @Published var activeConnectors: [UUID: any AppConnectorProtocol] = [:]

    private init() {}

    /// Get or create a connector for the given target.
    /// Uses specialized connectors for known apps (Cursor, etc.)
    /// and the GenericConnector for everything else.
    func connector(for target: AITarget) -> any AppConnectorProtocol {
        if let existing = activeConnectors[target.id] {
            return existing
        }

        let connector: any AppConnectorProtocol

        if target.type == .cliTool {
            connector = CLIConnector(target: target)
        } else {
            // GUI App Strategy
            // Use specialized connectors for known Electron apps
            switch target.bundleID {
            case "com.todesktop.230313mzl4w4u92":
                // Cursor IDE - uses keyboard-driven approach
                connector = CursorConnector(target: target)
            default:
                connector = GenericConnector(target: target)
            }
        }

        activeConnectors[target.id] = connector
        return connector
    }

    /// Remove a connector.
    func removeConnector(for targetID: UUID) {
        activeConnectors[targetID]?.stopMonitoring()
        activeConnectors.removeValue(forKey: targetID)
    }

    /// Remove all connectors.
    func removeAll() {
        for connector in activeConnectors.values {
            connector.stopMonitoring()
        }
        activeConnectors.removeAll()
    }
}
