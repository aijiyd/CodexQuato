# Codex 额度监控

Codex 额度监控（内部项目名 CodexQuota）是一个原生 macOS 状态栏工具。Codex 启动后，它自动显示周额度；Codex 退出后，状态栏入口自动隐藏。工具不抓网页、不保存账号密钥，只调用本机 Codex 自带的只读额度协议。

## 下载

从[GitHub Releases](https://github.com/aijiyd/CodexQuato/releases/latest)下载最新版DMG。打开后把`CodexQuota.app`拖入`Applications`，首次启动时右键应用并选择“打开”。

当前发布包使用临时签名，没有Apple Developer ID签名和公证，因此macOS可能显示安全提醒。

## 功能

- 只显示 Codex 周额度，可选择每1秒、5秒、10秒、15秒、30秒、1分钟、2分钟、5分钟或15分钟刷新。
- 点击状态栏入口弹出紧凑面板，显示周额度重置时间、可用重置卡数量和每张卡的过期时间；面板高度随卡片数量变化，点击面板外区域自动关闭。
- 剩余 61%–100% 为绿色，20%–60% 为橙色，0%–19% 为红色。
- 使用五个短条和精确百分比展示额度；例如 42% 显示2个橙色短条。
- Codex 退出时隐藏，重新启动时自动出现。
- 详情面板可立即刷新、退出工具和修改刷新频率。
- 首次运行注册为 macOS 登录项，无 Dock 图标；详情面板可随时开关登录启动。
- 读取失败时显示灰色 `--%` 和明确错误，不展示旧数据。

## 技术架构

项目使用 Swift 6、AppKit、ServiceManagement 和 Swift Package Manager，不依赖第三方库。

1. `CodexLifecycleMonitor` 监听 bundle id `com.openai.codex` 的启动和退出。
2. `CodexRateLimitClient` 启动 Codex 应用内置的 `codex app-server --stdio` 长连接。
3. 客户端完成初始化后调用 `account/rateLimits/read`，严格选择时长为 10080 分钟的周额度，并读取可用的 Codex 额度重置卡。
4. `StatusItemController` 绘制紧凑状态栏图像，点击后打开 `QuotaPopoverViewController` 详情面板。
5. `AppSettings` 持久化刷新频率，`SMAppService.mainApp` 管理登录时启动。

工具本身不读取 `auth.json`，也不持久化 token。身份验证和额度请求都由本机 Codex 进程完成。

## 本地构建

要求：

- macOS 13 或更高版本。
- Apple Silicon Mac。
- Swift 6 命令行工具。
- 已安装并登录 Codex 桌面应用。

```bash
swift build
swift test
```

当前机器只有 Command Line Tools，不需要安装完整 Xcode。

## 打包与安装

```bash
./Scripts/package_app.sh
```

生成文件：`outputs/CodexQuota.app.zip`。

生成DMG：

```bash
./Scripts/package_dmg.sh
```

生成文件：`outputs/CodexQuota-1.3.0.dmg`。

1. 解压 ZIP。
2. 将 `CodexQuota.app` 拖入 `/Applications`。
3. 启动一次；如果 macOS 提示需要批准登录项，按提示在系统设置中允许。

应用使用临时签名，没有Apple Developer ID和公证。

## 测试

```bash
swift test
CODEXQUOTA_LIVE_SMOKE=1 swift test --filter 'CodexQuotaCoreTests.CodexRateLimitClientTests/liveCodexSmokeTest'
plutil -lint Resources/Info.plist
codesign --verify --deep --strict /path/to/CodexQuota.app
```

自动测试覆盖周额度解析、错误数据、颜色边界、短条数量、应用识别、JSON-RPC 初始化、读取超时、子进程退出和重新连接。冒烟测试只读取本机 Codex 额度，不发起模型任务，不消耗对话额度。

预览版只写入 `preview/`，不会覆盖正式 ZIP：

```bash
./Scripts/package_preview.sh
```

## 搜索记录

| 来源 | 结论 |
|---|---|
| [skills.sh](https://www.skills.sh/) | 未发现能直接交付该专用 macOS 工具的现成 skill。 |
| [CodexBar](https://github.com/steipete/CodexBar) | 已支持 `account/rateLimits/read` 和超时终止，但面向几十种供应商，功能和设置远超本需求。参考了其本地协议和超时边界，不复制其多供应商架构。 |
| [ClaudeBar](https://github.com/tddworks/ClaudeBar) | 颜色阈值和定时刷新与本需求接近，但同样是多供应商工具，且不具备“仅在 Codex 运行时显示”的目标行为。 |
| [OpenAI Codex 使用说明](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan) | 官方产品提供额度页面，但没有面向本工具的公开额度 API；因此使用本机 Codex 随版本发布的结构化协议。 |
| [OpenAI Codex Referral Promotions](https://help.openai.com/en/articles/20001271-codex-referral-promotions) | 官方确认推广权益可能包含 Codex 额度重置及独立过期时间，但没有公开本地协议字段；字段结构以本机只读 `app-server` 响应为准。 |
| [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) | macOS 13 起可把主应用注册为登录项。 |

## 已完成与待办

已完成：紧凑状态栏 UI、动态详情面板、周额度与重置卡读取、Codex 生命周期跟随、可选刷新频率、失败显式展示、登录项开关、测试、打包和文档。

已发布：1.3.0 正式版已加入重置卡过期时间、动态面板高度和1秒/5秒/10秒刷新频率。

待办：公开分发前需要 Developer ID 签名、公证和独立版本兼容测试。

## 开源协议

本项目使用[MIT License](LICENSE)。

## 限制

- “Codex 关闭”指完全退出应用（例如 `Command + Q`），仅关闭窗口不会隐藏状态栏入口。
- 依赖 Codex 自带的实验性 app-server 协议；Codex 将来改变协议时，工具会显示错误，不会猜测或切换到网页抓取。
- 只接受 `windowDurationMins == 10080` 的周额度，不用五小时额度代替。
