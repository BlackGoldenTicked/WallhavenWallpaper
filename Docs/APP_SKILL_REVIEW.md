# 从 10 组 Apple App 开发 Skill 中筛选最佳实践

本文基于用户给出的 Skill 列表与相关文章，实际读取了可访问仓库中的 `SKILL.md`、README 和核心 references，并把适合当前 `WallhavenWallpaper` macOS SwiftUI 项目的实践落到了代码里。

## 结论

最值得安装和长期使用的是 Dimillian/Skills 与 vabole/apple-skills。前者更像一套可执行的工程工作流，尤其适合 SwiftUI 性能、UI 模式、Swift 并发和 SwiftPM macOS 打包；后者覆盖面广，适合当作 Apple 平台能力索引。App Store Review Skill 很适合上架前做最后检查，但不适合作为日常编码主 Skill。

本项目采用的最佳实践：

- SwiftUI 性能：本地图片不再在 `body` 中同步 `NSImage(contentsOf:)` 解码，改为后台降采样加载。
- macOS 原生体验：使用 inspector、Quick Look、Finder 定位、多屏壁纸设置、Settings 场景。
- 安全：Wallhaven API Key 保存到 Keychain，不再长期放在 `UserDefaults`。
- SwiftData：保持 `WallpaperItem` 单一模型，避免无必要关系和复杂迁移。
- Swift 并发：网络和图片处理保持 async/await，UI 更新留在主线程视图生命周期。
- SwiftPM macOS 打包：新增 `Scripts/package_app.sh`，能生成 `.app` 包并做 ad-hoc 签名。

## Skill 评分

| Skill / 仓库 | 评分 | 适合场景 | 评价 |
| --- | ---: | --- | --- |
| Dimillian/Skills - `swiftui-performance-audit` | 9.5 | SwiftUI 卡顿、滚动、图片内存、重复渲染 | 最适合当前项目。规则明确，能直接定位“图片解码在 body 中”这类问题。 |
| Dimillian/Skills - `swiftui-ui-patterns` | 9.0 | SwiftUI 页面结构、SplitView、Settings、组件拆分 | 实用、克制，强调小视图和原生 SwiftUI 数据流。 |
| Dimillian/Skills - `swift-concurrency-expert` | 8.8 | Swift 6 并发诊断、Sendable、MainActor | 对修 Swift 6 编译警告很有帮助，但需要结合具体错误使用。 |
| Dimillian/Skills - `macos-spm-app-packaging` | 8.8 | 无 Xcode 项目的 macOS SwiftPM 打包 | 对本项目非常贴切。脚本化 `.app`、签名、notarization 路线清楚。 |
| vabole/apple-skills - `swiftdata` / `guide-swiftdata` | 8.5 | SwiftData API 查询和模式检查 | 覆盖全面，适合查规则。当前项目模型简单，收益主要是避免过度建模。 |
| devsemih/appstore-review-skill | 8.2 | 上架前审核、隐私、权限、元数据检查 | 很适合发布前跑一遍；日常开发时偏重审核清单。 |
| hmohamed01/swift-development | 8.0 | SwiftPM、构建、测试、CI、Xcode 命令 | 范围广，像工程手册。对命令行构建有帮助，但不如 Dimillian 的单点 Skill 锋利。 |
| Jonnycatx/apple-full-stack-genius-skill | 7.5 | 全栈 Apple App、Vapor、设计、部署 | 覆盖很广，灵感多；对当前纯 macOS 壁纸 App 来说有些重。 |
| 2dubu/liquid-glass | 7.0 | iOS 26 视觉实验 | 有设计价值，但当前是 macOS 工具型 App，暂不采用。 |
| mwd1234/ios-agentic-skills | 6.8 | iOS agentic 工作流集合 | 仓库内容较集合化，本项目直接收益有限。 |
| conorluddy/ios-simulator-skill | 未评分 | iOS Simulator 自动化 | 本次浅克隆失败；且当前项目是 macOS App，不作为采用对象。 |

## 为什么这些 Skill 更好

好的开发 Skill 有三个特征：第一，能映射到具体代码问题；第二，有验证步骤；第三，不鼓励为了“架构感”增加实体。Dimillian 的 SwiftUI 性能 Skill 明确列出高优先级代码味道，例如在 `body` 中做图片解码、排序、过滤、复杂计算；这类规则能直接在项目里落地。

vabole/apple-skills 的优势是覆盖 Apple 平台完整能力，像一个分主题索引。它适合在需要 SwiftData、Swift Testing、StoreKit、WidgetKit 等具体领域时再打开对应 Skill，而不是一次性全用。

App Store Review Skill 的价值在发布前。当前 App 会下载并展示 Wallhaven 图片，尤其支持 NSFW 开关，因此上架时要注意年龄分级、NSFW 默认关闭、隐私说明、网络内容来源说明和版权边界。这个 Skill 能把这些风险变成检查清单。

## 本项目已完成的最佳实践改造

### 1. 图片性能

原先本地图库直接在 SwiftUI `body` 中读取 `NSImage(contentsOf:)`。这会在滚动和重绘时触发主线程 I/O 与解码。现在新增 `LocalImageLoader`，使用 ImageIO 在后台生成缩略图，降低主线程压力和内存峰值。

### 2. Keychain

API Key 属于敏感信息。当前项目新增 `KeychainStore`，用户点击钥匙按钮后写入 Keychain；启动时从 Keychain 读取。筛选项和保存目录继续用 `@AppStorage`，因为它们不是敏感数据。

### 3. macOS 原生交互

右侧详情使用 `.inspector()`，符合 macOS 工具类 App 的主视图 + 检查器模式。本地图片支持 Quick Look、Finder 定位、拖拽文件 URL；壁纸设置支持当前屏幕和全部屏幕。

### 4. SwiftPM 打包

新增 `Scripts/package_app.sh`，用于把 SwiftPM executable 包成 `.app`。这比只提供 `swift run` 更接近真实 macOS App 交付方式。后续发布时可以继续接入 Developer ID 签名和 notarization。

## 后续建议

- 发布前补 `PrivacyInfo.xcprivacy` 与正式 bundle id。
- 如果要上 App Store，NSFW 功能需要非常谨慎：默认关闭、明确年龄分级、说明内容来自 Wallhaven。
- 给下载和搜索逻辑补 Swift Testing，重点测 URL 参数构造、分组路径和重复下载跳过。
- 若要正式分发，扩展打包脚本加入 Developer ID 签名、notarytool 和 zip 输出。
