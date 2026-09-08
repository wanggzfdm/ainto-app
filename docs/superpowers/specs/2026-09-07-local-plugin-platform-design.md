# Ainto 本地插件平台设计

## 目标

为 Ainto 增加一个仅在本机运行的插件平台。用户可从插件中心导入本地插件目录或 ZIP 包，在 Ainto 主窗口内运行带 Web UI 的插件，并通过权限确认机制调用有限的 macOS 原生能力。

该平台优先兼容基于 `plugin.json` 的 ZTools/uTools UI 插件：兼容其清单、功能关键词和常用 Web API；不承诺 Electron、Node.js 或任意第三方 preload 脚本兼容。

## 非目标

第一期不实现：

- 在线插件市场、账号、下载统计、远程审核或自动更新。
- 无界面插件、常驻后台插件、剪贴板监听和定时任务。
- Electron、Node.js、`require()`、`ipcRenderer`、`remote` 或 Node 原生模块。
- 任意 shell 命令执行。
- 对所有 ZTools/uTools 插件的无条件兼容承诺。

## 用户体验

### 入口

插件中心有两个入口：

1. 启动器：搜索“插件中心”“插件市场”或“Plugins”进入插件中心。
2. 设置窗口：在侧边栏增加“插件”分区，提供相同的管理能力。

启动器搜索结果还包含每个已启用插件的 `features`。用户输入某个插件声明的 `cmds` 或匹配其 `explain` 后，选择结果会在当前 Ainto 主窗口内打开插件，而不是创建独立窗口。按 `Esc` 或插件调用退出 API 后返回搜索界面。

### 插件中心

插件中心包含以下页面或筛选项：

- **本地插件**：显示已安装插件和来自开发目录的插件；展示图标、名称、版本、描述、启用状态和兼容状态。
- **导入**：支持选择 ZIP 文件或插件目录。ZIP/普通导入复制到 Ainto 管理目录；开发目录以引用方式注册。
- **已安装**：启用、禁用、查看详情、更新导入副本、卸载。
- **开发者模式**：添加或移除本地开发目录、手动重新加载、查看 manifest 校验结果与 Web/桥接调用日志。
- **权限管理**：查看每个插件已声明和已批准的权限，可撤销授权；撤销后下次调用需再次确认。

### 安装与导入

1. 用户选择 ZIP、普通目录或开发目录。
2. 系统定位并解析根目录下的 `plugin.json`。
3. 系统校验插件 ID、版本、入口文件、图标路径、`features`、声明的权限和网络域名。
4. 对 ZIP/普通目录导入，系统复制或解压到管理目录；对开发目录，仅记录原路径，不复制源码。
5. 系统展示插件详情和声明的权限，用户确认后注册插件。
6. 注册成功后，插件功能立即可被启动器搜索；插件默认启用。

校验失败时不注册插件，插件中心显示可读错误，如缺失 `plugin.json`、入口文件不存在、ZIP 含多个候选根目录、插件 ID 冲突或不受支持的 manifest 结构。

### 卸载语义

- 对已安装副本，卸载删除 `installed/<plugin-id>/` 和该插件私有数据目录，但不删除用户导入源。
- 对开发目录，移除注册引用和私有数据；绝不删除开发者原目录。
- 禁用仅从搜索与运行时卸载，不删除文件、数据或授权记录。

## 本地目录与注册表

Ainto 使用应用支持目录，而不是网络服务：

```text
~/Library/Application Support/Ainto/Plugins/
├── installed/
│   └── <plugin-id>/
├── development/
│   └── registry.json
├── data/
│   └── <plugin-id>/
├── logs/
│   └── <plugin-id>.log
└── registry.json
```

`registry.json` 保存每个注册插件的稳定 ID、来源类型（`installed` 或 `development`）、解析后的版本、根路径、启用状态、当前授权、声明权限、网络域名白名单、最后校验结果和最后加载时间。插件私有持久化数据不写入全局注册表，只位于 `data/<plugin-id>/` 下。

开发目录注册表只存稳定 ID 到规范化绝对路径的映射。每次加载前检查该目录和 manifest 是否仍存在；路径失效时自动禁用并显示“开发目录不可用”，但不删除该条记录。

## 插件包与 manifest

### 包格式

- 插件目录根目录必须包含 `plugin.json`。
- ZIP 解压后必须得到一个包含 `plugin.json` 的单一插件根目录；安装器拒绝符号链接逃逸、绝对路径条目和压缩炸弹式不合理大小/文件数。
- 入口文件、图标和前端资源必须位于插件根目录内，路径规范化后不得逃逸根目录。

### 清单兼容策略

统一采用 `plugin.json`。Ainto 读取 ZTools/uTools 常见字段：

```json
{
  "name": "color-tool",
  "version": "1.0.0",
  "description": "颜色转换工具",
  "main": "index.html",
  "preload": "preload.js",
  "features": [
    {
      "code": "color",
      "explain": "颜色工具",
      "cmds": ["color", "颜色"]
    }
  ],
  "ainto": {
    "permissions": [
      "clipboard.read",
      "clipboard.write",
      "storage",
      "notification"
    ],
    "networkDomains": []
  }
}
```

Ainto 扩展字段放在 `ainto` 下：

- `permissions`：声明的原生 API 权限。
- `networkDomains`：允许 `fetch` 访问的 HTTPS 域名精确列表。
- `minimumHostVersion`：可选的最低 Ainto 版本。
- `compatibility`：可选的作者声明，例如 `web` 或 `ztools-ui`。

`name` 作为显示名；Ainto 额外从 manifest 的稳定唯一字段或目录规范化名称推导 `plugin-id`。若 ZTools/uTools 格式存在其既有稳定插件标识，则优先使用该标识；否则安装时生成并持久化 UUID，避免仅改显示名导致数据丢失。

`preload` 仅用于兼容性检查与提示，不直接执行第三方 Node preload 脚本。发现 `require(`、`process.`、`electron`、Node 原生模块或无法解析的预加载依赖时，插件中心标为“需要适配”；用户仍可查看详情，但不能启用，除非未来增加专门支持。

## 运行时架构

### 组件边界

1. **PluginRegistry**：扫描、解析、校验、持久化和查询已注册插件。
2. **PluginInstaller**：导入目录/ZIP、处理冲突、复制或解压、卸载已安装副本。
3. **PluginPermissionStore**：维护插件声明权限与用户授权，负责撤销。
4. **PluginSearchProvider**：将启用插件的 `features` 转换为 Ainto `SearchResult`；不修改 Rust 应用索引。
5. **PluginHostView / PluginHostController**：在 Ainto 主窗口内承载一个 `WKWebView`，加载本地插件入口，管理返回、尺寸和生命周期。
6. **PluginBridge**：在 `WKUserContentController` 中注册消息处理器，向页面注入受限的 `window.utools`、`window.ztools` 和 `window.ainto` 兼容对象。
7. **PluginAPIBroker**：在主线程上逐项校验调用者插件 ID、API 名、参数类型和权限，然后调用 AppKit/系统服务。
8. **PluginLogStore**：按插件记录 manifest 校验、加载、桥接调用、拒绝权限与 Web 控制台错误；日志不含剪贴板内容、文件内容或 token。

### 生命周期

插件 Host 打开时：

1. `PluginSearchProvider` 将匹配的 feature 与当前输入上下文传给 Host。
2. Host 创建或复用对应插件的 `WKWebView`，仅允许读取其插件根目录资源。
3. Host 注入 Ainto 兼容桥接脚本和当前上下文。
4. 页面加载完成后，桥接派发 `onPluginEnter`，参数包含 feature code、搜索文本、选中文本（如当前可用）和文件路径列表（仅在用户显式选取时）。
5. 页面调用 `outPlugin` 或用户按 `Esc` 时，Host 派发 `onPluginOut`，销毁/隔离页面状态并返回主搜索界面。

插件请求页面尺寸时，Host 对宽高设定最小/最大边界，并通过现有 `SearchPanel` 尺寸逻辑更新面板，避免插件越界或无限扩张。

## 权限与安全模型

### 原则

插件默认不能读取剪贴板、访问文件、发起网络请求或调用原生系统服务。每一次原生 API 调用都必须经过 `PluginAPIBroker`，浏览器内 JavaScript 不能绕过该 Broker。

### 权限项

第一期支持：

- `clipboard.read`
- `clipboard.write`
- `storage`
- `file.open`
- `file.reveal`
- `notification`
- `url.open`
- `network`
- `theme.read`
- `language.read`

`storage` 仅访问 `data/<plugin-id>/`；不允许跨插件读取。`network` 必须同时具有已批准权限和 `networkDomains` 精确域名匹配，且仅允许 HTTPS。文件能力必须通过系统 `NSOpenPanel` / `NSSavePanel` 获得用户选择的 URL；插件不能接收任意本地路径后自行读取。

### 授权流程

- 安装/导入时：展示 manifest 已声明权限与网络域名，用户可“允许全部声明权限”或逐项拒绝。
- 运行时：插件调用未授权但已声明的 API 时，显示一次按插件、权限和用途描述的确认框。
- 未声明的 API 调用直接拒绝，记录日志，不弹出扩大权限的确认框。
- 用户可在插件中心撤销已批准权限；下次调用重新询问。

### Web 安全

- 使用 `WKWebView` 本地资源加载，禁止任意顶级导航；允许的外部链接由 `url.open` 权限显式交给系统浏览器。
- 使用内容规则或导航代理限制不在 `networkDomains` 的网络请求。
- 桥接协议使用版本化 JSON 消息，包含请求 ID、API 名和参数；Native 层验证完整 schema，绝不执行来自插件的 JavaScript 字符串或 shell 命令。
- 不暴露 `WKWebView` 的任意 `evaluateJavaScript` 命令通道给插件。
- 第三方 `preload.js`、`require()` 和 Electron 代码不执行。

## 兼容 API

Ainto 注入有限的兼容对象。实现时将所有方法映射到明确的 `PluginAPIBroker` 请求，而不是复制 Electron API：

- 生命周期：`onPluginEnter(callback)`、`onPluginOut(callback)`。
- 插件退出：`outPlugin()`。
- 剪贴板：读取和写入文本。
- 存储：插件私有 key-value 的读取、写入和删除。
- 系统：通知、打开 URL、Finder 展示经用户选择/授权的文件。
- 文件：打开文件/目录选择器。
- 窗口：请求受限尺寸、返回搜索。
- 上下文：读取进入插件时传入的搜索关键词、选中文本和已授权文件选择结果。
- 网络：经权限和域名白名单检查的 `fetch`。
- 外观：当前深浅色模式与应用语言。

兼容层同时提供 `window.utools`、`window.ztools` 和 Ainto 原生的 `window.ainto`。三者共享相同受限实现；API 文档必须标明“已支持”“需适配”“明确不支持”。

## UI 与本地化

插件中心遵循当前 Ainto 的 SwiftUI/AppKit 原生材质与系统语义色风格，支持现有简体中文和英文即时切换。所有新文案写入 `LocalizationManager` 的键值表。

新设置分区为“插件 / Plugins”，图标使用 `puzzlepiece.extension`。启动器内置命令使用“插件中心 / Plugin Center”，其搜索别名包含“插件市场 / Plugin Market / Plugins”。

## 测试策略

生产逻辑变更必须使用 TDD。测试至少覆盖：

1. manifest 正常解析、必填字段缺失、入口逃逸、重复 ID 和版本升级策略。
2. ZIP 与目录导入的成功路径、无 manifest、多个根目录、非法路径和开发目录引用语义。
3. 已安装插件卸载删除副本与数据；开发插件移除只删除注册信息。
4. 注册表的启用/禁用、持久化恢复和失效开发路径自动禁用。
5. feature 到启动器结果的映射、关键词匹配和禁用插件不出现在搜索中。
6. 权限首次确认、拒绝、撤销、未声明 API 拒绝和网络域名白名单。
7. bridge JSON schema 校验与 API 请求不能跨插件访问数据。
8. 生命周期事件顺序：加载后 enter、Esc/outPlugin 后 out、返回搜索。
9. 兼容性检查：纯 Web 插件可运行；检测到 Node/Electron preload 的插件显示“需要适配”且不执行脚本。
10. 现有 Swift 单元测试、Swift 构建和 Rust 单元测试继续通过。

WKWebView 的渲染行为以最小化的集成测试或人工启动验证补充；纯 manifest、注册、权限、搜索和桥接 schema 逻辑应保持为可独立单测的 Swift 类型。

## 分阶段交付

### 阶段 1：本地插件基础

实现目录/ZIP 导入、manifest 解析和校验、注册表、已安装/开发插件列表、启用禁用卸载、feature 搜索注册、主窗口 Plugin Host、Esc 返回、私有存储和日志框架。

### 阶段 2：权限与原生桥接

实现安装前和运行时权限确认、权限管理界面、剪贴板、文件选择、通知、URL/Finder、主题/语言、网络域名白名单，以及完整参数校验。

### 阶段 3：兼容与开发体验

实现 `window.utools` / `window.ztools` / `window.ainto` 注入、生命周期、静态 preload 兼容性检查、开发目录重新加载、桥接调用日志和兼容状态展示。

## 验收标准

- 用户可从设置和启动器打开插件中心。
- 用户可导入兼容目录与 ZIP，且可区分已安装副本和开发目录引用。
- 已启用插件 feature 可通过启动器搜索并在主窗口内打开。
- 插件仅能调用获授权且已声明的原生 API；未授权、未声明、跨插件与不在白名单的网络调用被拒绝并记录。
- 用户可启用、禁用、卸载、移除开发引用、撤销权限和重新加载开发插件。
- 检测到 Node/Electron preload 依赖时，插件不执行该代码，并向用户说明需要适配。
- 所有新增逻辑具有自动化测试；Swift/Rust 全部回归测试与构建通过。
