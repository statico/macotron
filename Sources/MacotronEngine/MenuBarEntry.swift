import Foundation

public struct MenuBarEntry {
    public let title: String
    public let icon: String?
    public let onClick: (() -> Void)?
    public let children: [MenuBarEntry]
    /// A web page to show as the row itself, instead of a title.
    public let html: String?
    public let size: (width: Double, height: Double)

    public init(
        title: String,
        icon: String? = nil,
        onClick: (() -> Void)? = nil,
        children: [MenuBarEntry] = [],
        html: String? = nil,
        width: Double = 260,
        height: Double = 160
    ) {
        self.title = title
        self.icon = icon
        self.onClick = onClick
        self.children = children
        self.html = html
        self.size = (width, height)
    }

    public var isSeparator: Bool { title == "-" && children.isEmpty }
}
