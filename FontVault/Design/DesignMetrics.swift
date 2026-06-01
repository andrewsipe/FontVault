import CoreGraphics

/// Spacing aligned with macOS HIG (8pt grid, 20pt window margins).
enum DesignMetrics {
    static let windowMargin: CGFloat = 20
    static let controlSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 20

    static let sidebarMinWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 220
    static let sidebarMaxWidth: CGFloat = 260

    static let inspectorMinWidth: CGFloat = 200
    static let inspectorIdealWidth: CGFloat = 220
    static let inspectorMaxWidth: CGFloat = 260

    /// Full font inspector window (double-click a row).
    static let fontInspectorWindowMinWidth: CGFloat = 480
    static let fontInspectorWindowMinHeight: CGFloat = 320
    static let fontInspectorWindowIdealWidth: CGFloat = 560
    static let fontInspectorWindowIdealHeight: CGFloat = 640
    /// First-open size as a fraction of the main window frame (width and height).
    static let fontInspectorWindowRelativeScale: CGFloat = 0.75
    /// Offset for each additional inspector opened in one session.
    static let fontInspectorWindowCascadeOffset: CGFloat = 22
    static let fontInspectorTabMinWidth: CGFloat = 100
    static let fontInspectorTabMaxWidth: CGFloat = 200
    static let fontInspectorNavButtonWidth: CGFloat = 28
    static let fontInspectorTabCloseButtonSize: CGFloat = 16
    static let fontInspectorTabCornerRadius: CGFloat = 6
    /// Full height of the tab bar row (pills are shorter and centered).
    static let fontInspectorTabBarHeight: CGFloat = 36
    /// Selected tab pill height (caption line + close control).
    static let fontInspectorTabPillHeight: CGFloat = 24
    /// Vertical rules between tabs and beside step buttons.
    static var fontInspectorTabSeparatorHeight: CGFloat { fontInspectorTabPillHeight - 8 }
    /// Horizontal inset from the scroll viewport edge that triggers auto-scroll while dragging.
    static let fontInspectorTabDragEdgeScrollThreshold: CGFloat = 44

    static let statusBarHeight: CGFloat = 26

    /// Sheet footer actions (standalone row at bottom of a sheet).
    static let sheetActionButtonMinWidth: CGFloat = 128
    static let sheetActionButtonHorizontalPadding: CGFloat = 12

    /// Inline sheet actions (trailing a progress bar on the same row).
    static let sheetInlineActionSpacing: CGFloat = 12
    static let sheetInlineActionHorizontalPadding: CGFloat = 10
}
