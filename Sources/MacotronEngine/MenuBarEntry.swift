import Foundation

public struct MenuBarEntry {
    public let title: String
    public let icon: String?
    public let onClick: (() -> Void)?
    public let children: [MenuBarEntry]

    public init(title: String, icon: String? = nil, onClick: (() -> Void)? = nil, children: [MenuBarEntry] = []) {
        self.title = title
        self.icon = icon
        self.onClick = onClick
        self.children = children
    }

    public var isSeparator: Bool { title == "-" && children.isEmpty }
}
