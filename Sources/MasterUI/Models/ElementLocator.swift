import Foundation

// MARK: - ElementLocator

/// Configuration for locating a specific UI element in another app's accessibility tree.
struct ElementLocator: Codable, Hashable {
    /// The AX role to match (e.g., "AXTextArea", "AXTextField", "AXWebArea").
    var role: String?

    /// The accessibility identifier to match.
    var identifier: String?

    /// A regex pattern to match against the element's title.
    var titlePattern: String?

    /// A regex pattern to match against the element's description.
    var descriptionPattern: String?

    /// A regex pattern to match against the element's value (for output areas).
    var valuePattern: String?

    /// Ordered path hints for navigating the AX tree.
    /// e.g., ["AXWindow", "AXSplitGroup", "AXGroup", "AXTextArea"]
    var pathHint: [String]?

    /// Index hint when multiple matches exist (0-based).
    var matchIndex: Int?

    /// If true, search the entire subtree recursively. If false, only follow pathHint.
    var deepSearch: Bool

    init(
        role: String? = nil,
        identifier: String? = nil,
        titlePattern: String? = nil,
        descriptionPattern: String? = nil,
        valuePattern: String? = nil,
        pathHint: [String]? = nil,
        matchIndex: Int? = nil,
        deepSearch: Bool = true
    ) {
        self.role = role
        self.identifier = identifier
        self.titlePattern = titlePattern
        self.descriptionPattern = descriptionPattern
        self.valuePattern = valuePattern
        self.pathHint = pathHint
        self.matchIndex = matchIndex
        self.deepSearch = deepSearch
    }

    /// Returns true if this locator has enough information to attempt a search.
    var isConfigured: Bool {
        role != nil || identifier != nil || titlePattern != nil || pathHint != nil
    }
}
