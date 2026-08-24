import Foundation

public struct MenuBarEntry {
    public let title: String
    public let icon: String?
    public let onClick: (() -> Void)?
    public let children: [MenuBarEntry]
    /// A web page to show as the row itself, instead of a title.
    public let html: String?
    /// Draw `children` as buttons in this one row, which leaves the menu open
    /// when one is clicked, instead of as a submenu.
    public let inline: Bool
    public let size: (width: Double, height: Double)

    public init(
        title: String,
        icon: String? = nil,
        onClick: (() -> Void)? = nil,
        children: [MenuBarEntry] = [],
        html: String? = nil,
        inline: Bool = false,
        width: Double = 260,
        height: Double = 160
    ) {
        self.title = title
        self.icon = icon
        self.onClick = onClick
        self.children = children
        self.html = html
        self.inline = inline
        self.size = (width, height)
    }

    public var isSeparator: Bool { title == "-" && children.isEmpty }
}
