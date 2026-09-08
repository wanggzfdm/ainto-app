import Foundation
import Combine

/// Languages supported by Ainto's user interface.
enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    static func systemDefault(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let identifier = preferredLanguages.first else { return .english }
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized.hasPrefix("zh-hans") || normalized == "zh-cn" || normalized.hasPrefix("zh-cn-") {
            return .simplifiedChinese
        }
        return .english
    }
}

/// Central UI localization state. Language changes are persisted and published immediately.
@MainActor
final class LocalizationManager: ObservableObject {
    static let storageKey = "appLanguage"
    static let shared = LocalizationManager()

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Self.storageKey)
            NotificationCenter.default.post(name: .appLanguageDidChange, object: self)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        if let rawValue = defaults.string(forKey: Self.storageKey),
           let saved = AppLanguage(rawValue: rawValue) {
            language = saved
        } else {
            language = AppLanguage.systemDefault(preferredLanguages: preferredLanguages)
        }
    }

    func text(_ key: String) -> String {
        let english = Self.english[key] ?? key
        guard language == .simplifiedChinese else { return english }
        return Self.simplifiedChinese[key] ?? english
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }

    private static let english: [String: String] = [
        "test.englishOnly": "English fallback",
        "settings.title": "Settings",
        "settings.general": "General", "settings.ai": "AI", "settings.snippets": "Snippets", "settings.data": "Data", "settings.about": "About",
        "settings.language": "Language", "settings.languageHint": "Changes apply immediately", "settings.hotkey": "Hotkey", "settings.launchAtLogin": "Launch at login",
        "settings.resetRankings": "Reset Rankings", "common.cancel": "Cancel", "common.reset": "Reset", "common.edit": "Edit", "common.delete": "Delete", "common.open": "Open", "common.fix": "Fix",
        "settings.resetMessage": "This will reset all app and command usage rankings. This cannot be undone.",
        "settings.spotlightWarning": "Uncheck \"Show Spotlight search\" in Keyboard → Keyboard Shortcuts → Spotlight.",
        "settings.raycastWarning": "Raycast is using the same hotkey (%@). Quit Raycast or choose a different hotkey.",
        "settings.enabled": "Enabled", "settings.aiDisabledHint": "Hides every AI feature in the launcher when off, including AI Commands and Claude mode.",
        "settings.binaryPath": "Binary path", "settings.claudeHint": "Press Tab in the launcher to switch to Claude mode.", "settings.aiCommands": "AI Commands",
        "settings.aiCommandsHint": "Add, remove, or modify AI commands", "settings.selectionHint": "Use {selection} as placeholder for selected text in prompts.",
        "settings.textExpansion": "Text expansion", "settings.snippetsHint": "Manage snippet keywords and expansions",
        "settings.snippetsPermission": "Snippets expand automatically when you type their keyword in any app. Requires Accessibility permission.",
        "settings.configDirectory": "Config directory", "settings.usageRankings": "Usage rankings", "settings.rankingsHint": "Frecency data for apps and commands",
        "settings.version": "Version %@", "settings.tagline": "A personal macOS launcher\nbuilt with Swift + Rust", "settings.star": "Star on GitHub", "settings.reportIssue": "Report Issue", "settings.checkUpdates": "Check for Updates",
        "tray.hotkey": "Hotkey", "tray.settings": "Settings...", "tray.quit": "Quit Ainto",
        "search.placeholder": "Search...", "search.claudePlaceholder": "Ask Claude anything...", "search.modeSearch": "Search", "search.modeAI": "AI mode",
        "search.noResults": "No results", "search.oneResult": "1 result", "search.results": "%d results", "search.askClaude": "Ask Claude: %@",
        "search.application": "Application", "search.snippet": "Snippet: %@", "search.aiCommand": "AI Command", "search.manageAICommands": "Manage AI Commands", "search.command": "Command", "search.jsonSubtitle": "Format, minify, and query JSON", "search.openJSON": "Open JSON in JSON Formatter", "search.detectedJSON": "Detected JSON", "search.clipboardJSONPlaceholder": "JSON copied — press Enter to format", "search.clipboardJSONStatus": "JSON copied",
        "hint.actions": "actions", "hint.navigate": "navigate", "hint.open": "open", "hint.clear": "clear", "hint.aiMode": "AI mode", "hint.save": "save", "hint.cancel": "cancel", "hint.new": "new", "hint.edit": "edit", "hint.run": "run", "hint.back": "back", "hint.paste": "paste", "hint.replace": "replace", "hint.copy": "copy", "hint.send": "send", "hint.close": "close",
        "snippet.create": "Create Snippet", "snippet.edit": "Edit Snippet", "snippet.filter": "Filter snippets...", "snippet.empty": "No snippets", "snippet.createHint": "Press ⌘N to create one", "snippet.count": "%d snippets", "snippet.untitled": "Untitled", "snippet.select": "Select a snippet",
        "snippet.information": "Information", "snippet.name": "Name", "snippet.keyword": "Keyword", "snippet.characters": "Characters", "snippet.formName": "Snippet name", "snippet.snippet": "Snippet", "snippet.keywordPlaceholder": "Optional keyword", "snippet.dynamicHint": "Include **Dynamic Placeholders** for context like the copied text or the current date: `{date}` `{time}` `{clipboard}` `{uuid}`",
        "aiCommand.create": "Create AI Command", "aiCommand.edit": "Edit AI Command", "aiCommand.filter": "Filter commands...", "aiCommand.empty": "No AI commands", "aiCommand.createHint": "Click + to create one", "aiCommand.untitled": "Untitled", "aiCommand.select": "Select a command", "aiCommand.information": "Information", "aiCommand.name": "Name", "aiCommand.icon": "Icon", "aiCommand.input": "Input", "aiCommand.selectedText": "Selected text", "aiCommand.commandName": "Command name", "aiCommand.iconPlaceholder": "SF Symbol name (e.g. sparkle)", "aiCommand.prompt": "Prompt", "aiCommand.selectionHint": "Use `{selection}` as placeholder for the selected text from the frontmost app.",
        "claude.thinking": "Thinking...", "claude.askAnything": "Ask Anything", "claude.askHint": "Type a question and press Enter", "claude.followUp": "Follow up...",
        "action.openApplication": "Open Application", "action.showFinder": "Show in Finder", "action.showInfo": "Show Info in Finder", "action.copyPath": "Copy Path", "action.copyBundleID": "Copy Bundle ID",
        "json.title": "JSON Formatter", "json.format": "Format", "json.minify": "Minify", "json.copy": "Copy", "json.compactCopy": "Minify & Copy", "json.escapedCompactCopy": "Minify, Escape & Copy", "json.collapseAll": "Collapse All", "json.expandAll": "Expand All", "json.clear": "Clear", "json.filter": "JS filter", "json.apply": "Apply", "json.emptyFilter": "Enter a filter expression", "json.openWindow": "Open in separate window", "json.close": "Close JSON editor",
        "plugin.permission.authorizationRequired": "Authorization required", "plugin.permission.notDeclared": "Permission not declared", "plugin.bridge.requestRejected": "Plugin request was rejected", "plugin.permission.requests": "%@ requests %@", "plugin.permission.allow": "Allow", "plugin.permission.deny": "Deny", "plugin.permission.clipboard.read": "clipboard read", "plugin.permission.clipboard.write": "clipboard write", "plugin.permission.storage": "storage", "plugin.permission.network": "network", "plugin.permission.file.open": "file access", "plugin.permission.file.reveal": "file reveal", "plugin.permission.notification": "notifications", "plugin.permission.url.open": "open URLs", "plugin.permission.theme.read": "theme", "plugin.permission.language.read": "language",
        "settings.plugins": "Plugins", "plugin.center.title": "Plugin Center", "plugin.import": "Import Local Plugin", "plugin.reload": "Reload", "plugin.installed": "Installed", "plugin.development": "Development", "plugin.development.add": "Add Development Directory", "plugin.development.remove": "Remove Development Reference", "plugin.empty": "No plugins", "plugin.enabled": "Enabled", "plugin.uninstall": "Uninstall", "plugin.revoke": "Revoke", "plugin.logs": "Sanitized Logs", "plugin.needsAdaptation": "Needs adaptation"
    ]

    private static let simplifiedChinese: [String: String] = [
        "settings.title": "设置",
        "settings.general": "通用", "settings.ai": "AI", "settings.snippets": "文本片段", "settings.data": "数据", "settings.about": "关于",
        "settings.language": "语言", "settings.languageHint": "更改将立即生效", "settings.hotkey": "快捷键", "settings.launchAtLogin": "登录时启动",
        "settings.resetRankings": "重置使用排名", "common.cancel": "取消", "common.reset": "重置", "common.edit": "编辑", "common.delete": "删除", "common.open": "打开", "common.fix": "修复",
        "settings.resetMessage": "这将重置所有应用和命令的使用排名，且无法撤销。", "settings.spotlightWarning": "请在“键盘 → 键盘快捷键 → 聚焦”中取消勾选“显示聚焦搜索”。", "settings.raycastWarning": "Raycast 正在使用相同的快捷键（%@）。请退出 Raycast 或选择其他快捷键。",
        "settings.enabled": "启用", "settings.aiDisabledHint": "关闭后将隐藏启动器中的所有 AI 功能，包括 AI 命令和 Claude 模式。", "settings.binaryPath": "程序路径", "settings.claudeHint": "在启动器中按 Tab 键可切换到 Claude 模式。", "settings.aiCommands": "AI 命令", "settings.aiCommandsHint": "添加、删除或修改 AI 命令", "settings.selectionHint": "在提示词中使用 {selection} 代表所选文本。",
        "settings.textExpansion": "文本扩展", "settings.snippetsHint": "管理文本片段的关键词和展开内容", "settings.snippetsPermission": "在任意应用中输入关键词即可自动展开文本片段，需要辅助功能权限。", "settings.configDirectory": "配置目录", "settings.usageRankings": "使用排名", "settings.rankingsHint": "应用和命令的频率与近期使用数据", "settings.version": "版本 %@", "settings.tagline": "Swift + Rust 构建的\n个人 macOS 启动器", "settings.star": "在 GitHub 点赞", "settings.reportIssue": "报告问题", "settings.checkUpdates": "检查更新",
        "search.placeholder": "搜索...", "search.claudePlaceholder": "向 Claude 提问...", "search.modeSearch": "搜索", "search.modeAI": "AI 模式", "search.noResults": "无结果", "search.oneResult": "1 个结果", "search.results": "%d 个结果", "search.askClaude": "询问 Claude：%@", "search.application": "应用程序", "search.snippet": "文本片段：%@", "search.aiCommand": "AI 命令", "search.manageAICommands": "管理 AI 命令", "search.command": "命令", "search.jsonSubtitle": "格式化、压缩和查询 JSON", "search.openJSON": "使用 JSON 格式化打开", "search.detectedJSON": "检测到 JSON", "search.clipboardJSONPlaceholder": "已复制 JSON，按回车格式化", "search.clipboardJSONStatus": "已复制 JSON",
        "hint.actions": "操作", "hint.navigate": "导航", "hint.open": "打开", "hint.clear": "清除", "hint.aiMode": "AI 模式", "hint.save": "保存", "hint.cancel": "取消", "hint.new": "新建", "hint.edit": "编辑", "hint.run": "运行", "hint.back": "返回", "hint.paste": "粘贴", "hint.replace": "替换", "hint.copy": "复制", "hint.send": "发送", "hint.close": "关闭",
        "snippet.create": "新建文本片段", "snippet.edit": "编辑文本片段", "snippet.filter": "筛选文本片段...", "snippet.empty": "没有文本片段", "snippet.createHint": "按 ⌘N 新建", "snippet.count": "%d 个文本片段", "snippet.untitled": "未命名", "snippet.select": "选择一个文本片段", "snippet.information": "信息", "snippet.name": "名称", "snippet.keyword": "关键词", "snippet.characters": "字符数", "snippet.formName": "文本片段名称", "snippet.snippet": "内容", "snippet.keywordPlaceholder": "可选关键词", "snippet.dynamicHint": "可使用**动态占位符**插入剪贴板文本或当前日期：`{date}` `{time}` `{clipboard}` `{uuid}`",
        "aiCommand.create": "新建 AI 命令", "aiCommand.edit": "编辑 AI 命令", "aiCommand.filter": "筛选命令...", "aiCommand.empty": "没有 AI 命令", "aiCommand.createHint": "点击 + 新建", "aiCommand.untitled": "未命名", "aiCommand.select": "选择一个命令", "aiCommand.information": "信息", "aiCommand.name": "名称", "aiCommand.icon": "图标", "aiCommand.input": "输入", "aiCommand.selectedText": "所选文本", "aiCommand.commandName": "命令名称", "aiCommand.iconPlaceholder": "SF Symbol 名称（如 sparkle）", "aiCommand.prompt": "提示词", "aiCommand.selectionHint": "使用 `{selection}` 代表前台应用中选中的文本。",
        "claude.thinking": "思考中...", "claude.askAnything": "随便问点什么", "claude.askHint": "输入问题并按回车发送", "claude.followUp": "继续提问...",
        "action.openApplication": "打开应用", "action.showFinder": "在 Finder 中显示", "action.showInfo": "在 Finder 中显示简介", "action.copyPath": "复制路径", "action.copyBundleID": "复制 Bundle ID",
        "json.title": "JSON 格式化", "json.format": "格式化", "json.minify": "压缩", "json.copy": "复制", "json.compactCopy": "压缩并复制", "json.escapedCompactCopy": "压缩转义并复制", "json.collapseAll": "折叠全部", "json.expandAll": "展开全部", "json.clear": "清空", "json.filter": "JS 过滤器", "json.apply": "应用", "json.emptyFilter": "请输入过滤表达式", "json.openWindow": "在独立窗口中打开", "json.close": "关闭 JSON 编辑器",
        "plugin.permission.authorizationRequired": "需要授权", "plugin.permission.notDeclared": "未声明权限", "plugin.bridge.requestRejected": "插件请求被拒绝", "plugin.permission.requests": "%@ 请求 %@", "plugin.permission.allow": "允许", "plugin.permission.deny": "拒绝", "plugin.permission.clipboard.read": "读取剪贴板", "plugin.permission.clipboard.write": "写入剪贴板", "plugin.permission.storage": "存储", "plugin.permission.network": "网络", "plugin.permission.file.open": "文件访问", "plugin.permission.file.reveal": "在 Finder 中显示", "plugin.permission.notification": "通知", "plugin.permission.url.open": "打开 URL", "plugin.permission.theme.read": "主题", "plugin.permission.language.read": "语言",
        "settings.plugins": "插件", "plugin.center.title": "插件中心", "plugin.import": "导入本地插件", "plugin.reload": "重新加载", "plugin.installed": "已安装", "plugin.development": "开发", "plugin.development.add": "添加开发目录", "plugin.development.remove": "移除开发引用", "plugin.empty": "暂无插件", "plugin.enabled": "启用", "plugin.uninstall": "卸载", "plugin.revoke": "撤销", "plugin.logs": "脱敏日志", "plugin.needsAdaptation": "需要适配"
    ]
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("appLanguageDidChange")
}

@MainActor
func L(_ key: String) -> String {
    LocalizationManager.shared.text(key)
}
