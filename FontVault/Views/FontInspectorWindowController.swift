import AppKit
import SwiftUI

// MARK: - Window model

@MainActor
final class FontInspectorWindowModel: ObservableObject {
    @Published private(set) var fonts: [FontRecord]
    @Published var selectedIndex: Int

    var onOpenInNewWindow: ((FontRecord) -> Void)?
    var onCloseWindow: (() -> Void)?

    var font: FontRecord { fonts[selectedIndex] }

    init(fonts: [FontRecord], selectedIndex: Int) {
        self.fonts = fonts
        self.selectedIndex = min(max(0, selectedIndex), max(0, fonts.count - 1))
    }

    func selectTab(at index: Int) {
        guard fonts.indices.contains(index) else { return }
        selectedIndex = index
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard fonts.indices.contains(sourceIndex),
              destinationIndex >= 0,
              destinationIndex < fonts.count,
              sourceIndex != destinationIndex else { return }

        let selectedPath = fonts[selectedIndex].vaultPath
        fonts.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        )
        if let newIndex = fonts.firstIndex(where: { $0.vaultPath == selectedPath }) {
            selectedIndex = newIndex
        }
    }

    func stepTab(by delta: Int) {
        selectTab(at: selectedIndex + delta)
    }

    var canStepTabBack: Bool { selectedIndex > 0 }
    var canStepTabForward: Bool { selectedIndex + 1 < fonts.count }

    func openInNewWindow(tabAt index: Int) {
        guard fonts.indices.contains(index) else { return }
        onOpenInNewWindow?(fonts[index])
    }

    /// Opens this tab in a new window and removes it from the current window.
    func detachTab(at index: Int) {
        guard fonts.indices.contains(index) else { return }
        let font = fonts[index]
        onOpenInNewWindow?(font)
        closeTab(at: index)
    }

    func closeTab(at index: Int) {
        guard fonts.indices.contains(index) else { return }
        if fonts.count == 1 {
            onCloseWindow?()
            return
        }
        fonts.remove(at: index)
        if selectedIndex == index || selectedIndex >= fonts.count {
            selectedIndex = min(index, fonts.count - 1)
        } else if selectedIndex > index {
            selectedIndex -= 1
        }
    }
}

// MARK: - Menu command state (Window menu tab navigation)

@MainActor
final class FontInspectorCommandState: ObservableObject {
    static let shared = FontInspectorCommandState()

    @Published private(set) var canStepTabBack = false
    @Published private(set) var canStepTabForward = false

    fileprivate func apply(canStepBack: Bool, canStepForward: Bool) {
        canStepTabBack = canStepBack
        canStepTabForward = canStepForward
    }

    fileprivate func reset() {
        apply(canStepBack: false, canStepForward: false)
    }
}

// MARK: - AppKit windows (FEX-style: multiple, movable, resizable)

@MainActor
final class FontInspectorWindowController: NSObject, NSWindowDelegate {
    static let shared = FontInspectorWindowController()

    private struct WindowEntry {
        let id: UUID
        let window: NSWindow
        let model: FontInspectorWindowModel
    }

    private var windows: [UUID: WindowEntry] = [:]
    /// Last size/position while the app is running (cleared on quit).
    private var sessionContentSize: NSSize?
    private var sessionFrameOrigin: NSPoint?
    private var cascadeGeneration: UInt = 0

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearSessionFrameOnTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshCommandStateFromNotification),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshCommandStateFromNotification),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
    }

    var openWindowCount: Int { windows.count }

    func refreshCommandState() {
        guard let model = keyWindowModel else {
            FontInspectorCommandState.shared.reset()
            return
        }
        FontInspectorCommandState.shared.apply(
            canStepBack: model.canStepTabBack,
            canStepForward: model.canStepTabForward
        )
    }

    func stepKeyWindowTab(by delta: Int) {
        guard let model = keyWindowModel else { return }
        model.stepTab(by: delta)
        refreshCommandState()
    }

    private var keyWindowModel: FontInspectorWindowModel? {
        guard let keyWindow = NSApp.keyWindow,
              isInspectorWindow(keyWindow),
              let idString = keyWindow.identifier?.rawValue,
              let id = UUID(uuidString: idString) else { return nil }
        return windows[id]?.model
    }

    @objc private func refreshCommandStateFromNotification() {
        refreshCommandState()
    }

    func present(fonts: [FontRecord], selectedIndex: Int) {
        guard !fonts.isEmpty else { return }

        let id = UUID()
        let model = FontInspectorWindowModel(fonts: fonts, selectedIndex: selectedIndex)
        model.onOpenInNewWindow = { [weak self] font in
            self?.present(fonts: [font], selectedIndex: 0)
        }
        model.onCloseWindow = { [weak self] in
            self?.closeWindow(id: id)
        }

        let rootView = FontInspectorWindowView(model: model)
            .onChange(of: model.selectedIndex) { _, _ in
                FontInspectorWindowController.shared.refreshCommandState()
            }
        let hosting = NSHostingController(rootView: rootView)
        hosting.safeAreaRegions = []

        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultContentSize()),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        window.title = AppMenuCopy.inspectorWindowTitle
        window.titleVisibility = .visible
        window.contentViewController = hosting
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(
            width: DesignMetrics.fontInspectorWindowMinWidth,
            height: DesignMetrics.fontInspectorWindowMinHeight
        )
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        applyInitialFrame(to: window, isFirstInSession: sessionContentSize == nil)

        windows[id] = WindowEntry(id: id, window: window, model: model)
        window.makeKeyAndOrderFront(nil)
        refreshCommandState()
    }

    func closeWindow(id: UUID) {
        guard let entry = windows.removeValue(forKey: id) else { return }
        persistSessionFrame(from: entry.window)
        entry.window.delegate = nil
        entry.window.close()
        refreshCommandState()
    }

    func closeAll() {
        let ids = Array(windows.keys)
        for id in ids {
            closeWindow(id: id)
        }
    }

    @objc private func clearSessionFrameOnTerminate() {
        sessionContentSize = nil
        sessionFrameOrigin = nil
        cascadeGeneration = 0
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let idString = window.identifier?.rawValue,
              let id = UUID(uuidString: idString) else { return }
        if windows[id] != nil {
            closeWindow(id: id)
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        persistSessionFrame(from: window)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        persistSessionFrame(from: window)
    }

    private func persistSessionFrame(from window: NSWindow) {
        sessionContentSize = window.contentLayoutRect.size
        sessionFrameOrigin = window.frame.origin
    }

    private func applyInitialFrame(to window: NSWindow, isFirstInSession: Bool) {
        if let parent = mainAppWindow {
            window.maxSize = NSSize(width: parent.frame.width, height: parent.frame.height)
        }

        if let size = sessionContentSize {
            window.setContentSize(size)
            var origin = sessionFrameOrigin ?? window.frame.origin
            let offset = CGFloat(cascadeGeneration) * DesignMetrics.fontInspectorWindowCascadeOffset
            cascadeGeneration &+= 1
            origin.x += offset
            origin.y -= offset
            origin = clampedOrigin(origin, windowSize: window.frame.size, relativeTo: mainAppWindow)
            window.setFrameOrigin(origin)
            return
        }

        cascadeGeneration = 0
        positionCenteredOnMainWindow(window, isFirstInSession: isFirstInSession)
    }

    private func positionCenteredOnMainWindow(_ window: NSWindow, isFirstInSession: Bool) {
        let size = defaultContentSize()
        window.setContentSize(size)

        guard let parent = mainAppWindow else {
            window.center()
            return
        }

        var origin = NSPoint(
            x: parent.frame.midX - window.frame.width / 2,
            y: parent.frame.midY - window.frame.height / 2
        )
        origin = clampedOrigin(origin, windowSize: window.frame.size, relativeTo: parent)
        window.setFrameOrigin(origin)

        if isFirstInSession {
            sessionContentSize = size
            sessionFrameOrigin = origin
        }
    }

    private func defaultContentSize() -> NSSize {
        guard let parent = mainAppWindow else {
            return NSSize(
                width: DesignMetrics.fontInspectorWindowIdealWidth,
                height: DesignMetrics.fontInspectorWindowIdealHeight
            )
        }
        let scale = DesignMetrics.fontInspectorWindowRelativeScale
        return NSSize(
            width: max(
                DesignMetrics.fontInspectorWindowMinWidth,
                floor(parent.frame.width * scale)
            ),
            height: max(
                DesignMetrics.fontInspectorWindowMinHeight,
                floor(parent.frame.height * scale)
            )
        )
    }

    private var mainAppWindow: NSWindow? {
        if let main = NSApp.mainWindow, !isInspectorWindow(main) {
            return main
        }
        return NSApp.windows.first { window in
            window.canBecomeMain && !isInspectorWindow(window)
        }
    }

    private func isInspectorWindow(_ window: NSWindow) -> Bool {
        guard let idString = window.identifier?.rawValue,
              let uuid = UUID(uuidString: idString) else { return false }
        return windows[uuid] != nil || windows.values.contains { $0.window === window }
    }

    private func clampedOrigin(
        _ origin: NSPoint,
        windowSize: NSSize,
        relativeTo parent: NSWindow?
    ) -> NSPoint {
        let screen = parent?.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        var clamped = origin
        clamped.x = min(max(clamped.x, visible.minX), visible.maxX - windowSize.width)
        clamped.y = min(max(clamped.y, visible.minY), visible.maxY - windowSize.height)
        return clamped
    }
}
