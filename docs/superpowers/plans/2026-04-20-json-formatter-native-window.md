# JSON 格式化工具原生可缩放窗口实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 让分离后的 JSON 格式化工具使用 macOS 原生标题栏，并可通过四边和四角调整窗口尺寸。

**架构：** 窗口创建流程继续由 `SearchPanel.openJSONFormatterWindow()` 负责，且维持原有初始尺寸与最小尺寸。将 `JSONFormatterWindowStyle` 固定为标准 AppKit 可缩放窗口样式；用单元测试锁定样式掩码，避免重新引入无边框窗口。

**技术栈：** Swift、SwiftUI、AppKit、XCTest、Swift Package Manager。

---

## 文件结构

- 修改：`AintoApp/Sources/Views/JSONFormatterWindowStyle.swift` — 定义 JSON 独立窗口的原生 AppKit 样式掩码。
- 修改：`AintoApp/Tests/JSONFormatterCoreTests.swift` — 为窗口样式掩码新增回归测试，沿用现有测试 target。
- 不修改：`AintoApp/Sources/Views/SearchPanel.swift` — 保留它已有的 `900 × 760` 初始尺寸、`800 × 600` 最小尺寸与窗口创建逻辑。

### 任务 1：锁定原生可缩放窗口样式

**文件：**
- 修改：`AintoApp/Tests/JSONFormatterCoreTests.swift`
- 修改：`AintoApp/Sources/Views/JSONFormatterWindowStyle.swift`

- [ ] **步骤 1：在 `JSONFormatterCoreTests.swift` 添加失败的样式掩码测试**

在测试文件末尾的现有 `XCTestCase` 中添加：

```swift
func testJSONFormatterWindowUsesNativeResizableStyle() {
    let style = JSONFormatterWindowStyle.styleMask

    XCTAssertTrue(style.contains(.titled))
    XCTAssertTrue(style.contains(.closable))
    XCTAssertTrue(style.contains(.miniaturizable))
    XCTAssertTrue(style.contains(.resizable))
    XCTAssertFalse(style.contains(.borderless))
}
```

- [ ] **步骤 2：运行测试，确认因 `.borderless` 而失败**

运行：

```bash
swift test --package-path AintoApp --filter JSONFormatterCoreTests/testJSONFormatterWindowUsesNativeResizableStyle
```

预期：FAIL，`XCTAssertFalse` 报告样式仍包含 `.borderless`。

- [ ] **步骤 3：以最少代码固定原生窗口样式**

将 `JSONFormatterWindowStyle` 改为以下实现，移除 `usesBorderlessWindow` 分支，确保样式不会回退为无边框：

```swift
import AppKit

enum JSONFormatterWindowStyle {
    static let usesNativeWindowShadow = true

    static let styleMask: NSWindow.StyleMask = [
        .titled,
        .closable,
        .miniaturizable,
        .resizable
    ]
}
```

- [ ] **步骤 4：运行目标测试，确认修复通过**

运行：

```bash
swift test --package-path AintoApp --filter JSONFormatterCoreTests/testJSONFormatterWindowUsesNativeResizableStyle
```

预期：PASS。

- [ ] **步骤 5：运行完整测试套件**

运行：

```bash
swift test --package-path AintoApp
```

预期：所有测试 PASS。

### 任务 2：构建并进行运行时验收

**文件：**
- 修改：无
- 测试：`AintoApp/Tests/JSONFormatterCoreTests.swift`

- [ ] **步骤 1：构建 debug 版本**

运行：

```bash
swift build --package-path AintoApp
```

预期：构建成功，无编译错误。

- [ ] **步骤 2：启动 debug 应用**

运行：

```bash
open -a "$(pwd)/AintoApp/.build/debug/AintoApp"
```

预期：应用启动。

- [ ] **步骤 3：手动验证独立 JSON 窗口**

在应用中打开 JSON 格式化工具，点击“在窗口中打开”按钮。确认：

1. 出现 macOS 原生标题栏，带关闭和最小化控制按钮。
2. 可拖动窗口左、右、上、下边缘及四个角调整尺寸。
3. 窗口无法缩小到 `800 × 600` 以下。
4. JSON 格式化、压缩、复制、筛选、嵌回主面板和关闭操作仍可使用。

- [ ] **步骤 4：检查最终差异**

运行：

```bash
git diff -- AintoApp/Sources/Views/JSONFormatterWindowStyle.swift AintoApp/Tests/JSONFormatterCoreTests.swift
```

预期：仅包含窗口样式改动和对应回归测试。

## 计划自检

- 规格覆盖度：任务 1 覆盖标准标题栏、可缩放样式及无 `.borderless`；任务 2 覆盖初始/最小尺寸不变和全部用户可见验收项。
- 占位符扫描：无 TODO、待定或未定义的后续工作。
- 类型一致性：测试和实现均使用现有 `JSONFormatterWindowStyle.styleMask`，无需引入新类型或接口。
