# uTools 风格主界面实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将主搜索页的纵向结果列表替换为接近参考截图的 uTools 风格应用图标宫格，并提供可靠的二维键盘导航。

**架构：** 使用独立的 `GridSelectionNavigator` 纯逻辑类型计算宫格索引，供 `SearchPanel` 的键盘事件调用；`MainView` 使用固定列数的 `LazyVGrid` 和专注视觉呈现的 `ResultGridItem`。现有 `SearchViewModel` 的结果数据、排序、打开和 Action 行为保持不变。

**技术栈：** Swift 6、SwiftUI、AppKit、Swift Testing、Swift Package Manager。

---

## 文件结构

- 创建 `AintoApp/Sources/Views/GridSelectionNavigator.swift`：定义方向枚举与无 UI 依赖的二维索引计算。
- 创建 `AintoApp/Tests/GridSelectionNavigatorTests.swift`：验证水平、垂直、空数据和不完整末行边界。
- 修改 `AintoApp/Sources/Views/MainView.swift`：将结果列表改为 uTools 风格宫格，删除 footer，新增分区标题与宫格项组件。
- 修改 `AintoApp/Sources/Views/SearchPanel.swift`：在主页面应用模式下，将四个方向键映射到二维宫格导航；其他页面维持既有上下导航行为。

### 任务 1：可测试的二维宫格导航

**文件：**
- 创建：`AintoApp/Sources/Views/GridSelectionNavigator.swift`
- 创建：`AintoApp/Tests/GridSelectionNavigatorTests.swift`

- [ ] **步骤 1：编写失败的导航测试**

使用 Swift Testing 编写表驱动或独立测试，直接断言字面量结果。测试至少包含：

```swift
import Testing
@testable import AintoApp

@Test func movesHorizontallyWithinBounds() {
    #expect(GridSelectionNavigator.destination(from: 2, itemCount: 8, columnCount: 5, direction: .left) == 1)
    #expect(GridSelectionNavigator.destination(from: 2, itemCount: 8, columnCount: 5, direction: .right) == 3)
    #expect(GridSelectionNavigator.destination(from: 0, itemCount: 8, columnCount: 5, direction: .left) == 0)
    #expect(GridSelectionNavigator.destination(from: 7, itemCount: 8, columnCount: 5, direction: .right) == 7)
}

@Test func movesVerticallyByColumnCount() {
    #expect(GridSelectionNavigator.destination(from: 6, itemCount: 12, columnCount: 5, direction: .up) == 1)
    #expect(GridSelectionNavigator.destination(from: 1, itemCount: 12, columnCount: 5, direction: .down) == 6)
}

@Test func clampsVerticalMoveIntoIncompleteLastRow() {
    #expect(GridSelectionNavigator.destination(from: 4, itemCount: 8, columnCount: 5, direction: .down) == 7)
}

@Test func safelyHandlesEmptySingleAndInvalidColumnCounts() {
    #expect(GridSelectionNavigator.destination(from: 0, itemCount: 0, columnCount: 5, direction: .right) == 0)
    #expect(GridSelectionNavigator.destination(from: 0, itemCount: 1, columnCount: 5, direction: .down) == 0)
    #expect(GridSelectionNavigator.destination(from: 3, itemCount: 8, columnCount: 0, direction: .down) == 3)
}
```

这些测试分别抓住水平越界、上下跨行步长错误、末行落点越界和零值崩溃。

- [ ] **步骤 2：运行测试并确认因类型尚不存在而失败**

运行：

```bash
cd AintoApp && swift test --filter GridSelectionNavigatorTests
```

预期：编译失败，提示找不到 `GridSelectionNavigator` 或 `GridNavigationDirection`。

- [ ] **步骤 3：实现最少导航逻辑**

实现以下契约：

```swift
enum GridNavigationDirection {
    case left, right, up, down
}

enum GridSelectionNavigator {
    static func destination(
        from currentIndex: Int,
        itemCount: Int,
        columnCount: Int,
        direction: GridNavigationDirection
    ) -> Int
}
```

规则：空结果、非法列数或非法当前索引采用安全返回；左右移动夹在 `0...(itemCount - 1)`；上移减列数但不小于 0；下移加列数，若超过末尾则落到最后一个有效结果。

- [ ] **步骤 4：运行定向测试确认通过**

运行：

```bash
cd AintoApp && swift test --filter GridSelectionNavigatorTests
```

预期：上述导航测试全部通过。

### 任务 2：uTools 风格宫格和二维键盘接线

**文件：**
- 修改：`AintoApp/Sources/Views/MainView.swift`
- 修改：`AintoApp/Sources/Views/SearchPanel.swift`
- 测试：`AintoApp/Tests/GridSelectionNavigatorTests.swift`

- [ ] **步骤 1：在主视图中定义共享宫格列数**

添加应用主宫格使用的稳定列数常量，例如：

```swift
enum MainSearchGridMetrics {
    static let columnCount = 8
}
```

`MainView` 和 `SearchPanel` 必须引用同一常量，避免视觉列数与键盘跨行步长不一致。

- [ ] **步骤 2：将结果列表替换为宫格**

在 `mainSearchView` 中：

- 保留搜索输入及现有 AI 模式提示。
- 普通搜索提示文案改为“搜索应用和指令/粘贴文件或图片”。
- 在应用模式且结果非空时显示标题行：“最近使用”与“展开（\(viewModel.results.count)）”。
- 使用 `ScrollViewReader`、纵向 `ScrollView` 和 `LazyVGrid` 展示结果。
- 每个宫格项继续保留 `.id(result.id)`、单击选中、双击打开和原有 context menu。
- 选中索引变化时使用 `proxy.scrollTo(..., anchor: .center)` 保证结果可见。
- 删除整个 footer、footer Divider 和 `KeyHint` 组件。

- [ ] **步骤 3：用 `ResultGridItem` 替换 `ResultRow`**

宫格单元实现：

- 图标约 44–48pt。
- 名称位于图标下方，单行截断，居中显示。
- 单元拥有稳定高度和完整 `contentShape`。
- 选中时显示轻量 accent 背景或描边与连续圆角；未选中透明。
- 不显示 `result.subtitle`。

- [ ] **步骤 4：接入四方向导航**

在 `SearchPanel.installKeyMonitor()` 中扩展 IME 方向键保护到左右键 `123`、`124`，然后：

```swift
case 123: // Left
case 124: // Right
case 125: // Down
case 126: // Up
```

当 `page == .main && searchMode == .apps` 时，用 `GridSelectionNavigator.destination(...)` 和 `MainSearchGridMetrics.columnCount` 更新 `viewModel.selectedIndex`。其他页面或模式的上下键继续使用现有 `moveSelection(by:)`，左右键不吞掉文本编辑行为。

为避免方向键在搜索文本编辑时造成退化，应只在主页面应用结果宫格确实显示且事件被判定用于结果导航时消费左右键；如果现有交互约定要求搜索框中的左右键移动光标，则保留左右键给文本系统，仅通过上下键跨行。这一冲突必须基于当前实际行为作保守选择，并在 worker 报告中说明。

- [ ] **步骤 5：运行全部 Swift 测试**

运行：

```bash
cd AintoApp && swift test
```

预期：导航测试和现有 JSON formatter 测试全部通过，无失败。

- [ ] **步骤 6：运行 Swift 构建**

运行：

```bash
cd AintoApp && swift build
```

预期：构建退出码为 0，无 Swift 编译错误。

- [ ] **步骤 7：检查变更范围**

运行：

```bash
git diff -- AintoApp/Sources/Views/MainView.swift AintoApp/Sources/Views/SearchPanel.swift AintoApp/Sources/Views/GridSelectionNavigator.swift AintoApp/Tests/GridSelectionNavigatorTests.swift
```

确认没有修改搜索排序、数据模型、其他子页面或任务范围外文件；不要 commit、push 或 reset。
