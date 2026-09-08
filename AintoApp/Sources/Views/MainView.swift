import SwiftUI
import AppKit
import AintoCore

/// Main search view — glassmorphism style matching modern macOS.
struct MainView: View {
    @ObservedObject var viewModel: SearchViewModel
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        Group {
            switch viewModel.page {
            case .main:
                mainSearchView
            case .snippets:
                SnippetView(viewModel: viewModel)
            case .aiCommands:
                AICommandView(viewModel: viewModel)
            case .claude:
                ClaudeView(viewModel: viewModel)
            case .plugin:
                if let plugin = viewModel.activePlugin,
                   let featureCode = viewModel.activePluginFeatureCode {
                    PluginHostView(
                        entryURL: plugin.rootURL.appendingPathComponent(plugin.manifest.main),
                        pluginRootURL: plugin.rootURL,
                        session: PluginHostSession(pluginID: plugin.id, featureCode: featureCode, query: viewModel.query),
                        onExit: { viewModel.goBack() },
                        onResize: { size in viewModel.onPluginResize?(size) ?? size },
                        permissionStore: viewModel.pluginPermissionStore,
                        networkDomains: plugin.manifest.ainto?.networkDomains ?? [],
                        paths: viewModel.pluginPaths,
                        logStore: viewModel.pluginLogStore
                    )
                }
            case .pluginCenter:
                PluginCenterView(model: PluginCenterModel(registry: viewModel.pluginRegistry, permissionStore: viewModel.pluginPermissionStore, logStore: viewModel.pluginLogStore))
                    .padding(20)
                    .frame(width: 800, height: 520, alignment: .topLeading)
            }
        }
        .background {
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                LinearGradient(
                    colors: [Color.white.opacity(0.06), Color.clear],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.05),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.3), radius: 40, x: 0, y: 20)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    private var gridViewportHeight: CGFloat {
        if viewModel.isApplicationGridExpanded { return 420 }
        return viewModel.displayedApplicationResults.count > MainSearchGridMetrics.columnCount ? 154 : 82
    }

    private var mainSearchView: some View {
        VStack(spacing: 0) {
            mainSearchContent
            if viewModel.isJSONFormatterExpanded {
                Divider().opacity(0.5)
                JSONFormatterView(
                    text: $viewModel.jsonFormatterInput,
                    onDetach: { viewModel.requestJSONFormatterWindow() },
                    onClose: { viewModel.collapseJSONFormatter() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.isJSONFormatterExpanded)
    }

    private var mainSearchContent: some View {
        VStack(spacing: 0) {
            // Search input
            HStack(spacing: 14) {
                if viewModel.searchMode == .claude {
                    ClaudeIcon(size: 22)
                } else {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 20, weight: .medium))
                }

                TextField(
                    viewModel.searchPlaceholder,
                    text: Binding(
                        get: { viewModel.query },
                        set: { viewModel.updateQuery($0) }
                    )
                )
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .regular))
                    .onSubmit {
                        viewModel.openSelected()
                    }

                Spacer()
                if viewModel.hasClipboardJSON && viewModel.searchMode == .apps {
                    Label(L("search.clipboardJSONStatus"), systemImage: "doc.on.clipboard")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.tint.opacity(0.14), in: Capsule())
                        .accessibilityLabel(L("search.clipboardJSONStatus"))
                }
                // Mode indicator — hidden when AI is disabled
                if viewModel.aiEnabled {
                    HStack(spacing: 4) {
                        Text(viewModel.searchMode == .claude ? L("search.modeSearch") : L("search.modeAI"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text("Tab")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .onAppear {
                viewModel.focusFilterField()
            }

            // Results grid (hidden in Claude mode)
            if !viewModel.isJSONFormatterExpanded,
               !viewModel.displayedApplicationResults.isEmpty,
               viewModel.searchMode == .apps {
                HStack {
                    Text(viewModel.query.isEmpty ? "最近使用" : "搜索结果")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if viewModel.query.isEmpty, viewModel.expandableApplicationCount > 0 {
                        Button {
                            viewModel.setApplicationGridExpanded(!viewModel.isApplicationGridExpanded)
                        } label: {
                            Text(
                                viewModel.isApplicationGridExpanded
                                    ? "收起"
                                    : "展开（\(viewModel.expandableApplicationCount)）"
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 5)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: viewModel.isApplicationGridExpanded || !viewModel.query.isEmpty) {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 8),
                                count: MainSearchGridMetrics.columnCount
                            ),
                            spacing: 8
                        ) {
                            ForEach(Array(viewModel.displayedApplicationResults.enumerated()), id: \.element.id) { index, result in
                                ResultGridItem(
                                    result: result,
                                    isSelected: index == viewModel.selectedIndex
                                )
                                .id(result.id)
                                .onTapGesture(count: 2) {
                                    viewModel.selectedIndex = index
                                    result.action()
                                }
                                .onTapGesture(count: 1) {
                                    viewModel.selectedIndex = index
                                }
                                .contextMenu {
                                    ForEach(result.actions) { action in
                                        Button(action: {
                                            action.action()
                                        }) {
                                            Label(action.title, systemImage: action.icon)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                    .frame(
                        height: gridViewportHeight
                    )
                    .onChange(of: viewModel.selectedIndex) { _, newIndex in
                        let displayedResults = viewModel.displayedApplicationResults
                        if displayedResults.indices.contains(newIndex) {
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(displayedResults[newIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 800)
        .onChange(of: viewModel.shouldSelectAll) { _, shouldSelect in
            if shouldSelect {
                viewModel.focusFilterField(then: {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                })
                viewModel.shouldSelectAll = false
            }
        }
    }
}

/// A single result in the uTools-style application grid.
struct ResultGridItem: View {
    let result: SearchResult
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: result.displayIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)

            Text(result.title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .padding(.horizontal, 3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.72), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Keyboard shortcut hint badge reused by secondary pages.
struct KeyHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

/// NSVisualEffectView wrapper for SwiftUI — real macOS vibrancy blur.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Claude Code icon using SF Symbol (no Anthropic logo — trademark restriction).
struct ClaudeIcon: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.7))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}
