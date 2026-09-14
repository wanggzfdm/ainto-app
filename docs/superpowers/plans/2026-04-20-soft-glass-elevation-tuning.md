# 柔和玻璃悬浮强度调校实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 提升主面板与内部卡片的冷灰悬浮阴影可见度，同时确保卡片视觉权重始终低于主面板。

**架构：** 仅调整 `GlassElevationStyle` 的现有参数，保留 `RGBColor`、冷灰颜色、高光和 modifier 实现。测试增加对调校后绝对阈值与主/卡片相对层级的断言；不修改窗口、SwiftUI 视图结构或布局逻辑。

**技术栈：** Swift、SwiftUI、Swift Testing、Swift Package Manager。

---

## 文件结构

- 修改：`AintoApp/Sources/Views/GlassElevationStyle.swift` — 调高主面板和卡片的近/远阴影 opacity、radius、y 参数。
- 修改：`AintoApp/Tests/MainPanelLayoutTests.swift` — 覆盖调校后的可见度阈值及卡片低于主面板的约束。

### 任务 1：调校共享 elevation 参数并验证

**文件：**
- 修改：`AintoApp/Sources/Views/GlassElevationStyle.swift:24-36`
- 修改：`AintoApp/Tests/MainPanelLayoutTests.swift`

- [ ] **步骤 1：编写失败测试，锁定“明显但克制”的数值关系**

在 `MainPanelLayoutTests.swift` 增加：

```swift
@Test func tunedElevationKeepsCardsSubtleButClearlyVisible() {
    #expect(GlassElevationStyle.mainPanel.nearShadow.opacity >= 0.22)
    #expect(GlassElevationStyle.mainPanel.farShadow.opacity >= 0.28)
    #expect(GlassElevationStyle.mainPanel.farShadow.radius >= 44)
    #expect(GlassElevationStyle.mainPanel.farShadow.y >= 22)
    #expect(GlassElevationStyle.card.farShadow.opacity >= 0.14)
    #expect(GlassElevationStyle.card.farShadow.opacity < GlassElevationStyle.mainPanel.farShadow.opacity)
    #expect(GlassElevationStyle.card.farShadow.radius < GlassElevationStyle.mainPanel.farShadow.radius)
    #expect(GlassElevationStyle.card.farShadow.y < GlassElevationStyle.mainPanel.farShadow.y)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`cd AintoApp && swift test --filter MainPanelLayoutTests`

预期：新增测试失败，因为当前 opacity、远层半径与下移距离低于阈值。

- [ ] **步骤 3：仅调高现有样式参数**

在 `GlassElevationStyle.swift` 中更新为以下精确参数：

```swift
static let mainPanel = GlassElevationStyle(
    nearShadow: .init(opacity: 0.24, radius: 12, y: 4),
    farShadow: .init(opacity: 0.30, radius: 48, y: 24),
    highlightOpacity: 0.24
)

static let card = GlassElevationStyle(
    nearShadow: .init(opacity: 0.12, radius: 5, y: 2),
    farShadow: .init(opacity: 0.16, radius: 18, y: 8),
    highlightOpacity: 0.16
)
```

不修改 `coolGrayShadow`、`RGBColor`、`glassElevation` modifier、任何 SwiftUI view 或窗口配置。

- [ ] **步骤 4：运行自动化验证**

运行：

```bash
cd AintoApp && swift test --filter MainPanelLayoutTests
swift build --package-path AintoApp
```

预期：目标测试全部通过；debug 构建成功。

- [ ] **步骤 5：启动 debug App 并手动验收**

运行：

```bash
open -a "$(pwd)/AintoApp/.build/debug/AintoApp"
```

在当前桌面背景下打开主搜索面板、设置页与内嵌 JSON formatter；确认主面板有明显悬浮层，卡片也可见但更弱，且无黑边、脏边、布局或交互变化。

- [ ] **步骤 6：检查差异**

运行：`git diff --check`

预期：无空白错误。