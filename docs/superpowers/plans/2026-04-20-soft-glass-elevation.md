# 柔和玻璃悬浮实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为搜索主面板、设置卡片和 JSON formatter 工作区提供分层、柔和的玻璃悬浮阴影，同时保留当前透明外观和布局。

**架构：** 新建一个只描述视觉层级参数的 `GlassElevationStyle`，将主面板与次级卡片的阴影/高光参数集中管理。`MainView` 和 `SettingsCard` 通过可复用 SwiftUI modifier 应用对应层级；窗口类继续通过既有布尔配置启用 AppKit 原生投影。测试保持在 `MainPanelLayoutTests.swift`，验证窗口投影开关和两层样式参数的相对关系，不快照或断言平台渲染结果。

**技术栈：** Swift 6、SwiftUI、AppKit、Swift Testing、Swift Package Manager。

---

## 文件结构

- 创建：`AintoApp/Sources/Views/GlassElevationStyle.swift` — 定义可测试的主面板与卡片阴影参数，以及应用多层阴影和高光边缘的 `View` modifier。
- 修改：`AintoApp/Sources/Views/MainPanelLayout.swift` — 启用主面板的 AppKit 原生窗口阴影；移除已由样式 modifier 取代的 SwiftUI 阴影开关。
- 修改：`AintoApp/Sources/Views/JSONFormatterWindowStyle.swift` — 启用无边框 JSON formatter 独立窗口的原生窗口阴影。
- 修改：`AintoApp/Sources/Views/MainView.swift` — 以主面板 elevation modifier 替代内联、由布尔开关控制的两层黑色阴影。
- 修改：`AintoApp/Sources/Views/SettingsView.swift` — 在 `SettingsCard` 表面应用次级卡片 elevation modifier。
- 修改：`AintoApp/Sources/Views/JSONEditorView.swift` — 将内嵌 JSON formatter 工作区包裹为次级浮层，避免改变原有内容、动作栏与尺寸约束。
- 修改：`AintoApp/Tests/MainPanelLayoutTests.swift` — 更新被替代的“无阴影”断言，并覆盖两类 elevation 的层级关系及两个窗口阴影开关。

## 任务 1：建立可复用的玻璃悬浮样式与测试

**文件：**
- 创建：`AintoApp/Sources/Views/GlassElevationStyle.swift`
- 修改：`AintoApp/Tests/MainPanelLayoutTests.swift`

- [ ] **步骤 1：编写失败测试，规定窗口阴影和 elevation 参数的层级关系**

在 `MainPanelLayoutTests.swift` 的现有阴影测试附近，将旧的 `searchPanelDoesNotUseWindowOrSwiftUIShadows` 测试替换为以下两个测试：

```swift
@Test func searchPanelUsesNativeWindowShadowAndMainElevation() {
    #expect(MainPanelLayout.shouldUseNativeWindowShadow)
    #expect(GlassElevationStyle.mainPanel.farShadow.radius > GlassElevationStyle.mainPanel.nearShadow.radius)
    #expect(GlassElevationStyle.mainPanel.farShadow.y > GlassElevationStyle.mainPanel.nearShadow.y)
}

@Test func cardElevationIsMoreSubtleThanMainPanelElevation() {
    #expect(GlassElevationStyle.card.farShadow.radius < GlassElevationStyle.mainPanel.farShadow.radius)
    #expect(GlassElevationStyle.card.farShadow.opacity < GlassElevationStyle.mainPanel.farShadow.opacity)
    #expect(GlassElevationStyle.card.highlightOpacity > 0)
}
```

同时在已有 `JSONFormatterWorkspaceUsesTheSameLayoutInInlineAndDetachedModes` 中将 `usesNativeWindowShadow == false` 改为 `usesNativeWindowShadow`。

- [ ] **步骤 2：运行测试验证失败**

运行：`cd AintoApp && swift test --filter MainPanelLayoutTests`

预期：编译失败，提示找不到 `GlassElevationStyle`；旧配置断言失败或在实现前仍为 `false`。

- [ ] **步骤 3：定义最小、可测试的样式模型和 modifier**

创建 `GlassElevationStyle.swift`。定义以下可比较且不依赖视图快照的参数模型，并提供 `mainPanel` 与 `card` 常量：

```swift
import SwiftUI

struct GlassElevationStyle {
    struct Shadow {
        let opacity: Double
        let radius: CGFloat
        let y: CGFloat
    }

    let nearShadow: Shadow
    let farShadow: Shadow
    let highlightOpacity: Double

    static let mainPanel = GlassElevationStyle(
        nearShadow: .init(opacity: 0.16, radius: 10, y: 3),
        farShadow: .init(opacity: 0.20, radius: 36, y: 18),
        highlightOpacity: 0.24
    )

    static let card = GlassElevationStyle(
        nearShadow: .init(opacity: 0.08, radius: 4, y: 1),
        farShadow: .init(opacity: 0.10, radius: 14, y: 6),
        highlightOpacity: 0.16
    )
}
```

在同一文件中实现一个接收 `GlassElevationStyle` 与 `RoundedRectangle` 的 `View` extension：先绘制两层 `Color.black.opacity(...)` 阴影，再叠加顶部到下部渐隐的白色高光描边。modifier 不设置 `frame`、`padding` 或 `clipShape`，以保证不改变布局占用空间。

- [ ] **步骤 4：运行测试验证通过**

运行：`cd AintoApp && swift test --filter MainPanelLayoutTests`

预期：测试编译通过；新样式层级断言通过；其余已有布局测试仍通过。

- [ ] **步骤 5：提交样式基础设施与测试**

```bash
git add AintoApp/Sources/Views/GlassElevationStyle.swift AintoApp/Tests/MainPanelLayoutTests.swift
git commit -m "feat: add glass elevation style"
```

## 任务 2：给主搜索与独立 JSON 窗口恢复悬浮深度

**文件：**
- 修改：`AintoApp/Sources/Views/MainPanelLayout.swift`
- 修改：`AintoApp/Sources/Views/JSONFormatterWindowStyle.swift`
- 修改：`AintoApp/Sources/Views/MainView.swift`
- 测试：`AintoApp/Tests/MainPanelLayoutTests.swift`

- [ ] **步骤 1：补充失败测试，锁定两种窗口原生阴影均启用**

在 `MainPanelLayoutTests.swift` 增加：

```swift
@Test func detachedJSONFormatterUsesNativeWindowShadow() {
    #expect(JSONFormatterWindowStyle.usesBorderlessWindow)
    #expect(JSONFormatterWindowStyle.usesNativeWindowShadow)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`cd AintoApp && swift test --filter MainPanelLayoutTests`

预期：`detachedJSONFormatterUsesNativeWindowShadow` 失败，因为 `usesNativeWindowShadow` 当前为 `false`。

- [ ] **步骤 3：启用原生窗口阴影并应用主面板 modifier**

1. 在 `MainPanelLayout.swift` 把 `shouldUseNativeWindowShadow` 设为 `true`，删除 `shouldUseSwiftUIShadow`（它不再是状态开关）。不修改 `contentState`、`size(for:)` 或 `shouldAnimateResize(for:)`。
2. 在 `JSONFormatterWindowStyle.swift` 把 `usesNativeWindowShadow` 设为 `true`，保留 `usesBorderlessWindow` 与 `styleMask` 计算逻辑。
3. 在 `MainView.swift` 删除现有两段 `.shadow`（它们通过 `MainPanelLayout.shouldUseSwiftUIShadow` 将 alpha 置零），在保留原有 `.clipShape` 与 gradient `.overlay` 的前提下，调用任务 1 的 modifier 并传入 `.mainPanel` 和同样的 `RoundedRectangle(cornerRadius: 16, style: .continuous)`。

确保 `SearchPanel` 的 `self.hasShadow = MainPanelLayout.shouldUseNativeWindowShadow` 保持不变，令其自然读取新配置；确认创建 detached JSON window 的代码仍使用 `JSONFormatterWindowStyle.usesNativeWindowShadow` 赋值给 `hasShadow`。

- [ ] **步骤 4：运行目标测试和完整包测试**

运行：

```bash
cd AintoApp && swift test --filter MainPanelLayoutTests
cd AintoApp && swift test
```

预期：两条命令均通过；没有尺寸、内容状态、JSON formatter 行为或窗口样式测试回归。

- [ ] **步骤 5：手动验证主面板和独立窗口**

运行：`make run`

在浅色和深色桌面背景下依次打开搜索面板与 detached JSON formatter：确认窗口外沿有柔和、向下扩散的投影，圆角处没有黑色硬边；搜索、展开应用网格和打开 JSON formatter 时，面板尺寸及交互维持原有行为。

- [ ] **步骤 6：提交窗口与主面板修改**

```bash
git add AintoApp/Sources/Views/MainPanelLayout.swift AintoApp/Sources/Views/JSONFormatterWindowStyle.swift AintoApp/Sources/Views/MainView.swift AintoApp/Tests/MainPanelLayoutTests.swift
git commit -m "feat: elevate glass panels"
```

## 任务 3：给设置卡片与内嵌 JSON 工作区增加次级浮层

**文件：**
- 修改：`AintoApp/Sources/Views/SettingsView.swift`
- 修改：`AintoApp/Sources/Views/JSONEditorView.swift`
- 测试：`AintoApp/Tests/MainPanelLayoutTests.swift`

- [ ] **步骤 1：编写失败测试，锁定次级卡片使用卡片层级配置**

在 `MainPanelLayoutTests.swift` 增加一个纯样式测试，明确次级表面拥有近、远阴影和正值高光：

```swift
@Test func cardElevationIncludesTwoShadowsAndHighlight() {
    #expect(GlassElevationStyle.card.nearShadow.opacity > 0)
    #expect(GlassElevationStyle.card.farShadow.opacity > 0)
    #expect(GlassElevationStyle.card.highlightOpacity > 0)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`cd AintoApp && swift test --filter MainPanelLayoutTests/cardElevationIncludesTwoShadowsAndHighlight`

预期：若任务 1 尚未合并，因 `GlassElevationStyle` 不存在而编译失败；若任务 1 已完成，该测试通过，可继续以视觉实现作为本任务的验证重点。

- [ ] **步骤 3：将 card elevation 应用于两个内部表面**

1. 在 `SettingsView.swift` 的 `SettingsCard.body` 中保留 `.padding(16)`、`.background(.regularMaterial)`、圆角裁剪和既有 `strokeBorder`；在这些现有装饰之后应用任务 1 的 modifier，传入 `.card` 及 `RoundedRectangle(cornerRadius: 10, style: .continuous)`。不要修改 `SettingsCard` 的泛型 API 或其调用点。
2. 在 `JSONEditorView.swift` 的 `JSONFormatterView.body` 中，将现有 `VStack` 的完整工作区表面应用同一个 `.card` modifier；使用与 JSON formatter 当前外观一致的连续圆角形状，并补上与形状一致的裁剪/轻量 material 背景（仅当当前容器没有独立表面时）。保持 `frame(maxWidth: .infinity)`、各 `Divider`、错误消息和所有按钮的顺序不变。
3. 避免对单个列表项、输入框或按钮重复添加阴影；本任务只抬升完整设置卡片和完整 JSON formatter 工作区。

- [ ] **步骤 4：运行测试验证通过**

运行：

```bash
cd AintoApp && swift test --filter MainPanelLayoutTests
cd AintoApp && swift test
```

预期：全部通过，且没有 SwiftUI 类型推断或访问控制错误。

- [ ] **步骤 5：手动验证卡片层次不抢占主面板焦点**

运行：`make run`

打开设置页中的多个 `SettingsCard`，再在搜索面板内展开 JSON formatter。确认卡片有轻微近/远阴影和顶部高光，但其阴影半径、偏移和暗度均明显低于主窗口；滚动、点击和文本输入正常，阴影不改变控件布局或裁剪内容。

- [ ] **步骤 6：提交内部卡片修改**

```bash
git add AintoApp/Sources/Views/SettingsView.swift AintoApp/Sources/Views/JSONEditorView.swift AintoApp/Tests/MainPanelLayoutTests.swift
git commit -m "feat: add elevated glass cards"
```

## 最终验证

- [ ] **步骤 1：检查变更范围和提交状态**

运行：`git status --short && git diff --check HEAD~3..HEAD`

预期：不出现空白错误；仅包含设计范围内的 Swift 文件、测试和计划产生的提交。

- [ ] **步骤 2：执行完整测试套件**

运行：`cd AintoApp && swift test`

预期：全部测试通过。

- [ ] **步骤 3：完成视觉验收**

运行：`make run`

依次验证主搜索面板、展开的应用网格、内嵌 JSON formatter、独立 JSON formatter 窗口以及设置页面的卡片。确认透明和圆角保持，主窗口投影比卡片明显，卡片的高光和阴影均柔和且无硬黑边。