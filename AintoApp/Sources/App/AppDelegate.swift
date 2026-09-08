import AppKit
import SwiftUI
import AintoCore
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var searchPanel: SearchPanel?
    private let pluginPaths = PluginPaths.applicationSupport
    private lazy var pluginRegistry = PluginRegistry(paths: pluginPaths)
    private lazy var pluginPermissionStore = PluginPermissionStore(paths: pluginPaths)
    private lazy var pluginLogStore = PluginLogStore(paths: pluginPaths)
    private var hotkeyManager: HotkeyManager?
    private var textExpander: TextExpander?
    private var trayManager: TrayManager?
    private var settingsWindow: NSWindow?
    private var configWatcherSources: [DispatchSourceFileSystemObject] = []
    private var configWatcherFDs: [Int32] = []
    private var languageObserver: NSObjectProtocol?

    private var updaterController: SPUStandardUpdaterController?

    var updater: SPUUpdater? {
        updaterController?.updater
    }

    /// Only start Sparkle when running as a .app bundle (not bare SPM binary).
    private func setupSparkle() {
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.infoDictionary?["SUFeedURL"] != nil else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock (LSUIElement behavior)
        NSApp.setActivationPolicy(.accessory)

        // Prevent macOS from auto-terminating this background launcher
        ProcessInfo.processInfo.automaticTerminationSupportEnabled = false

        // Initialize Rust core
        initializeRustCore()

        // Start Sparkle auto-update (only in .app bundle)
        setupSparkle()

        // Load the one shared plugin service graph before creating the panel.
        try? pluginRegistry.load()
        try? pluginRegistry.refreshDevelopmentPlugins()

        // Set up search panel
        searchPanel = SearchPanel(viewModel: SearchViewModel(pluginRegistry: pluginRegistry, pluginPermissionStore: pluginPermissionStore, pluginLogStore: pluginLogStore, pluginPaths: pluginPaths))
        searchPanel?.viewModel.onSnippetsChanged = { [weak self] in
            self?.textExpander?.reloadSnippets()
        }

        // Set up global hotkey
        hotkeyManager = HotkeyManager { [weak self] in
            self?.toggleSearchPanel()
        }
        // Spotlight/Raycast conflict warnings are handled in SettingsView


        // Start global text expansion (only while enabled in config)
        textExpander = TextExpander()
        applySnippetsEnabled()

        // Set up tray icon
        trayManager = TrayManager(hotkeyManager: hotkeyManager, onSettings: { [weak self] in
            self?.openSettings()
        })

        // Watch ~/.config/ainto/ for external file changes (e.g. manual TOML edits)
        watchConfigDirectory()
        languageObserver = NotificationCenter.default.addObserver(
            forName: .appLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLanguage() }
        }
    }

    /// Monitor config files for external changes and reload automatically.
    private func watchConfigDirectory() {
        let configDir = NSHomeDirectory() + "/.config/ainto"
        let files = ["snippets.toml", "ai-commands.toml", "config.toml"]

        for file in files {
            let path = configDir + "/" + file
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            configWatcherFDs.append(fd)

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                if file == "config.toml" {
                    // Covers both the Settings toggle (saved via rc_config_save)
                    // and manual TOML edits.
                    self?.applySnippetsEnabled()
                } else {
                    self?.searchPanel?.viewModel.loadSnippets()
                    self?.searchPanel?.viewModel.loadAICommands()
                    self?.textExpander?.reloadSnippets()
                }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            configWatcherSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        textExpander?.stop()
        configWatcherSources.forEach { $0.cancel() }
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
    }

    private func toggleSearchPanel() {
        guard let panel = searchPanel else { return }
        if panel.isPanelVisible {
            panel.hidePanel()
        } else {
            panel.showPanel()
        }
    }

    private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(hotkeyManager: hotkeyManager, pluginRegistry: pluginRegistry, pluginPermissionStore: pluginPermissionStore, pluginLogStore: pluginLogStore)
        let hostingView = NSHostingView(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.title = L("settings.title")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear

        // Glassmorphism: add visual effect view behind the hosting view
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = visualEffect
        visualEffect.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    private func refreshLanguage() {
        settingsWindow?.title = L("settings.title")
        searchPanel?.viewModel.refreshLocalizedContent()
    }

    /// Rust core initialization is intentionally lightweight; app discovery is
    /// performed by SearchViewModel.refreshApps() when the panel is shown.
    private func initializeRustCore() {
        // Keep startup non-blocking and avoid racing the first panel refresh.
    }

    /// Start or stop the keystroke event tap to match `snippets_enabled` in
    /// config.toml. Disabling snippets must actually tear down the CGEvent
    /// tap — users expect no keystroke monitoring while the switch is off.
    private func applySnippetsEnabled() {
        if loadSnippetsEnabled() {
            textExpander?.start()
        } else {
            textExpander?.stop()
        }
    }

    private func loadSnippetsEnabled() -> Bool {
        guard let cstr = rc_config_load() else { return true }
        defer { rc_free_string(cstr) }
        let json = String(cString: cstr)
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return true }
        return dict["snippets_enabled"] as? Bool ?? true
    }

}
