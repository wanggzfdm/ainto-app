import AppKit
import SwiftUI

/// Non-activating floating panel for the search interface.
/// Uses NSPanel + .nonactivatingPanel so the previously focused app keeps focus.
@MainActor
final class SearchPanel: NSPanel {
    private let hostingView: NSHostingView<MainView>
    let viewModel = SearchViewModel()

    /// The app that was frontmost before we showed the panel.
    private var previousApp: NSRunningApplication?

    /// Floating action panel window.
    private var actionWindow: NSWindow?
    private var jsonFormatterWindow: NSWindow?
    private var jsonFormatterWindowDelegate: JSONFormatterWindowDelegate?
    private var actionSelectedIndex = 0

    init() {
        let mainView = MainView(viewModel: viewModel)
        hostingView = NSHostingView(rootView: mainView)
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        // Default sizingOptions (.standardBounds) for correct auto-sizing.
        // Removing .titled eliminates the title bar constraints that caused
        // the infinite recursion between updateWindowContentSizeExtremaIfNecessary
        // and updateConstraints when display configuration changes (macOS 14/15).
        // The panel's visual appearance is unchanged — SwiftUI provides its own
        // glassmorphism background via VisualEffectBackground + RoundedRectangle.

        super.init(
            contentRect: NSRect(
                origin: .zero,
                size: MainPanelLayout.size(for: .collapsedApplications)
            ),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.contentView = hostingView
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true

        // Round the window content view to match the SwiftUI clipShape,
        // so the window-level shadow follows the rounded corners.
        if let cv = self.contentView {
            cv.wantsLayer = true
            cv.layer?.cornerRadius = 16
            cv.layer?.cornerCurve = .continuous
            cv.layer?.masksToBounds = true
        }

        // Accept keyboard input even without activating the app
        self.becomesKeyOnlyIfNeeded = false

        // Wire up the paste action
        viewModel.onPasteAndHide = { [weak self] in
            self?.pasteToFrontmostApp()
        }

        // Wire up grab selection for AI commands
        viewModel.onGrabSelection = { [weak self] completion in
            self?.grabSelectionFromPreviousApp(completion: completion)
        }

        viewModel.onOpenJSONFormatterWindow = { [weak self] in
            self?.openJSONFormatterWindow()
        }

        viewModel.onJSONFormatterExpansionChanged = { [weak self] expanded in
            DispatchQueue.main.async {
                self?.resizePanel(for: expanded ? .jsonFormatter : self?.mainPanelState ?? .searchOnly)
            }
        }

        viewModel.onApplicationGridExpansionChanged = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resizePanel(for: self.mainPanelState)
            }
        }

        viewModel.onResultsChanged = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resizePanel(for: self.mainPanelState)
            }
        }

        viewModel.onApplicationIndexReady = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.pendingInitialShow else { return }
                self.pendingInitialShow = false
                self.presentPanel()
            }
        }

        viewModel.loadAISettings()
    }

    /// Whether the user has ever positioned the panel manually.
    private var hasUserPosition = false
    private var pendingInitialShow = false
    func showPanel() {
        // Remember the currently focused app before showing.
        previousApp = NSWorkspace.shared.frontmostApplication
        viewModel.loadAISettings()
        if !viewModel.isApplicationIndexReady, viewModel.query.isEmpty {
            pendingInitialShow = true
            viewModel.selectAll()
            viewModel.refreshApps()
            return
        }
        presentPanel()
    }

    private func presentPanel() {
        let screen = screenUnderMouse()
        if let screen {
            let frameSize = MainPanelLayout.size(for: mainPanelState, itemCount: mainPanelItemCount)
            let visibleFrame = screen.visibleFrame
            let width = min(frameSize.width, visibleFrame.width - 24)
            let height = min(frameSize.height, visibleFrame.height - 24)
            let x = visibleFrame.midX - width / 2
            let y = visibleFrame.maxY - visibleFrame.height * 0.25 - height / 2
            setFrame(NSRect(x: x, y: max(visibleFrame.minY + 12, y), width: width, height: height), display: true, animate: false)
        }
        viewModel.updateClipboardContext(NSPasteboard.general.string(forType: .string))
        makeKeyAndOrderFront(nil)
        viewModel.selectAll()
    }

    private var mainPanelState: MainPanelContentState {
        if viewModel.isJSONFormatterExpanded { return .jsonFormatter }
        let itemCount = viewModel.displayedApplicationResults.count
        if itemCount == 0 { return .searchOnly }
        return viewModel.query.isEmpty
            ? .collapsedApplications
            : .searchResults
    }

    private var mainPanelItemCount: Int {
        viewModel.displayedApplicationResults.count
    }

    private func screenUnderMouse() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func resizePanel(for state: MainPanelContentState, animate: Bool = true) {
        let screen = screenUnderMouse()
        let availableFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 800)
        let desiredSize = MainPanelLayout.size(for: state, itemCount: mainPanelItemCount)
        let width = min(desiredSize.width, availableFrame.width - 24)
        let height = min(desiredSize.height, availableFrame.height - 24)
        let top = min(frame.maxY, availableFrame.maxY - 12)
        let x = min(max(frame.origin.x, availableFrame.minX + 12), availableFrame.maxX - width - 12)
        let y = max(availableFrame.minY + 12, top - height)
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: animate)
    }

    private func openJSONFormatterWindow() {
        if let window = jsonFormatterWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            viewModel.didOpenJSONFormatterWindow()
            return
        }

        let text = Binding(
            get: { [weak viewModel] in viewModel?.jsonFormatterInput ?? "" },
            set: { [weak viewModel] in viewModel?.jsonFormatterInput = $0 }
        )
        let rootView = JSONFormatterView(text: text)
        let hosting = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.title = L("json.title")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 800, height: 600)
        window.center()

        let delegate = JSONFormatterWindowDelegate { [weak self] in
            self?.jsonFormatterWindow = nil
            self?.jsonFormatterWindowDelegate = nil
            self?.viewModel.didCloseJSONFormatterWindow()
        }
        jsonFormatterWindowDelegate = delegate
        window.delegate = delegate
        jsonFormatterWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        viewModel.didOpenJSONFormatterWindow()
    }

    func hidePanel() {
        hideActionPanel()
        viewModel.resetApplicationGridExpansion()
        orderOut(nil)
    }

    /// Hide panel, re-activate the previous app, and simulate Cmd+V to paste.
    func pasteToFrontmostApp() {
        hidePanel()

        // Re-activate the previous app
        if let app = previousApp {
            app.activate()
        }

        // Small delay to let the app activate, then simulate Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.simulatePaste()
        }
    }

    /// Simulate Cmd+V keystroke.
    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Hide panel, activate previous app, simulate Cmd+C to grab selection, then call back.
    func grabSelectionFromPreviousApp(completion: @escaping (String) -> Void) {
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        // Hide panel and activate previous app
        hidePanel()
        previousApp?.activate()

        // Wait for app activation, then simulate Cmd+C
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            pasteboard.clearContents()
            self.simulateCopy()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let selection = pasteboard.string(forType: .string) ?? ""

                pasteboard.clearContents()
                if let prev = previousContent {
                    pasteboard.setString(prev, forType: .string)
                    pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
                }

                // Re-show panel and call back
                self.makeKeyAndOrderFront(nil)
                completion(selection)
            }
        }
    }

    /// Simulate Cmd+C keystroke.
    private func simulateCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        cDown?.flags = .maskCommand
        cDown?.post(tap: .cghidEventTap)
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        cUp?.flags = .maskCommand
        cUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Action Panel

    func showActionPanel() {
        let actions = viewModel.currentActions
        guard !actions.isEmpty else { return }
        actionSelectedIndex = 0

        let displayedResults = viewModel.displayedApplicationResults
        let title = displayedResults.indices.contains(viewModel.selectedIndex)
            ? displayedResults[viewModel.selectedIndex].title : ""

        let panelView = ActionPanelView(
            title: title,
            actions: actions,
            onDismiss: { [weak self] in self?.hideActionPanel() },
            selectedIndex: actionSelectedIndex
        )
        let hosting = NSHostingView(rootView: panelView)
        hosting.frame = NSRect(x: 0, y: 0, width: 260, height: CGFloat(actions.count * 32 + 70))

        let window = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating

        // Position to the right of the main panel
        let mainFrame = self.frame
        let x = mainFrame.maxX + 8
        let y = mainFrame.maxY - hosting.frame.height - 40
        window.setFrameOrigin(NSPoint(x: x, y: y))

        window.orderFront(nil)
        actionWindow = window
        viewModel.showActionPanel = true
    }

    func hideActionPanel() {
        actionWindow?.orderOut(nil)
        actionWindow = nil
        viewModel.showActionPanel = false
        actionSelectedIndex = 0
    }

    func updateActionPanelSelection() {
        guard let window = actionWindow else { return }
        let actions = viewModel.currentActions
        let displayedResults = viewModel.displayedApplicationResults
        let title = displayedResults.indices.contains(viewModel.selectedIndex)
            ? displayedResults[viewModel.selectedIndex].title : ""

        let panelView = ActionPanelView(
            title: title,
            actions: actions,
            onDismiss: { [weak self] in self?.hideActionPanel() },
            selectedIndex: actionSelectedIndex
        )
        let hosting = NSHostingView(rootView: panelView)
        hosting.frame = window.contentView?.frame ?? .zero
        window.contentView = hosting
    }

    var isPanelVisible: Bool {
        isVisible && isKeyWindow
    }

    // Auto-hide when losing focus
    override func resignKey() {
        super.resignKey()
        hidePanel()
    }

    // NSPanel override: allow key events even when app is not active
    override var canBecomeKey: Bool { true }

    private var localEventMonitor: Any?

    private func installKeyMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isKeyWindow else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyCode = Int(event.keyCode)
            let hasCmd = flags.contains(.command)

            // Forward standard text editing shortcuts to first responder.
            // NonActivatingPanel doesn't receive Edit menu actions automatically.
            if hasCmd, self.firstResponder is NSTextView {
                let action: Selector? = switch keyCode {
                case 6: flags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:")) // Z
                case 0: #selector(NSText.selectAll(_:))  // A
                case 7: #selector(NSText.cut(_:))        // X
                case 8: #selector(NSText.copy(_:))       // C
                case 9: #selector(NSText.paste(_:))      // V
                default: nil
                }
                if let action {
                    NSApp.sendAction(action, to: nil, from: nil)
                    return nil
                }
            }

            // Cmd+K — toggle action panel
            if hasCmd && keyCode == 40 { // K key
                if self.viewModel.showActionPanel {
                    self.hideActionPanel()
                } else {
                    self.showActionPanel()
                }
                return nil
            }

            // When action panel is shown, handle its navigation
            if self.viewModel.showActionPanel {
                let actions = self.viewModel.currentActions
                switch keyCode {
                case 125: // Down
                    if self.actionSelectedIndex < actions.count - 1 {
                        self.actionSelectedIndex += 1
                        self.updateActionPanelSelection()
                    }
                    return nil
                case 126: // Up
                    if self.actionSelectedIndex > 0 {
                        self.actionSelectedIndex -= 1
                        self.updateActionPanelSelection()
                    }
                    return nil
                case 36: // Enter — run selected action
                    if self.actionSelectedIndex < actions.count {
                        let action = actions[self.actionSelectedIndex]
                        action.action()
                        self.hideActionPanel()
                        if !action.keepPanel {
                            self.hidePanel()
                        }
                    }
                    return nil
                case 53: // Escape — close action panel
                    self.hideActionPanel()
                    return nil
                default:
                    return event
                }
            }

            // Cmd+Enter — save snippet/AI command form
            if hasCmd && keyCode == 36 {
                if self.viewModel.isEditingSnippet {
                    self.viewModel.saveEditingSnippet()
                    return nil
                }
                if self.viewModel.isEditingAICommand {
                    self.viewModel.saveEditingAICommand()
                    return nil
                }
            }

            // Cmd+C in Claude page — copy last response
            if hasCmd && keyCode == 8 && self.viewModel.page == .claude { // C key
                self.viewModel.claudeCopyLastResponse()
                return nil
            }

            // Cmd+Enter in Claude page — replace selected text with response
            if hasCmd && keyCode == 36 && self.viewModel.page == .claude && !self.viewModel.claudeIsStreaming {
                self.viewModel.replaceSelectedText()
                return nil
            }

            // Cmd+N — new snippet/AI command
            if hasCmd && keyCode == 45 { // N key
                if self.viewModel.page == .snippets && !self.viewModel.isEditingSnippet {
                    self.viewModel.addSnippet()
                    return nil
                }
                if self.viewModel.page == .aiCommands && !self.viewModel.isEditingAICommand {
                    self.viewModel.addAICommand()
                    return nil
                }
            }

            // Cmd+D or Cmd+Backspace — delete selected item
            if hasCmd && (keyCode == 2 || keyCode == 51) { // D key or Backspace
                if self.viewModel.page == .snippets && !self.viewModel.isEditingSnippet {
                    let items = self.viewModel.filteredSnippets
                    if self.viewModel.snippetSelectedIndex < items.count {
                        self.viewModel.deleteSnippet(id: items[self.viewModel.snippetSelectedIndex].id)
                    }
                    return nil
                }
                if self.viewModel.page == .aiCommands && !self.viewModel.isEditingAICommand {
                    let items = self.viewModel.filteredAICommands
                    if self.viewModel.aiCommandSelectedIndex < items.count {
                        self.viewModel.deleteAICommand(id: items[self.viewModel.aiCommandSelectedIndex].id)
                    }
                    return nil
                }
            }

            // Cmd+E — edit selected snippet/AI command
            if hasCmd && keyCode == 14 { // E key
                if self.viewModel.page == .snippets && !self.viewModel.isEditingSnippet {
                    self.viewModel.editSelectedSnippet()
                    return nil
                }
                if self.viewModel.page == .aiCommands && !self.viewModel.isEditingAICommand {
                    self.viewModel.editSelectedAICommand()
                    return nil
                }
            }

            // Tab — toggle search mode (apps ↔ Claude)
            if keyCode == 48 && !hasCmd && self.viewModel.page == .main { // Tab key
                self.viewModel.toggleSearchMode()
                return nil
            }

            // Let the IME handle Enter/Escape/arrows while composing
            // (marked text means the input method is mid-composition).
            if let textView = self.firstResponder as? NSTextView,
               textView.hasMarkedText(),
               [36, 53, 125, 126].contains(keyCode) {
                return event
            }

            switch keyCode {
            case 53 where self.viewModel.isEditingSnippet: // Escape in snippet edit — cancel
                self.viewModel.cancelEditingSnippet()
                return nil
            case 53 where self.viewModel.isEditingAICommand: // Escape in AI command edit — cancel
                self.viewModel.cancelEditingAICommand()
                return nil
            case 123: // Left arrow
                if self.shouldUseHorizontalGridNavigation {
                    self.moveGridSelection(.left)
                    return nil
                }
                return event
            case 124: // Right arrow
                if self.shouldUseHorizontalGridNavigation {
                    self.moveGridSelection(.right)
                    return nil
                }
                return event
            case 125: // Down arrow
                if self.viewModel.page == .main, self.viewModel.searchMode == .apps {
                    self.moveGridSelection(.down)
                } else {
                    self.viewModel.moveSelection(by: 1)
                }
                return nil
            case 126: // Up arrow
                if self.viewModel.page == .main, self.viewModel.searchMode == .apps {
                    self.moveGridSelection(.up)
                } else {
                    self.viewModel.moveSelection(by: -1)
                }
                return nil
            case 36: // Enter/Return
                if self.viewModel.searchMode == .claude && self.viewModel.page == .main {
                    self.viewModel.claudeAsk()
                    return nil
                }
                if self.viewModel.page == .claude && !self.viewModel.claudeIsStreaming {
                    self.viewModel.claudeAsk()
                    return nil
                }
                self.viewModel.openSelected()
                if self.viewModel.page == .main && !self.viewModel.isJSONFormatterExpanded {
                    self.hidePanel()
                }
                return nil
            case 53: // Escape
                if self.viewModel.page != .main {
                    self.viewModel.goBack()
                } else if self.viewModel.isJSONFormatterExpanded {
                    self.viewModel.collapseJSONFormatter()
                } else if self.viewModel.query.isEmpty {
                    self.hidePanel()
                } else {
                    self.viewModel.clearQuery()
                }
                return nil
            default:
                return event
            }
        }
    }

    private var shouldUseHorizontalGridNavigation: Bool {
        viewModel.page == .main
            && viewModel.searchMode == .apps
            && viewModel.query.isEmpty
            && !viewModel.results.isEmpty
    }

    private func moveGridSelection(_ direction: GridNavigationDirection) {
        let displayedResults = viewModel.displayedApplicationResults
        guard !displayedResults.isEmpty else { return }
        viewModel.selectedIndex = GridSelectionNavigator.destination(
            from: viewModel.selectedIndex,
            itemCount: displayedResults.count,
            columnCount: MainSearchGridMetrics.columnCount,
            direction: direction
        )
    }

    private func removeKeyMonitor() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        installKeyMonitor()
    }

    override func orderOut(_ sender: Any?) {
        removeKeyMonitor()
        super.orderOut(sender)
    }
}

@MainActor
private final class JSONFormatterWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
