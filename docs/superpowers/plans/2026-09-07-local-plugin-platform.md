# Ainto 本地插件平台实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 在 Ainto 中提供纯本地的插件中心，支持目录/ZIP 导入、主窗口内 Web UI 插件运行、权限控制、有限 ZTools/uTools UI 插件兼容和开发目录重新加载。

**架构：** Swift 层新增独立的插件域模型、注册表、安装器、权限存储与 WebKit Host；`SearchViewModel` 只消费已启用插件的 feature 搜索结果，Rust 核心不处理插件。所有 Web → Native 调用经由版本化 JSON Bridge 和 `PluginAPIBroker` 验证后再执行，第三方 Node/Electron preload 永不执行。

**技术栈：** Swift 6、SwiftUI、AppKit、WebKit、Foundation/JSON、Swift Package Manager、XCTest、Rust（仅现有回归测试）。

---

## 全局约束

- 插件必须仅从本机目录或 ZIP 导入；不引入市场后端、网络下载或账号系统。
- 已安装插件复制至 `~/Library/Application Support/Ainto/Plugins/installed/<plugin-id>/`；开发插件只保存原目录引用，移除开发引用绝不删除源目录。
- 清单使用 `plugin.json`，并支持可选 `ainto.permissions`、`ainto.networkDomains`、`ainto.minimumHostVersion`、`ainto.compatibility`。
- 一期仅支持带 Web UI 的插件；不实现无界面、常驻、定时或剪贴板监听插件。
- 不执行第三方 `preload.js`；检测到 `require(`、`process.`、`electron` 或 Node 原生依赖时标记“需要适配”并禁止启用。
- `WKWebView` 不获得任意本地文件、shell、Node/Electron 或任意 JavaScript 执行能力。
- Native API 必须同时满足“manifest 已声明 + 用户已授权”；未声明调用直接拒绝。
- 网络仅允许 HTTPS，并且 host 必须精确命中已授权插件的 `networkDomains`。
- 每个插件的私有数据只能位于 `data/<plugin-id>/`。
- 所有新增用户文案必须写入 `LocalizationManager` 的中英文键值表。
- 每个生产逻辑变更遵循 TDD：先添加失败测试、确认失败、最小实现、确认通过。
- 不修改 Rust 插件接口或现有 Rust 搜索逻辑；最后执行 `cd ainto-core && cargo test` 回归。
- 不提交、推送、重置或覆盖工作区内与本计划无关的已有改动。

## 文件结构

### 新增

- `AintoApp/Sources/Plugins/PluginModels.swift`：manifest、feature、权限、来源、注册记录、兼容状态、Bridge 请求/响应等纯数据模型。
- `AintoApp/Sources/Plugins/PluginManifestParser.swift`：读取和校验 `plugin.json`、相对路径、权限与预加载兼容状态。
- `AintoApp/Sources/Plugins/PluginPaths.swift`：应用支持目录、插件/数据/日志路径和根目录逃逸防护。
- `AintoApp/Sources/Plugins/PluginRegistry.swift`：注册表加载、持久化、扫描、启用/禁用、开发目录失效处理。
- `AintoApp/Sources/Plugins/PluginInstaller.swift`：目录和 ZIP 导入、复制/解压、冲突处理、卸载语义。
- `AintoApp/Sources/Plugins/PluginPermissionStore.swift`：声明权限、已授权权限、撤销和权限查询。
- `AintoApp/Sources/Plugins/PluginSearchProvider.swift`：将已启用 feature 映射为搜索结果候选。
- `AintoApp/Sources/Plugins/PluginLogStore.swift`：按插件追加结构化且脱敏的加载/拒绝/桥接日志。
- `AintoApp/Sources/Plugins/PluginBridge.swift`：Bridge JSON schema、Web 注入脚本和请求验证。
- `AintoApp/Sources/Plugins/PluginAPIBroker.swift`：权限检查和受限 native API 分发。
- `AintoApp/Sources/Plugins/PluginHostView.swift`：`WKWebView` 的 SwiftUI 封装、导航限制、生命周期与 Esc 返回。
- `AintoApp/Sources/Plugins/PluginCenterView.swift`：本地插件、导入、已安装、开发者模式、权限管理 UI。
- `AintoApp/Tests/PluginManifestParserTests.swift`：manifest 与兼容检测单元测试。
- `AintoApp/Tests/PluginRegistryTests.swift`：注册表、启用状态、开发路径和持久化测试。
- `AintoApp/Tests/PluginInstallerTests.swift`：目录/ZIP 导入和卸载语义测试。
- `AintoApp/Tests/PluginPermissionStoreTests.swift`：权限授予、拒绝、撤销测试。
- `AintoApp/Tests/PluginSearchProviderTests.swift`：feature 搜索结果与禁用过滤测试。
- `AintoApp/Tests/PluginBridgeTests.swift`：Bridge schema、跨插件访问与权限拒绝测试。
- `AintoApp/Tests/Fixtures/Plugins/valid-color-tool/`：可运行纯 Web 插件 fixture。
- `AintoApp/Tests/Fixtures/Plugins/node-preload/`：含 Node preload 的不兼容 fixture。
- `AintoApp/Tests/Fixtures/Plugins/invalid-entry/`：入口逃逸/不存在 fixture。

### 修改

- `AintoApp/Package.swift`：为生产 target 链接 `WebKit`；确认 Tests 可访问插件域类型。
- `AintoApp/Sources/App/LocalizationManager.swift`：增加插件中心、权限、导入/错误状态的中英文文案。
- `AintoApp/Sources/App/AppDelegate.swift`：拥有单例 `PluginRegistry`、在启动时加载插件、将其注入搜索与设置入口。
- `AintoApp/Sources/Bridge/SearchViewModel.swift`：组合插件 feature 搜索结果，打开/退出 `PluginHostView`，不触及 Rust 搜索 FFI。
- `AintoApp/Sources/Views/MainView.swift`：根据新的插件页面状态呈现 `PluginHostView`。
- `AintoApp/Sources/Views/SearchPanel.swift`：插件 Host 的键盘退出、受限面板尺寸和返回搜索处理。
- `AintoApp/Sources/Views/SettingsView.swift`：新增“插件 / Plugins”分区并承载 `PluginCenterView`。
- `AintoApp/Sources/Views/SharedComponents.swift`：如已有通用组件不足，仅增加插件中心需要的状态 badge / 空状态组件。

## 实施顺序

### 任务 1：建立插件模型、路径和 manifest 校验

**文件：**
- 创建：`AintoApp/Sources/Plugins/PluginModels.swift`
- 创建：`AintoApp/Sources/Plugins/PluginPaths.swift`
- 创建：`AintoApp/Sources/Plugins/PluginManifestParser.swift`
- 创建：`AintoApp/Tests/PluginManifestParserTests.swift`
- 创建：`AintoApp/Tests/Fixtures/Plugins/valid-color-tool/plugin.json`
- 创建：`AintoApp/Tests/Fixtures/Plugins/valid-color-tool/index.html`
- 创建：`AintoApp/Tests/Fixtures/Plugins/node-preload/plugin.json`
- 创建：`AintoApp/Tests/Fixtures/Plugins/node-preload/preload.js`
- 创建：`AintoApp/Tests/Fixtures/Plugins/invalid-entry/plugin.json`

- [ ] **步骤 1：编写失败的 parser 与路径安全测试**

覆盖一个有效 `plugin.json`、缺少 `name`/`version`/`main`/`features`、不存在入口、`../` 入口逃逸、未支持权限、非 HTTPS 网络域、Node/Electron preload 兼容状态。断言 `PluginManifest` 中保留 feature code/explain/cmds 与 `ainto` 权限。

- [ ] **步骤 2：运行 parser 测试，验证它因类型不存在而失败**

运行：

```bash
cd AintoApp && swift test --filter PluginManifestParserTests
```

预期：FAIL，错误指出 `PluginManifestParser` 或相关模型不存在。

- [ ] **步骤 3：实现最小模型、路径和 parser**

实现 `Codable` 模型和显式 `PluginValidationError`。`PluginPaths` 使用注入的根 URL 方便测试；调用 `standardizedFileURL` 后确认入口 URL 仍有插件根路径前缀。解析 `preload` 时只读文本进行静态检测，不加载或执行该脚本。

- [ ] **步骤 4：再次运行 parser 测试**

运行：

```bash
cd AintoApp && swift test --filter PluginManifestParserTests
```

预期：PASS；有效 Web fixture 为可运行，Node fixture 为 `needsAdaptation`，不安全入口为失败。

- [ ] **步骤 5：审阅 scope 与代码格式**

运行：

```bash
git diff --check -- AintoApp/Sources/Plugins AintoApp/Tests/PluginManifestParserTests.swift AintoApp/Tests/Fixtures/Plugins
```

预期：无空白错误；没有运行时 WebKit 或 UI 代码。

### 任务 2：注册表、权限存储和日志

**文件：**
- 创建：`AintoApp/Sources/Plugins/PluginRegistry.swift`
- 创建：`AintoApp/Sources/Plugins/PluginPermissionStore.swift`
- 创建：`AintoApp/Sources/Plugins/PluginLogStore.swift`
- 创建：`AintoApp/Tests/PluginRegistryTests.swift`
- 创建：`AintoApp/Tests/PluginPermissionStoreTests.swift`

- [ ] **步骤 1：编写失败的注册表与权限测试**

测试首次加载空注册表、添加已安装/开发注册记录、持久化恢复、启用/禁用、失效开发路径自动禁用；测试仅对已声明权限可授予、撤销后不可访问、不同插件不能共享授权。

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
cd AintoApp && swift test --filter PluginRegistryTests && swift test --filter PluginPermissionStoreTests
```

预期：FAIL，缺少 `PluginRegistry` 与 `PluginPermissionStore`。

- [ ] **步骤 3：实现 JSON 注册表与权限 store**

以原子写入方式写 `registry.json`，记录来源、根路径、启用状态、解析版本、声明权限和已授权权限。扫描开发目录时，路径不存在或 manifest 无效仅将记录禁用并存储校验结果。日志写入插件专属文件并剥除参数中的文本/文件内容。

- [ ] **步骤 4：运行测试验证通过**

运行：

```bash
cd AintoApp && swift test --filter PluginRegistryTests && swift test --filter PluginPermissionStoreTests
```

预期：PASS，开发目录源文件不被删除或修改。

- [ ] **步骤 5：执行全量 Swift 测试**

运行：

```bash
cd AintoApp && swift test
```

预期：新旧测试均通过。

### 任务 3：目录/ZIP 导入与卸载

**文件：**
- 创建：`AintoApp/Sources/Plugins/PluginInstaller.swift`
- 创建：`AintoApp/Tests/PluginInstallerTests.swift`
- 修改：`AintoApp/Sources/Plugins/PluginPaths.swift`
- 修改：`AintoApp/Sources/Plugins/PluginRegistry.swift`

- [ ] **步骤 1：编写失败的安装器测试**

测试普通目录导入复制到 `installed/<plugin-id>`、开发目录只记录引用、ZIP 导入解压后注册、重名 ID 不覆盖既有插件、卸载已安装插件删除副本和私有数据、移除开发插件保留源目录。

- [ ] **步骤 2：运行安装器测试，验证失败**

运行：

```bash
cd AintoApp && swift test --filter PluginInstallerTests
```

预期：FAIL，缺少 `PluginInstaller`。

- [ ] **步骤 3：实现安装和卸载**

对普通目录使用 `FileManager.copyItem` 到临时目录，校验后原子移动到 `installed/<plugin-id>`；ZIP 使用系统受控解压方式并限制文件数量和总解压尺寸。拒绝 ZIP 中符号链接、绝对路径与多根/无根 manifest。遇到已有同 ID 时保留现有版本并要求 UI 显式选择更新/替换。

- [ ] **步骤 4：运行安装器测试验证通过**

运行：

```bash
cd AintoApp && swift test --filter PluginInstallerTests
```

预期：PASS，所有卸载和开发目录断言通过。

- [ ] **步骤 5：运行全量 Swift 测试**

运行：

```bash
cd AintoApp && swift test
```

预期：PASS。

### 任务 4：插件 feature 搜索与启动器导航

**文件：**
- 创建：`AintoApp/Sources/Plugins/PluginSearchProvider.swift`
- 创建：`AintoApp/Tests/PluginSearchProviderTests.swift`
- 修改：`AintoApp/Sources/Bridge/SearchViewModel.swift`
- 修改：`AintoApp/Sources/App/AppDelegate.swift`
- 修改：`AintoApp/Sources/App/LocalizationManager.swift`

- [ ] **步骤 1：编写失败的搜索 provider 测试**

测试 feature 的 code、explain 和 cmds 均可匹配；禁用插件不返回结果；结果保留 plugin ID/feature code；插件中心内置命令可通过中文、英文与“插件市场”别名找到。

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
cd AintoApp && swift test --filter PluginSearchProviderTests
```

预期：FAIL，缺少 `PluginSearchProvider`。

- [ ] **步骤 3：实现 provider 并接入 SearchViewModel**

在 `AppDelegate` 启动时加载 `PluginRegistry`。`SearchViewModel` 注入 registry/provider，保持现有应用、片段、AI 命令的排序与行为不变；将插件候选按现有模糊匹配分数合并。选择 feature 时仅更新新的插件页面状态和激活上下文，尚不创建 WebView。

- [ ] **步骤 4：运行 provider 与现有搜索测试**

运行：

```bash
cd AintoApp && swift test --filter PluginSearchProviderTests && swift test
```

预期：PASS，禁用插件从结果消失，现有搜索上下文测试仍通过。

- [ ] **步骤 5：检查新增文案**

确认 `LocalizationManager` 同时增加中文和英文的插件中心、导入、开发、权限、兼容状态和错误摘要键，禁止在新插件文件硬编码用户可见英文。

### 任务 5：受限 WebKit Host 与生命周期

**文件：**
- 创建：`AintoApp/Sources/Plugins/PluginHostView.swift`
- 修改：`AintoApp/Package.swift`
- 修改：`AintoApp/Sources/Views/MainView.swift`
- 修改：`AintoApp/Sources/Views/SearchPanel.swift`
- 修改：`AintoApp/Sources/Bridge/SearchViewModel.swift`

- [ ] **步骤 1：编写失败的 Host 状态/生命周期纯逻辑测试**

将 plugin host 会话状态抽取为可测试类型。测试打开 feature 生成 enter context、Esc/显式退出生成一次 out、退出后恢复主搜索状态、尺寸请求被限制在既定最小/最大范围。

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
cd AintoApp && swift test --filter PluginHost
```

预期：FAIL，缺少 Host 会话状态或尺寸限制类型。

- [ ] **步骤 3：实现 Host 和 WebKit 限制**

在 `Package.swift` 链接 `WebKit`。使用 `NSViewRepresentable` 承载 `WKWebView`，只加载 manifest 已校验的本地入口。`WKNavigationDelegate` 取消顶级外部导航；Host 不执行第三方 preload。进入插件后注入 enter 上下文，用户 Esc 或显式返回时派发 out 并恢复 `SearchPanel` 原始尺寸。

- [ ] **步骤 4：运行 Host 测试与构建**

运行：

```bash
cd AintoApp && swift test --filter PluginHost && swift build
```

预期：测试和构建通过。

- [ ] **步骤 5：人工启动验证**

运行：

```bash
open build/Build/Products/Debug/Ainto.app
```

预期：通过 fixture 插件打开本地页面；Esc 返回启动器；外部导航不在 WebView 内打开。

### 任务 6：Bridge、权限 Broker 与兼容对象

**文件：**
- 创建：`AintoApp/Sources/Plugins/PluginBridge.swift`
- 创建：`AintoApp/Sources/Plugins/PluginAPIBroker.swift`
- 创建：`AintoApp/Tests/PluginBridgeTests.swift`
- 修改：`AintoApp/Sources/Plugins/PluginHostView.swift`
- 修改：`AintoApp/Sources/Plugins/PluginPermissionStore.swift`
- 修改：`AintoApp/Sources/App/LocalizationManager.swift`

- [ ] **步骤 1：编写失败的 Bridge/Broker 测试**

测试版本化 JSON 请求解析、未知 API 拒绝、未声明权限拒绝、已声明未授权触发授权请求状态、撤销后拒绝、跨 plugin ID 存储访问拒绝、`http` 与未列出 HTTPS 域名的网络请求拒绝。

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
cd AintoApp && swift test --filter PluginBridgeTests
```

预期：FAIL，缺少 Bridge/Broker。

- [ ] **步骤 3：实现受限 API**

注入 `window.ainto`，再将同一实现别名为受限的 `window.utools` 和 `window.ztools`。实现 `onPluginEnter`、`onPluginOut`、`outPlugin`、clipboard text、私有存储、文件选择、通知、URL/Finder、主题/语言、受限尺寸和受控 fetch。每个请求经 schema、插件会话 ID、声明权限和授权状态验证；不暴露 shell、任意本地路径读取、`evaluateJavaScript` 或 Node/Electron。

- [ ] **步骤 4：运行 Bridge 测试**

运行：

```bash
cd AintoApp && swift test --filter PluginBridgeTests
```

预期：PASS，所有越权、跨插件、未声明与未白名单请求被拒绝。

- [ ] **步骤 5：人工验证授权流程**

使用 fixture 依次请求剪贴板和存储权限。预期：首次出现插件名和权限名确认；拒绝后页面获得明确错误；撤销后下次调用重新询问。

### 任务 7：插件中心、设置入口与开发工具

**文件：**
- 创建：`AintoApp/Sources/Plugins/PluginCenterView.swift`
- 修改：`AintoApp/Sources/Views/SettingsView.swift`
- 修改：`AintoApp/Sources/Views/MainView.swift`
- 修改：`AintoApp/Sources/Bridge/SearchViewModel.swift`
- 修改：`AintoApp/Sources/Plugins/PluginRegistry.swift`
- 修改：`AintoApp/Sources/Plugins/PluginLogStore.swift`
- 修改：`AintoApp/Sources/App/LocalizationManager.swift`

- [ ] **步骤 1：编写失败的 UI-independent view-model tests**

抽取 `PluginCenterModel` 或等价纯逻辑。测试已安装/开发分组、导入校验错误显示数据、启用禁用操作、移除开发引用不删除源、撤销权限和重新加载后的状态更新。

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
cd AintoApp && swift test --filter PluginCenter
```

预期：FAIL，缺少插件中心状态模型。

- [ ] **步骤 3：实现 SwiftUI 插件中心**

在设置侧栏加入 `plugins` section 和 `puzzlepiece.extension` 图标；在启动器内置命令打开相同中心页面。实现本地插件卡片、目录/ZIP 导入按钮、开发目录添加/移除、启用/禁用、卸载、权限列表和脱敏日志。遵循现有系统材质、原生控件、简中/英文即时切换。

- [ ] **步骤 4：运行插件中心、全量 Swift 测试和构建**

运行：

```bash
cd AintoApp && swift test --filter PluginCenter && swift test && swift build
```

预期：全部 PASS，构建退出码 0。

- [ ] **步骤 5：人工端到端验证**

启动 Debug 应用，验证：

1. 设置和启动器均可进入插件中心。
2. 从 fixture 目录导入插件，确认权限并启用。
3. 搜索 feature 命令，插件在主窗口打开，Esc 返回。
4. 禁用后 feature 不再出现。
5. 删除已安装插件后副本和数据消失；移除开发引用后源码仍在。
6. Node preload fixture 显示“需要适配”，且不会执行。

### 任务 8：最终回归与安全范围检查

**文件：**
- 修改：上述实现和测试文件，仅在测试/验证发现缺陷时最小修复。

- [ ] **步骤 1：审查新增代码中的危险接口**

运行：

```bash
ffgrep --path 'AintoApp/Sources/Plugins/**/*.swift' --pattern 'Process\(|/bin/sh|NSTask|evaluateJavaScript|require\(|ipcRenderer|remote'
```

预期：不出现 shell/进程/Electron 暴露；仅允许 Host 内部受控的必要 WebKit 调用，且不接受插件提供的任意脚本文本。

- [ ] **步骤 2：运行完整验证**

运行：

```bash
git diff --check
cd AintoApp && swift test && swift build
cd ../ainto-core && cargo test
```

预期：无 diff whitespace 错误、Swift 测试全部通过、Swift 构建成功、Rust 测试全部通过。

- [ ] **步骤 3：逐项对照规格验收标准**

检查 `docs/superpowers/specs/2026-09-07-local-plugin-platform-design.md` 的所有验收项；记录任何无法自动验证的 WebKit/权限 UI 手工验证证据与已知兼容边界。
