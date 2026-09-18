import AppKit
import Foundation
import AintoCore

/// AI command — loaded from ~/.config/ainto/ai-commands.toml
struct AICommand: Identifiable {
    var id: String
    var name: String
    var icon: String
    var prompt: String  // {selection} will be replaced with selected text

    static func new() -> AICommand {
        AICommand(id: UUID().uuidString, name: "", icon: "sparkle", prompt: "{selection}")
    }

    /// Load all commands from TOML (includes defaults on first run).
    static func loadAll() -> [AICommand] {
        guard let cStr = rc_ai_commands_load() else { return [] }
        let jsonStr = String(cString: cStr)
        rc_free_string(cStr)

        guard let data = jsonStr.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return entries.map { entry in
            AICommand(
                id: entry["name"] as? String ?? UUID().uuidString,
                name: entry["name"] as? String ?? "",
                icon: entry["icon"] as? String ?? "sparkle",
                prompt: entry["prompt"] as? String ?? ""
            )
        }
    }
}

/// Fuzzy match score. Returns 0 if no match.
/// Higher = better match. Mirrors Rust's fuzzy_score logic.
func fuzzyScore(_ query: String, _ target: String) -> Int {
    let q = query.lowercased()
    let t = target.lowercased()
    if t == q { return 200 }
    if t.hasPrefix(q) { return 150 }
    // Word-boundary initials: "iw" → "Improve Writing" (I + W)
    if wordBoundaryMatch(q, target) { return 120 }
    if t.contains(q) { return 100 }
    if fuzzyMatch(q, t) { return 60 + Int(Double(q.count) / Double(t.count) * 40) }
    return 0
}

/// Check if query matches the first letter of each word or camelCase boundary.
/// "iw" matches "Improve Writing", "vsc" matches "Visual Studio Code"
func wordBoundaryMatch(_ query: String, _ target: String) -> Bool {
    let initials = extractWordBoundaries(target)
    let qChars = Array(query.lowercased())
    let iChars = initials.map { Character($0.lowercased()) }
    guard !qChars.isEmpty, !iChars.isEmpty else { return false }
    var qi = 0
    for ic in iChars {
        if qi < qChars.count && ic == qChars[qi] {
            qi += 1
        }
    }
    return qi == qChars.count
}

/// Extract first char + chars after space/hyphen + uppercase in camelCase.
func extractWordBoundaries(_ name: String) -> [Character] {
    var boundaries: [Character] = []
    let chars = Array(name)
    for (i, c) in chars.enumerated() {
        if i == 0 && c.isLetter {
            boundaries.append(c)
        } else if c.isUppercase && i > 0 && chars[i-1].isLowercase {
            boundaries.append(c)
        } else if i > 0 && (chars[i-1] == " " || chars[i-1] == "-" || chars[i-1] == "_") && c.isLetter {
            boundaries.append(c)
        }
    }
    return boundaries
}

/// Simple fuzzy match: query chars appear in order in target.
/// Returns true if all characters of query appear in target in order.
func fuzzyMatch(_ query: String, _ target: String) -> Bool {
    if query.isEmpty { return true }
    let q = query.lowercased()
    let t = target.lowercased()
    var qi = q.startIndex
    for tc in t {
        if tc == q[qi] {
            qi = q.index(after: qi)
            if qi == q.endIndex { return true }
        }
    }
    return false
}

/// Sendable wrapper for UnsafeMutableRawPointer (for passing to Task.detached).
struct SendablePointer: @unchecked Sendable {
    let ptr: UnsafeMutableRawPointer
}

/// A message in the Claude conversation.
struct ClaudeMessage: Identifiable {
    let id = UUID()
    let role: ClaudeRole
    var text: String
}

enum ClaudeRole {
    case user
    case assistant
}

/// Active page in the launcher.
enum LauncherPage: Equatable {
    case main
    case snippets
    case aiCommands
    case claude
    case plugin
    case pluginCenter
}

enum SearchMode: Equatable {
    case apps    // default: search apps/commands
    case claude  // Tab: ask Claude
}

/// An action available for a search result.
struct ActionItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String // SF Symbol name
    let shortcut: String? // e.g. "⌘ O" for display
    var keepPanel: Bool = false // true = don't hide panel after action (for navigation)
    let action: () -> Void
}

/// Search result model for the UI.
struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: NSImage?
    let systemIcon: String? // fallback SF Symbol name
    var stableIdentity: String? = nil
    var score: Int = 0 // higher = better match, used for unified sorting
    let action: () -> Void
    var actions: [ActionItem] = [] // Cmd+K to show

    /// Stable across search passes, so SwiftUI preserves unchanged result rows.
    var stableID: String { stableIdentity ?? "\(subtitle)\u{0}\(title)" }

    /// Resolved icon: app icon or SF Symbol fallback
    var displayIcon: NSImage {
        if let icon { return icon }
        if let name = systemIcon,
           let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            return img
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            ?? NSImage()
    }
}

/// Snippet item model.
struct SnippetItem: Identifiable {
    var id: String
    var name: String
    var keyword: String
    var expansion: String

    static func new() -> SnippetItem {
        SnippetItem(id: UUID().uuidString, name: "", keyword: "", expansion: "")
    }
}

/// ViewModel managing search state and Rust FFI calls.
@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [SearchResult] = []
    @Published var allApplications: [SearchResult] = []
    @Published var isApplicationIndexReady = false
    @Published var isApplicationGridExpanded = false
    @Published var selectedIndex: Int = 0
    @Published var shouldSelectAll = false
    @Published var page: LauncherPage = .main
    @Published var searchMode: SearchMode = .apps
    @Published var jsonFormatterInput: String = ""
    @Published var isJSONFormatterExpanded = false
    @Published var shouldOpenJSONFormatterWindow = false
    private var clipboardJSON: String?
    private var lastConsumedClipboardChangeCount: Int?
    var clipboardText: String?
    let pluginRegistry: PluginRegistry
    let pluginPermissionStore: PluginPermissionStore
    let pluginLogStore: PluginLogStore
    let pluginPaths: PluginPaths
    private let pluginSearchProvider = PluginSearchProvider()

    init(pluginRegistry: PluginRegistry = PluginRegistry(), pluginPermissionStore: PluginPermissionStore = PluginPermissionStore(), pluginLogStore: PluginLogStore = PluginLogStore(), pluginPaths: PluginPaths = .applicationSupport) {
        self.pluginRegistry = pluginRegistry
        self.pluginPermissionStore = pluginPermissionStore
        self.pluginLogStore = pluginLogStore
        self.pluginPaths = pluginPaths
    }
    @Published var activePlugin: PluginRegistration?
    @Published var activePluginFeatureCode: String?
    // Claude state
    @Published var claudeMessages: [ClaudeMessage] = []
    @Published var claudeIsStreaming = false
    private var claudeSession: UnsafeMutableRawPointer?
    private var claudeSessionId: String?

    // Snippet state
    @Published var snippets: [SnippetItem] = []
    @Published var snippetSelectedIndex: Int = 0
    @Published var snippetFilter: String = ""
    @Published var isEditingSnippet = false
    @Published var editingSnippet: SnippetItem?

    // AI master switch (config: ai_enabled). When false, all AI surfaces
    // are hidden from the launcher.
    @Published var aiEnabled: Bool = true

    // Agent CLI binary to spawn for AI sessions (config: claude_binary).
    var claudeBinary: String = "claude"

    // AI Commands state
    @Published var aiCommands: [AICommand] = []
    @Published var aiCommandSelectedIndex: Int = 0
    @Published var aiCommandFilter: String = ""
    @Published var isEditingAICommand = false
    @Published var editingAICommand: AICommand?

    // Action panel
    @Published var showActionPanel = false

    /// Icon cache keyed by app path
    private var iconCache: [String: NSImage] = [:]


    /// Callback to hide panel and paste to frontmost app (set by SearchPanel)
    var onPasteAndHide: (() -> Void)?

    /// Callback to reload text expander snippets (set by AppDelegate)
    var onSnippetsChanged: (() -> Void)?
    var onOpenJSONFormatterWindow: (() -> Void)?
    var onPluginFeatureSelected: ((String, String) -> Void)?
    var onPluginResize: ((PluginHostSize) -> PluginHostSize)?
    var onPluginExit: (() -> Void)?
    var onJSONFormatterExpansionChanged: ((Bool) -> Void)?
    var onApplicationGridExpansionChanged: (() -> Void)?
    var onResultsChanged: (() -> Void)?
    var onApplicationIndexReady: (() -> Void)?

    var statusText: String {
        switch results.count {
        case 0: return L("search.noResults")
        case 1: return L("search.oneResult")
        default: return LocalizationManager.shared.format("search.results", results.count)
        }
    }

    func refreshLocalizedContent() {
        if page == .main {
            if query.isEmpty {
                results = buildDefaultResults()
            } else {
                performSearch(query: query)
            }
            selectedIndex = min(selectedIndex, max(results.count - 1, 0))
        }
    }

    /// Consume clipboard context only once for each system pasteboard version.
    func consumeClipboardContextIfNeeded(_ text: String?, changeCount: Int) -> Bool {
        guard lastConsumedClipboardChangeCount != changeCount else {
            clearClipboardContext()
            return false
        }
        lastConsumedClipboardChangeCount = changeCount
        updateClipboardContext(text)
        return true
    }

    /// Clear clipboard-derived state without touching the system pasteboard.
    func clearClipboardContext() {
        clipboardText = nil
        clipboardJSON = nil
        results = []
        selectedIndex = 0
        onResultsChanged?()
    }

    func updateClipboardContext(_ text: String?) {
        let original = text ?? ""
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clipboardText = nil
            clipboardJSON = nil
            if page == .main && query.isEmpty {
                results = buildDefaultResults()
                selectedIndex = 0
                onResultsChanged?()
            }
            return
        }

        clipboardJSON = JSONFormatterCore.decodeJSONDocumentStringOnce(original)
            ?? (JSONFormatterCore.isValidJSON(original) ? original : nil)
        if clipboardJSON != nil {
            clipboardText = nil
            query = ""
            results = buildDefaultResults()
        } else {
            clipboardJSON = nil
            clipboardText = original
            query = ""
            performSearch(query: original)
        }
        selectedIndex = 0
    }

    var hasClipboardText: Bool { clipboardText != nil }

    func useClipboardTextAsQuery() {
        guard let text = clipboardText else { return }
        clipboardText = nil
        updateQuery(text)
    }

    /// Update the query and its results in the same input event, avoiding a deferred view update.
    func updateQuery(_ newQuery: String) {
        guard query != newQuery else { return }
        if !newQuery.isEmpty {
            clipboardText = nil
            clipboardJSON = nil
        }
        query = newQuery
        if !newQuery.isEmpty {
            isApplicationGridExpanded = false
        }
        performSearch(query: newQuery)
    }

    func openJSONFormatter(with text: String? = nil, format: Bool = false) {
        let input = text ?? clipboardJSON ?? ""
        if format, let formatted = try? JSONFormatterCore.format(input) {
            jsonFormatterInput = formatted
        } else {
            jsonFormatterInput = input
        }
        page = .main
        searchMode = .apps
        isJSONFormatterExpanded = true
        onJSONFormatterExpansionChanged?(true)
    }

    func collapseJSONFormatter() {
        isJSONFormatterExpanded = false
        onJSONFormatterExpansionChanged?(false)
    }

    func requestJSONFormatterWindow() {
        isJSONFormatterExpanded = false
        onJSONFormatterExpansionChanged?(false)
        shouldOpenJSONFormatterWindow = true
        onOpenJSONFormatterWindow?()
    }

    func reopenJSONFormatterInline() {
        isJSONFormatterExpanded = true
        onJSONFormatterExpansionChanged?(true)
    }

    func didOpenJSONFormatterWindow() {
        shouldOpenJSONFormatterWindow = false
    }

    func didCloseJSONFormatterWindow() {
        shouldOpenJSONFormatterWindow = false
    }

    var hasClipboardJSON: Bool { clipboardJSON != nil }

    var searchPlaceholder: String {
        searchMode == .claude
            ? L("search.claudePlaceholder")
            : "搜索应用和指令/粘贴文件或图片"
    }

    var compactApplicationResults: [SearchResult] {
        guard query.isEmpty, isApplicationIndexReady else { return [] }
        let recentApplications = results.filter { $0.subtitle == L("search.application") }
        var applications = ApplicationGridPresentation.collapsedItems(
            recent: recentApplications,
            all: allApplications,
            maximumCount: ApplicationGridPresentation.collapsedItemCount,
            id: { $0.stableID }
        )
        if let clipboardCommand = results.first(where: { $0.title == L("search.openJSON") }) {
            applications.insert(clipboardCommand, at: 0)
        }
        return applications
    }

    var launchpadApplicationResults: [SearchResult] {
        guard query.isEmpty, isApplicationIndexReady else { return [] }
        return allApplications
    }

    var displayedApplicationResults: [SearchResult] {
        guard query.isEmpty else { return results }
        if hasClipboardText || hasClipboardJSON { return results }
        return isApplicationGridExpanded ? launchpadApplicationResults : compactApplicationResults
    }
    var expandableApplicationCount: Int {
        allApplications.count
    }

    func setApplicationGridExpanded(_ expanded: Bool) {
        isApplicationGridExpanded = expanded
        selectedIndex = 0
        onApplicationGridExpansionChanged?()
    }

    func resetApplicationGridExpansion() {
        isApplicationGridExpanded = false
        selectedIndex = 0
    }

    func clearQuery() {
        query = ""
        results = []
        selectedIndex = 0
    }

    func selectAll() {
        shouldSelectAll = true
    }

    /// Re-scan installed applications in the background, then refresh the
    /// visible results. Picks up apps installed (or removed) since launch,
    /// since `rc_discover_apps` otherwise only runs once at startup.
    /// Runs off the main thread so panel appearance isn't blocked.
    func refreshApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            let _ = rc_discover_apps(false)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.page == .main else { return }
                if self.query.isEmpty {
                    self.applyApplicationRefresh(
                        allApplications: self.loadAllApplications(),
                        recentApplications: self.buildDefaultResults()
                    )
                } else {
                    self.performSearch(query: self.query)
                }
            }
        }
    }

    func applyApplicationRefresh(
        allApplications: [SearchResult],
        recentApplications: [SearchResult]
    ) {
        self.allApplications = allApplications
        if query.isEmpty, let clipboardText {
            performSearch(query: clipboardText)
        } else if query.isEmpty, hasClipboardJSON {
            results = buildDefaultResults()
        } else {
            results = recentApplications
        }
        selectedIndex = 0
        isApplicationIndexReady = true
        onApplicationIndexReady?()
        onApplicationGridExpansionChanged?()
        onResultsChanged?()
    }

    // MARK: - Navigation

    func goToSnippets() {
        page = .snippets
        snippetFilter = ""
        snippetSelectedIndex = 0
        isEditingSnippet = false
        editingSnippet = nil
        loadSnippets()
        focusFilterField()
    }

    func goToAICommands() {
        page = .aiCommands
        aiCommandFilter = ""
        aiCommandSelectedIndex = 0
        isEditingAICommand = false
        editingAICommand = nil
        loadAICommands()
        focusFilterField()
    }

    func goBack() {
        let wasPlugin = page == .plugin
        if page == .claude {
            claudeCancel()
            claudeMessages.removeAll()
            claudeSessionId = nil // start fresh next time
        }
        if page == .aiCommands && isEditingAICommand {
            cancelEditingAICommand()
            return
        }
        page = .main
        activePlugin = nil
        activePluginFeatureCode = nil
        searchMode = .apps
        if wasPlugin { onPluginExit?() }
        // TextField is always in the view hierarchy (ZStack), so focus immediately.
        // selectAll is chained after focus succeeds to avoid race conditions.
        focusFilterField(then: { [weak self] in self?.selectAll() })
    }

    // MARK: - Main search

    private func loadPluginsIfNeeded() {
        guard pluginRegistry.plugins.isEmpty else { return }
        try? pluginRegistry.load()
    }

    func performSearch(query: String) {
        guard !query.isEmpty else {
            results = buildDefaultResults()
            selectedIndex = 0
            onResultsChanged?()
            return
        }

        // Check for /cc prefix (Claude Code)
        if query.hasPrefix("/cc ") {
            let prompt = String(query.dropFirst(4))
            results = [
                SearchResult(
                    title: LocalizationManager.shared.format("search.askClaude", prompt),
                    subtitle: "Claude Code",
                    icon: nil,
                    systemIcon: "bubble.left.fill"
                ) { [weak self] in
                    self?.startClaude(prompt: prompt)
                }
            ]
            selectedIndex = 0
            return
        }

        // A valid local directory is always the first result.
        var finderResults: [SearchResult] = []
        if let finderResult = FinderPathResult.resolve(query) {
            finderResults.append(SearchResult(
                title: finderResult.title,
                subtitle: finderResult.subtitle,
                icon: nil,
                systemIcon: "folder.fill"
            ) {
                NSWorkspace.shared.open(finderResult.url)
            })
        }

        // Search apps via Rust FFI
        var appResults: [SearchResult] = []

        if let cStr = rc_search_apps(query) {
            let jsonStr = String(cString: cStr)
            rc_free_string(cStr)

            if let data = jsonStr.data(using: .utf8),
               let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                appResults = entries.prefix(8).map { entry in
                    let name = entry["display_name"] as? String ?? ""
                    let path = entry["path"] as? String ?? ""
                    let ranking = entry["ranking"] as? Int ?? 0
                    let icon = self.loadAppIcon(path: path)
                    var result = SearchResult(
                        title: name,
                        subtitle: L("search.application"),
                        icon: icon,
                        systemIcon: "app.fill",
                        stableIdentity: path,
                        score: fuzzyScore(query, name) + ranking
                    ) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        rc_update_ranking(path)
                    }
                    result.actions = Self.appActions(path: path)
                    return result
                }
            }
        }

        // Search snippets
        var snippetResults: [SearchResult] = []
        if let cStr = rc_snippets_load() {
            let jsonStr = String(cString: cStr)
            rc_free_string(cStr)

            if let data = jsonStr.data(using: .utf8),
               let snippets = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                snippetResults = snippets
                    .filter { snippet in
                        let name = snippet["name"] as? String ?? ""
                        let keyword = snippet["keyword"] as? String ?? ""
                        return fuzzyMatch(query, name) || fuzzyMatch(query, keyword)
                    }
                    .prefix(5)
                    .map { snippet in
                        let name = snippet["name"] as? String ?? ""
                        let keyword = snippet["keyword"] as? String ?? ""
                        let expansion = snippet["expansion"] as? String ?? ""
                        return SearchResult(
                            title: name,
                            subtitle: LocalizationManager.shared.format("search.snippet", keyword),
                            icon: nil,
                            systemIcon: "doc.text.fill"
                        ) { [weak self] in
                            self?.expandAndPasteSnippet(expansion)
                        }
                    }
            }
        }

        // Built-in commands that fuzzy match
        var commandResults: [SearchResult] = []
        let q = query.lowercased()

        // AI commands (built-in + custom) — fuzzy match. Hidden entirely when
        // the AI master switch is off.
        if aiEnabled {
            let matchingAICommands = AICommand.loadAll().filter { cmd in
                fuzzyMatch(q, cmd.name)
            }
            let rankedAICommands = matchingAICommands.sorted { a, b in
                self.commandRanking(for: a.name) > self.commandRanking(for: b.name)
            }
            for cmd in rankedAICommands.prefix(6) {
                let command = cmd
                let cmdScore = fuzzyScore(q, command.name) + self.commandRanking(for: command.name)
                var result = SearchResult(
                    title: command.name,
                    subtitle: L("search.aiCommand"),
                    icon: nil,
                    systemIcon: command.icon,
                    score: cmdScore
                ) { [weak self] in
                    self?.incrementCommandRanking(command.name)
                    self?.executeAICommand(command)
                }
                result.actions = aiCommandActions(for: command)
                commandResults.append(result)
            }

            if fuzzyMatch(q, "ai commands") || fuzzyMatch(q, "manage ai commands") {
                commandResults.append(SearchResult(
                    title: L("settings.aiCommands"),
                    subtitle: L("search.manageAICommands"),
                    icon: nil,
                    systemIcon: "sparkle",
                    score: fuzzyScore(q, "AI Commands")
                ) { [weak self] in
                    self?.goToAICommands()
                })
            }
        }

        if fuzzyMatch(q, "snippets") {
            let r = SearchResult(
                title: L("settings.snippets"),
                subtitle: L("search.command"),
                icon: nil,
                systemIcon: "text.quote",
                score: fuzzyScore(query, "Snippets") + commandRanking(for: "Snippets")
            ) { [weak self] in
                self?.incrementCommandRanking("Snippets")
                self?.goToSnippets()
            }
            commandResults.append(r)
        }

        if fuzzyMatch(q, "json formatter") || fuzzyMatch(q, "json 格式化") || fuzzyMatch(q, "json-editor") || fuzzyMatch(q, "json editor") {
            commandResults.append(SearchResult(title: L("json.title"), subtitle: L("search.jsonSubtitle"), icon: nil, systemIcon: "curlybraces", score: fuzzyScore(query, "JSON Formatter")) { [weak self] in
                self?.openJSONFormatter()
            })
        }

        if ["plugins", "plugin center", "插件", "插件中心", "插件市场"].contains(where: { fuzzyMatch(q, $0) }) {
            commandResults.append(SearchResult(title: L("plugin.center.title"), subtitle: L("search.command"), icon: nil, systemIcon: "puzzlepiece.extension", score: fuzzyScore(query, "Plugin Center")) { [weak self] in
                self?.page = .pluginCenter
            })
        }

        loadPluginsIfNeeded()
        let pluginResults = pluginSearchProvider.candidates(from: pluginRegistry.plugins)
            .filter { pluginSearchProvider.matches(query: query, candidate: $0) }
            .map { candidate in
                SearchResult(
                    title: candidate.title,
                    subtitle: candidate.subtitle,
                    icon: nil,
                    systemIcon: "puzzlepiece.extension",
                    score: fuzzyScore(query, candidate.title)
                ) { [weak self] in
                    guard let self, let registration = self.pluginRegistry.plugin(id: candidate.pluginID) else { return }
                    self.activePlugin = registration
                    self.activePluginFeatureCode = candidate.featureCode
                    self.page = .plugin
                    self.onPluginFeatureSelected?(candidate.pluginID, candidate.featureCode)
                }
            }

        var allResults = appResults + commandResults + snippetResults + pluginResults
        allResults.sort { $0.score > $1.score }
        results = Array(finderResults + allResults.prefix(19))
        selectedIndex = 0
        onResultsChanged?()
    }

    func moveSelection(by offset: Int) {
        switch page {
        case .snippets:
            let count = filteredSnippets.count
            guard count > 0 else { return }
            snippetSelectedIndex = max(0, min(snippetSelectedIndex + offset, count - 1))
        case .aiCommands:
            let count = filteredAICommands.count
            guard count > 0 else { return }
            aiCommandSelectedIndex = max(0, min(aiCommandSelectedIndex + offset, count - 1))
        case .main:
            guard !results.isEmpty else { return }
            selectedIndex = max(0, min(selectedIndex + offset, results.count - 1))
        case .claude, .plugin, .pluginCenter:
            break // no list navigation on non-list pages
        }
    }

    func openSelected() {
        switch page {
        case .snippets:
            expandSelectedSnippet()
        case .aiCommands:
            executeSelectedAICommand()
        case .main:
            let displayedResults = displayedApplicationResults
            guard displayedResults.indices.contains(selectedIndex) else { return }
            displayedResults[selectedIndex].action()
        case .claude, .plugin, .pluginCenter:
            break
        }
    }

    // MARK: - Snippets

    func loadSnippets() {
        guard let cStr = rc_snippets_load() else { return }
        let jsonStr = String(cString: cStr)
        rc_free_string(cStr)

        guard let data = jsonStr.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        snippets = entries.map { entry in
            SnippetItem(
                id: entry["id"] as? String ?? UUID().uuidString,
                name: entry["name"] as? String ?? "",
                keyword: entry["keyword"] as? String ?? "",
                expansion: entry["expansion"] as? String ?? ""
            )
        }
        snippetSelectedIndex = 0
    }

    func saveSnippets() {
        let jsonArray: [[String: Any]] = snippets.map { s in
            ["id": s.id, "name": s.name, "keyword": s.keyword, "expansion": s.expansion]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: jsonArray),
              let jsonStr = String(data: data, encoding: .utf8) else { return }
        let _ = rc_snippets_save(jsonStr)
        onSnippetsChanged?()
    }

    var filteredSnippets: [SnippetItem] {
        if snippetFilter.isEmpty { return snippets }
        let q = snippetFilter.lowercased()
        return snippets.filter {
            $0.name.lowercased().contains(q) || $0.keyword.lowercased().contains(q)
        }
    }

    func addSnippet() {
        editingSnippet = .new()
        isEditingSnippet = true
    }

    func editSelectedSnippet() {
        let items = filteredSnippets
        guard snippetSelectedIndex < items.count else { return }
        editingSnippet = items[snippetSelectedIndex]
        isEditingSnippet = true
    }

    func saveEditingSnippet() {
        guard let editing = editingSnippet else { return }
        if let idx = snippets.firstIndex(where: { $0.id == editing.id }) {
            snippets[idx] = editing
        } else {
            snippets.append(editing)
        }
        saveSnippets()
        isEditingSnippet = false
        editingSnippet = nil
        focusFilterField()
    }

    func cancelEditingSnippet() {
        isEditingSnippet = false
        editingSnippet = nil
        focusFilterField()
    }

    func deleteSnippet(id: String) {
        snippets.removeAll { $0.id == id }
        saveSnippets()
        if snippetSelectedIndex >= filteredSnippets.count {
            snippetSelectedIndex = max(0, filteredSnippets.count - 1)
        }
    }

    func expandSelectedSnippet() {
        let items = filteredSnippets
        guard snippetSelectedIndex < items.count else { return }
        expandAndPasteSnippet(items[snippetSelectedIndex].expansion)
    }

    /// Expand a snippet's placeholders, put the result on the pasteboard,
    /// and paste it into the frontmost app.
    private func expandAndPasteSnippet(_ expansion: String) {
        let clipboardText = NSPasteboard.general.string(forType: .string)
        guard let cStr = rc_snippet_expand(expansion, clipboardText) else { return }
        let expanded = String(cString: cStr)
        rc_free_string(cStr)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(expanded, forType: .string)
        onPasteAndHide?()
    }

    // MARK: - AI Commands

    func loadAICommands() {
        aiCommands = AICommand.loadAll()
        aiCommandSelectedIndex = 0
    }

    /// Load AI settings (`ai_enabled` master switch and the agent CLI binary)
    /// from config.toml. Called at startup and each time the panel opens, so
    /// changes in Settings take effect the next time the launcher is shown.
    func loadAISettings() {
        guard let cStr = rc_config_load() else { return }
        let jsonStr = String(cString: cStr)
        rc_free_string(cStr)
        guard let data = jsonStr.data(using: .utf8),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        aiEnabled = config["ai_enabled"] as? Bool ?? true
        claudeBinary = (config["claude_binary"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "claude"
        exitAISurfacesIfDisabled()
    }

    /// When AI is disabled, leave any active AI surface (Claude chat or the AI
    /// Commands page) so the launcher doesn't reopen mid-conversation or stuck
    /// on a now-hidden page. No-op while AI is enabled.
    private func exitAISurfacesIfDisabled() {
        guard !aiEnabled else { return }
        if page == .claude {
            claudeCancel()
            claudeMessages.removeAll()
            claudeSessionId = nil
        }
        if page == .claude || page == .aiCommands {
            page = .main
        }
        searchMode = .apps
    }

    func saveAICommands() {
        let jsonArray: [[String: Any]] = aiCommands.map { cmd in
            ["name": cmd.name, "icon": cmd.icon, "prompt": cmd.prompt]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: jsonArray),
              let jsonStr = String(data: data, encoding: .utf8) else { return }
        let _ = rc_ai_commands_save(jsonStr)
    }

    var filteredAICommands: [AICommand] {
        if aiCommandFilter.isEmpty { return aiCommands }
        let q = aiCommandFilter.lowercased()
        return aiCommands.filter { $0.name.lowercased().contains(q) }
    }

    func addAICommand() {
        editingAICommand = .new()
        isEditingAICommand = true
    }

    func editSelectedAICommand() {
        let items = filteredAICommands
        guard aiCommandSelectedIndex < items.count else { return }
        editingAICommand = items[aiCommandSelectedIndex]
        isEditingAICommand = true
    }

    func saveEditingAICommand() {
        guard let editing = editingAICommand else { return }
        if let idx = aiCommands.firstIndex(where: { $0.id == editing.id }) {
            aiCommands[idx] = editing
        } else {
            aiCommands.append(editing)
        }
        // Update id to match name (used as stable identifier)
        if let idx = aiCommands.firstIndex(where: { $0.id == editing.id }) {
            aiCommands[idx].id = editing.name
        }
        saveAICommands()
        isEditingAICommand = false
        editingAICommand = nil
        focusFilterField()
    }

    func cancelEditingAICommand() {
        isEditingAICommand = false
        editingAICommand = nil
        focusFilterField()
    }

    func deleteAICommand(id: String) {
        aiCommands.removeAll { $0.id == id }
        saveAICommands()
        if aiCommandSelectedIndex >= filteredAICommands.count {
            aiCommandSelectedIndex = max(0, filteredAICommands.count - 1)
        }
    }

    private func aiCommandActions(for command: AICommand) -> [ActionItem] {
        [
            ActionItem(title: L("common.edit"), icon: "pencil", shortcut: nil, keepPanel: true) { [weak self] in
                self?.goToAICommands()
                if let idx = self?.aiCommands.firstIndex(where: { $0.id == command.id }) {
                    self?.aiCommandSelectedIndex = idx
                    self?.editSelectedAICommand()
                }
            },
            ActionItem(title: L("search.manageAICommands"), icon: "sparkle", shortcut: nil, keepPanel: true) { [weak self] in
                self?.goToAICommands()
            },
        ]
    }

    func executeSelectedAICommand() {
        let items = filteredAICommands
        guard aiCommandSelectedIndex < items.count else { return }
        let command = items[aiCommandSelectedIndex]
        executeAICommand(command)
    }

    // MARK: - Action Panel

    /// Get actions for the currently selected result.
    var currentActions: [ActionItem] {
        switch page {
        case .main:
            let displayedResults = displayedApplicationResults
            guard displayedResults.indices.contains(selectedIndex) else { return [] }
            return displayedResults[selectedIndex].actions
        default:
            return []
        }
    }

    func toggleActionPanel() {
        showActionPanel = !currentActions.isEmpty && !showActionPanel
    }

    /// App-specific actions.
    static func appActions(path: String) -> [ActionItem] {
        [
            ActionItem(title: L("action.openApplication"), icon: "arrow.up.forward.app", shortcut: "↵") {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            },
            ActionItem(title: L("action.showFinder"), icon: "folder", shortcut: nil) {
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            },
            ActionItem(title: L("action.showInfo"), icon: "info.circle", shortcut: nil) {
                let url = URL(fileURLWithPath: path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
                // Cmd+I after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let source = CGEventSource(stateID: .combinedSessionState)
                    let iDown = CGEvent(keyboardEventSource: source, virtualKey: 0x22, keyDown: true)
                    iDown?.flags = .maskCommand
                    iDown?.post(tap: .cghidEventTap)
                    let iUp = CGEvent(keyboardEventSource: source, virtualKey: 0x22, keyDown: false)
                    iUp?.flags = .maskCommand
                    iUp?.post(tap: .cghidEventTap)
                }
            },
            ActionItem(title: L("action.copyPath"), icon: "doc.on.doc", shortcut: nil) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            },
            ActionItem(title: L("action.copyBundleID"), icon: "number", shortcut: nil) {
                if let bundle = Bundle(path: path), let id = bundle.bundleIdentifier {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(id, forType: .string)
                }
            },
        ]
    }

    // MARK: - Default Results

    /// Build recent applications shown when the search query is empty.
    private func buildDefaultResults() -> [SearchResult] {
        if let clipboardJSON {
            return [SearchResult(
                title: L("search.openJSON"),
                subtitle: L("search.detectedJSON"),
                icon: nil,
                systemIcon: "curlybraces"
            ) { [weak self] in
                self?.openJSONFormatter(with: clipboardJSON, format: true)
            }]
        }
        guard let cStr = rc_get_top_apps(
            UInt64(MainSearchGridMetrics.columnCount * MainSearchGridMetrics.collapsedRowCount)
        ) else { return [] }
        defer { rc_free_string(cStr) }
        var results = appResults(fromJSON: String(cString: cStr))
        if let clipboardJSON {
            results.insert(SearchResult(
                title: L("search.openJSON"),
                subtitle: L("search.detectedJSON"),
                icon: nil,
                systemIcon: "curlybraces"
            ) { [weak self] in
                self?.openJSONFormatter(with: clipboardJSON, format: true)
            }, at: 0)
        }
        return results
    }

    private func loadAllApplications() -> [SearchResult] {
        guard let cStr = rc_get_all_apps() else { return [] }
        defer { rc_free_string(cStr) }
        return appResults(fromJSON: String(cString: cStr))
    }

    private func appResults(fromJSON json: String) -> [SearchResult] {
        guard let data = json.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return entries.map { entry in
            let name = entry["display_name"] as? String ?? ""
            let path = entry["path"] as? String ?? ""
            let icon = loadAppIcon(path: path)
            var result = SearchResult(
                title: name,
                subtitle: L("search.application"),
                icon: icon,
                systemIcon: "app.fill",
                stableIdentity: path
            ) {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                rc_update_ranking(path)
            }
            result.actions = Self.appActions(path: path)
            return result
        }
    }

    // MARK: - AI Commands

    /// Callback to grab selection from previous app (set by SearchPanel)
    var onGrabSelection: ((@escaping (String) -> Void) -> Void)?

    func executeAICommand(_ command: AICommand) {
        // Ask the panel to hide, grab selection from previous app, then proceed
        onGrabSelection? { [weak self] selectedText in
            guard let self else { return }

            guard !selectedText.isEmpty else {
                self.searchMode = .claude
                self.claudeMessages.append(ClaudeMessage(role: .assistant, text: "Please select some text in another app first, then try this command again."))
                self.page = .claude
                return
            }

            let prompt = command.prompt.replacingOccurrences(of: "{selection}", with: selectedText)
            self.searchMode = .claude
            self.query = prompt
            self.claudeAsk()
        }
    }

    // MARK: - Claude

    func toggleSearchMode() {
        // Claude mode is an AI surface — disabled when the master switch is off.
        guard aiEnabled else { return }
        if searchMode == .apps {
            searchMode = .claude
            results = []
        } else {
            searchMode = .apps
            claudeCancel()
            performSearch(query: query)
        }
    }

    func claudeAsk() {
        guard aiEnabled else { return }
        guard !query.isEmpty else { return }
        let prompt = query

        // Add user message
        claudeMessages.append(ClaudeMessage(role: .user, text: prompt))

        // Add empty assistant message (will be filled by streaming)
        claudeMessages.append(ClaudeMessage(role: .assistant, text: ""))

        // Switch to Claude page
        page = .claude
        claudeIsStreaming = true
        query = ""

        // Start session via Rust FFI
        // Only resume if we're on the Claude page already (continuing a conversation)
        let resumeId = (page == .claude) ? claudeSessionId : nil
        guard let session = rc_claude_start(prompt, claudeBinary, resumeId) else {
            // Update last message with error
            if let lastIdx = claudeMessages.indices.last {
                claudeMessages[lastIdx].text = "Error: Could not start AI session. Is `\(claudeBinary)` installed?"
            }
            claudeIsStreaming = false
            return
        }
        claudeSession = session

        // Stream chunks in background (blocking reads on detached thread)
        let sendablePtr = SendablePointer(ptr: session)
        Task.detached {
            let ptr = sendablePtr.ptr
            var gotAnyText = false
            while true {
                guard let cStr = rc_claude_next_chunk(ptr) else {
                    // Stream done — capture session_id for resume
                    if let sidStr = rc_claude_get_session_id(ptr) {
                        let sid = String(cString: sidStr)
                        rc_free_string(sidStr)
                        await MainActor.run { [weak self] in
                            self?.claudeSessionId = sid
                        }
                    }

                    // If no text was received, show error
                    if !gotAnyText {
                        var errorMsg = "Claude process ended without output."
                        if let errStr = rc_claude_get_stderr(ptr) {
                            let stderr = String(cString: errStr)
                            rc_free_string(errStr)
                            if !stderr.isEmpty {
                                errorMsg = stderr
                            }
                        }
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            if let lastIdx = self.claudeMessages.indices.last {
                                self.claudeMessages[lastIdx].text = errorMsg
                            }
                            self.claudeSessionId = nil
                        }
                    }
                    await MainActor.run { [weak self] in
                        self?.claudeIsStreaming = false
                        self?.claudeSession = nil
                    }
                    rc_claude_free(ptr)
                    break
                }

                let chunk = String(cString: cStr)
                rc_free_string(cStr)
                gotAnyText = true

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if let lastIdx = self.claudeMessages.indices.last {
                        self.claudeMessages[lastIdx].text += chunk
                    }
                }
            }
        }
    }

    func claudeCancel() {
        if let session = claudeSession {
            rc_claude_cancel(session)
            // Don't free here — background reader thread still holds the pointer.
            // It will be freed when rc_claude_next_chunk returns nil.
            claudeSession = nil
        }
        claudeIsStreaming = false
    }

    /// Replace the selected text in the previous app with the last Claude response.
    func replaceSelectedText() {
        guard let lastResponse = claudeMessages.last(where: { $0.role == .assistant }),
              !lastResponse.text.isEmpty else { return }

        // Write response to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastResponse.text, forType: .string)

        // Hide panel and paste into previous app
        onPasteAndHide?()
    }

    func claudeCopyLastResponse() {
        if let last = claudeMessages.last(where: { $0.role == .assistant }) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(last.text, forType: .string)
        }
    }

    // MARK: - Command Ranking

    func incrementCommandRanking(_ name: String) {
        let key = "cmd:\(name)"
        let _ = rc_increment_ranking(key)
    }

    func commandRanking(for name: String) -> Int {
        let key = "cmd:\(name)"
        return Int(rc_get_ranking(key))
    }

    // MARK: - Focus

    /// Force focus on the first visible, editable text field.
    /// SwiftUI @FocusState doesn't work reliably with NSPanel + nonActivatingPanel,
    /// so we use AppKit directly. Retries up to 3 times with short delays to handle
    /// SwiftUI render lag (e.g. conditional view mounting or .disabled toggling).
    func focusFilterField(then completion: (() -> Void)? = nil) {
        func tryFocus(attempts: Int) {
            guard attempts > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let window = NSApp.keyWindow,
                   let textField = Self.findTextField(in: window.contentView) {
                    window.makeFirstResponder(textField)
                    completion?()
                } else {
                    tryFocus(attempts: attempts - 1)
                }
            }
        }
        tryFocus(attempts: 3)
    }

    private static func findTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let tf = view as? NSTextField, tf.isEditable {
            return tf
        }
        for subview in view.subviews {
            if let found = findTextField(in: subview) {
                return found
            }
        }
        return nil
    }

    // MARK: - Private

    private func loadAppIcon(path: String) -> NSImage? {
        if let cached = iconCache[path] {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)
        iconCache[path] = icon
        return icon
    }

    private func startClaude(prompt: String) {
        query = prompt
        searchMode = .claude
        claudeAsk()
    }
}
