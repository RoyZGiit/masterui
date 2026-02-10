import Foundation

// MARK: - CLIToolConfig

/// Simplified CLI tool configuration for JSON editing.
/// This is the only format users see in the JSON editor.
struct CLIToolConfig: Codable, Hashable {
    var name: String
    var path: String
    var args: [String] = []
    var workdir: String? = nil
}
