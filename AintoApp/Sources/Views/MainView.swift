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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: MainPanelLayout.contentAlignment)
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
                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.1), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
        .glassElevation(.mainPanel, shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchResultViewportHeight: CGFloat { 420 }

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
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: MainPanelLayout.contentAlignment)
    }

    private var mainSearchContent: some View {
        VStack(spacing: 0) {
            searchHeader

            if !viewModel.isJSONFormatterExpanded,
               viewModel.searchMode == .apps,
               !(viewModel.query.isEmpty && !viewModel.hasClipboardJSON && !viewModel.hasClipboardText && !viewModel.isApplicationGridExpanded) {
                resultHeader
                if viewModel.query.isEmpty {
                    applicationGrids
                } else {
                    searchResultPage
                }
            }
        }
        .frame(width: 800, alignment: .top)
    }

    private func clipboardTextChip(_ text: String) -> some View {
        Button {
            viewModel.useClipboardTextAsQuery()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.tint.opacity(0.8))
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: 200, minHeight: 36, maxHeight: 36)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            if viewModel.searchMode == .claude {
                ClaudeIcon(size: 22)
            }

            if viewModel.query.isEmpty, let clipboardText = viewModel.clipboardText, viewModel.searchMode == .apps {
                clipboardTextChip(clipboardText)
            }

            ZStack(alignment: .leading) {
                if viewModel.query.isEmpty, !viewModel.hasClipboardText {
                    Text(viewModel.searchPlaceholder)
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }

                TextField(
                    "",
                    text: Binding(
                        get: { viewModel.query },
                        set: { viewModel.updateQuery($0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 25, weight: .regular))
                .frame(height: 48)
                .onSubmit { viewModel.openSelected() }
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
            if viewModel.aiEnabled {
                HStack(spacing: 4)
                {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(height: 58)
        .onAppear { viewModel.focusFilterField() }
    }

    private var resultHeader: some View {
        HStack {
            Text(viewModel.query.isEmpty ? "最近使用" : "搜索结果")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            if viewModel.query.isEmpty, viewModel.expandableApplicationCount > 0 {
                Button {
                    viewModel.setApplicationGridExpanded(!viewModel.isApplicationGridExpanded)
                } label: {
                    Text(viewModel.isApplicationGridExpanded ? "收起" : "展开（\(viewModel.expandableApplicationCount)）")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 5)
    }

    private var applicationGrids: some View {
        VStack(spacing: 0) {
            Group {
                if viewModel.isApplicationGridExpanded {
                    launchpadPage
                } else {
                    compactApplicationsGrid
                }
            }
            .frame(
                height: viewModel.isApplicationGridExpanded
                    ? ApplicationGridPresentation.expandedViewportHeight
                    : ApplicationGridPresentation.compactViewportHeight,
                alignment: .top
            )
            .clipped()
            .animation(.easeInOut(duration: ApplicationGridPresentation.expansionDuration), value: viewModel.isApplicationGridExpanded)
        }
    }
    private var compactApplicationsGrid: some View {
        applicationGrid(
            results: viewModel.compactApplicationResults,
            columnCount: ApplicationGridPresentation.collapsedColumnCount,
            spacing: 8,
            iconSize: 40,
            itemHeight: 68,
            titleFontSize: 11
        )
        .frame(height: ApplicationGridPresentation.collapsedViewportHeight, alignment: .top)
        .clipped()
    }

    private var launchpadPage: some View {
        ScrollView(.vertical, showsIndicators: true) {
            applicationGrid(
                results: viewModel.launchpadApplicationResults,
                columnCount: ApplicationGridPresentation.expandedColumnCount,
                spacing: ApplicationGridPresentation.expandedGridSpacing,
                iconSize: ApplicationGridPresentation.expandedIconSize,
                itemHeight: ApplicationGridPresentation.expandedItemHeight,
                titleFontSize: 12
            )
            .padding(.top, 8)
        }
    }

    private var searchResultPage: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                applicationGrid(
                    results: viewModel.results,
                    columnCount: MainSearchGridMetrics.columnCount,
                    spacing: 8,
                    iconSize: 40,
                    itemHeight: 68,
                    titleFontSize: 11
                )
            }
            .frame(height: searchResultViewportHeight)
            .clipped()
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                if viewModel.results.indices.contains(newIndex) {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(viewModel.results[newIndex].stableID, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func applicationGrid(
        results: [SearchResult],
        columnCount: Int,
        spacing: CGFloat,
        iconSize: CGFloat,
        itemHeight: CGFloat,
        titleFontSize: CGFloat
    ) -> some View {
        if results.isEmpty {
            if ApplicationGridPresentation.shouldShowLoadingState(
                queryIsEmpty: viewModel.query.isEmpty,
                isApplicationIndexReady: viewModel.isApplicationIndexReady
            ) {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: ApplicationGridPresentation.collapsedViewportHeight, alignment: .top)
                    .padding(.top, 24)
            } else {
                Text(L("search.noResults"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: ApplicationGridPresentation.collapsedViewportHeight, alignment: .top)
                    .padding(.top, 24)
            }
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount),
                spacing: spacing
            ) {
                ForEach(Array(results.enumerated()), id: \.element.stableID) { index, result in
                    ResultGridItem(
                        result: result,
                        isSelected: index == viewModel.selectedIndex,
                        iconSize: iconSize,
                        itemHeight: itemHeight,
                        titleFontSize: titleFontSize
                    )
                    .id(result.stableID)
                    .onTapGesture(count: 2) {
                        viewModel.selectedIndex = index
                        result.action()
                    }
                    .onTapGesture(count: 1) {
                        viewModel.selectedIndex = index
                    }
                    .contextMenu {
                        ForEach(result.actions) { action in
                            Button(action: action.action) {
                                Label(action.title, systemImage: action.icon)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }
}

/// A single result in the application grid.
struct ResultGridItem: View {
    let result: SearchResult
    let isSelected: Bool
    let iconSize: CGFloat
    let itemHeight: CGFloat
    let titleFontSize: CGFloat

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: result.displayIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)

            Text(result.title)
                .font(.system(size: titleFontSize, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: itemHeight)
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

/// NSVisualEffectView wrapper for real macOS vibrancy blur.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
