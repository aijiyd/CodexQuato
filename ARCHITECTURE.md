# Codex 额度监控（CodexQuota）架构说明

## 调用关系

```text
AppMain
  └─ AppController
      ├─ CodexLifecycleMonitor ──监听──> com.openai.codex
      ├─ CodexBinaryLocator ──定位──> Codex.app/Contents/Resources/codex
      ├─ CodexRateLimitClient ──JSON-RPC──> codex app-server --stdio
      │   └─ RateLimitParser ──产出──> QuotaSnapshot + RateLimitResetCredit
      └─ StatusItemController ──绘制──> macOS 状态栏
          └─ QuotaPopoverViewController ──展示──> 时间与设置面板
```

## 文件职责

| 文件 | 职责 |
|---|---|
| `Package.swift` | 定义 Core、应用和测试三个 Swift target。 |
| `Sources/CodexQuotaCore/QuotaModels.swift` | 定义通用额度窗口、双额度快照、重置卡、显示状态、刷新频率、颜色、短条和 Codex 识别规则。 |
| `Sources/CodexQuotaCore/RateLimitParser.swift` | 解析 `account/rateLimits/read` 响应，按时长提取可选5小时额度、必需周额度及可用重置卡。 |
| `Sources/CodexQuotaCore/CodexRateLimitClient.swift` | 管理长期 app-server 子进程、请求编号、超时和断线清理。 |
| `Sources/CodexQuota/AppMain.swift` | 创建无 Dock 图标的 AppKit 应用和主控制器。 |
| `Sources/CodexQuota/AppController.swift` | 串联生命周期、可配置定时刷新、客户端重连和状态栏更新。 |
| `Sources/CodexQuota/AppSettings.swift` | 使用 UserDefaults 保存刷新频率。 |
| `Sources/CodexQuota/CodexLifecycleMonitor.swift` | 监听 Codex 应用启动和退出，并过滤无关应用。 |
| `Sources/CodexQuota/CodexBinaryLocator.swift` | 根据 Codex bundle id 动态定位内置程序。 |
| `Sources/CodexQuota/StatusItemController.swift` | 5小时额度可用时绘制上下双行状态栏图，否则绘制单行周额度，并控制详情面板关闭。 |
| `Sources/CodexQuota/QuotaPopoverViewController.swift` | 显示双额度、重置卡、原生刷新频率菜单和操作，并按可见内容计算面板高度。 |
| `Sources/CodexQuota/LoginItemRegistrar.swift` | 首次启动时默认注册登录项，并处理系统批准。 |
| `Resources/Info.plist` | 定义 bundle id、最低系统版本和 `LSUIElement`。 |
| `Resources/AppIconSource.svg` / `AppIcon.icns` | 保存白底环形额度表图标设计稿与打包资源。 |
| `Scripts/render_app_icon.swift` | 在透明画布上确定性绘制图标 PNG，避免转换工具填白四角。 |
| `Scripts/package_app.sh` | Release 构建、组装 `.app`、临时签名、校验和压缩。 |
| `Scripts/package_preview.sh` | 构建独立 bundle id 的预览应用，不覆盖正式 ZIP。 |
| `Scripts/package_dmg.sh` | 生成带应用拖拽入口的HFS磁盘映像，并完成SHA-256校验。 |
| `.github/workflows/release.yml` | 收到版本标签后，在GitHub的macOS构建机上测试、打包并发布DMG。 |
| `Tests/CodexQuotaCoreTests/RateLimitParserTests.swift` | 验证双额度解析、可选5小时窗口和所有明确失败分支。 |
| `Tests/CodexQuotaCoreTests/QuotaPresentationTests.swift` | 验证颜色、短条和应用识别边界。 |
| `Tests/CodexQuotaCoreTests/CodexRateLimitClientTests.swift` | 用本地测试进程验证初始化、读取、超时、退出、重连和可选真实冒烟测试。 |

## 关键决定

- 只使用 Codex 内置 app-server，不直接读取 token，避免复制登录逻辑。
- 周额度必须精确匹配10080分钟；5小时额度只匹配300分钟，完全缺失时允许隐藏，存在但冲突或非法时显示失败。
- 子进程长连接只在 Codex 运行期间存在，8秒超时后立即终止。
- 失败状态不保留旧百分比，避免把过期额度误认为当前额度。
- 后台应用一直运行以感知 Codex 再次启动；状态栏入口按 Codex 生命周期显隐。
- 刷新频率只允许九个明确值，使用整行入口打开原生菜单，修改后立即保存并重建定时器。
- 状态栏不增加5小时或周额度文字标签；有5小时额度时固定上行显示5小时、下行显示周额度，缺失时回退原单行周额度。
- 时间信息放入点击面板，不依赖响应较慢的系统悬浮提示。
- 重置卡只接受 `status=available` 且 `resetType=codexRateLimits` 的记录；声明数量与实际记录不一致时直接报错。
- 面板高度由 Auto Layout 的实际内容高度计算，零张卡不保留卡片行，有几张卡就增加几行。
- 登录启动不再提供应用内开关；正式应用每次启动都会检查并自动注册，用户仍可通过 macOS 系统设置管理。
