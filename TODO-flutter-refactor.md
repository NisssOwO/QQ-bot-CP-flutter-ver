# QQ-bot-CP Flutter 重构 TODO

工作区：本地 Flutter 工程目录

目标：直接以 Flutter 作为新应用主架构，保留官方 QQ Bot + DSH/Node Runtime 作为独立后台运行层；优先完成新架构、AI 协议、主题、小组件、更新和公网 IP 能力。旧版 WebView/原生架构的历史闪退暂不作为重构前置条件，在 Flutter 版本完成后统一回归。

当前排期调整：Android 9 适配和真机验收后置，先完成正常版本功能、Android 16 验证和 Release 发布链路；Android 9 不作为当前阶段阻塞条件。

当前进度证据：P0 工程、测试、静态分析和 APK 构建已通过；P1 已完成 MethodChannel、Foreground Service、Keystore 配置链路和 Runtime Bundle 解包；总览页已提供启动步骤、当前阶段和预计耗时，最新 APK 已安装到 Android 16 真机，空配置启动拦截验证通过；冷启动页面在该设备约 6–8 秒，烟测脚本已按实际启动时延等待；真实 QQ/Node 启动仍需在应用内填写凭据后验收。

范围调整：
- 直接重构，不以修复旧版 UI 或旧版原生空指针作为启动条件。
- 旧版安装包和旧版数据只作为迁移参考，不继续扩展旧架构。
- Flutter 新版本必须从空配置、空角色卡、空会话状态开始。

## 0. 约束与验收原则

- [x] 不修改普通 QQ 客户端，不使用 NapCat、OneBot、Root 或客户端注入。
- [x] 默认 Release APK 已通过自动审计，不包含 AppID、AppSecret、API Key、会话记录或用户角色卡；模型/Base URL 保持为空配置表达式。
- [x] 所有真实凭据只保存到 Android Keystore；日志和备份不写入密钥。
- [ ] UI、日志过滤、配置读写、更新下载、JSON 解析不能阻塞 Flutter UI isolate。
- [ ] Android 9 作为最低真机验收版本；同时覆盖 Android 14/16。
- [ ] 每一阶段完成后都要有构建产物、测试记录和回滚点。

## P0：Flutter 项目基线与新架构

### P0.1 建立 Flutter 工程

- [x] 创建 Flutter Android 工程和包名 `com.shinycolors.officialbot`；APK 已通过 aapt 验证应用 ID 和启动 Activity。
- [x] 固定 Flutter、Dart、Android Gradle Plugin、Gradle、JDK 版本，并提供 `tool/check-toolchain.ps1` 校验脚本。
- [x] 建立 `lib/`、`android/`、`test/`、`tool/` 目录。`integration_test/` 尚未建立。
- [x] 配置 debug、release、arm64-v8a 构建入口；arm64 专用 Debug 使用 `tool/build-arm64-debug.ps1`。
- [x] 配置 lint 和静态检查；`dart analyze` 已通过。format、CI 尚未接入。
- [x] 添加不包含任何用户数据的空配置页面和示例模型。

### P0.2 旧版问题登记（不阻塞重构）

- [ ] 记录旧版 Android 9 闪退现象和堆栈，作为迁移回归样本。
- [ ] 不在旧版 WebView/原生代码上继续扩展功能。
- [ ] Flutter 版本完成后重新验证同一场景。
- [ ] 若 Flutter 版本仍复现，再单独建立缺陷修复任务。

### P0.3 空配置安全启动

- [x] AppID、AppSecret、API Key、模型、Base URL 默认全部为空。
- [x] 空配置时应用正常进入首页，不自动启动真实 Runtime。
- [x] UI 显示“未配置”，不显示异常堆栈代替提示。
- [x] 点击启动时给出明确缺少字段列表。
- [x] 空角色列表时显示空状态，不加载任何内置角色卡；运行包空 preset 冒烟测试通过，`/presets` 返回空列表和添加说明。

**P0 验收：** Flutter 工程可构建、可启动、可通过桥接控制后台 Runtime；无配置能进入新应用。旧版 Android 9 闪退不作为本阶段阻塞条件。

## P1：Flutter UI 与原生 Runtime 桥接

### P1.1 总体架构

- [x] Flutter 只负责 UI、状态管理、配置编辑和用户交互。
- [x] 原生 Android Foreground Service 负责启动/停止/重启 Node/DSH Runtime；当前已完成服务和进程控制骨架，真实凭据启动尚未真机验证。
- [x] 使用 MethodChannel 发送命令：`startRuntime`、`stopRuntime`、`restartRuntime`。
- [x] Flutter 桥接调用统一增加超时和 `RuntimeBridgeException` 错误码；取消与自动重试仍按具体操作补齐。
- [x] 幂等状态、配置、角色列表和 QQ 测试调用增加有限指数退避重试；保存/删除/重启不会自动重复执行。
- [x] 使用 EventChannel 推送 Runtime 阶段和 Node 输出日志；网络状态、更新进度仍未接入。
- [x] 统一定义状态模型：`stopped`、`starting`、`online`、`reconnecting`、`failed`、`stopping`。
- [ ] 所有桥接调用都提供超时、取消、错误码和重试策略。

### P1.2 页面迁移

- [x] 总览页：Runtime 状态、QQ 状态、模型状态和公网 IP 已建立；真实 QQ/模型状态尚未接入。
- [x] AI 配置页：协议、模型、Base URL、API Key 已可填写和保存；历史配置快速选择已接入。
- [x] AI 配置支持通过已保存 API Key 拉取 OpenAI-compatible `/models` 列表并下拉选择；手动输入仍可用。
- [x] AI 配置增加关闭/低/中/高思考程度，保存后通过 Runtime 环境传递。
- [x] 更新清单 URL 保存到 Android 私有配置，并随脱敏备份恢复。
- [x] AI 配置页内的 QQ 配置区：AppID、AppSecret、连接状态、测试连接。
- [x] 日志页：级别筛选、模块筛选和阶段耗时展示已接入；复制和导出尚未实现。
- [x] 角色页：角色列表、新建、编辑、系统文件导入导出、文本 JSON 导入、删除确认、设为默认和持久化保存已接入；Runtime `presets` 内置角色也支持编辑和删除。
- [x] 角色编辑页增加 ID 规则、提示词结构、保存流程和 QQ `/preset` 使用说明。
- [x] 角色保存/删除同步 Runtime `presets` 文件，应用内自定义角色可被 DSH `/preset` 直接发现；避免角色列表重复显示。
- [x] 设置页：后台运行、通知、电池优化、更新、数据清理；后台入口跳转系统设置，不强制修改系统策略。
- [x] 设置页显示版本号和构建 ABI，并提供本地 APK 更新入口；在线检查更新待实现。
- [x] 总览页提供首次启动步骤、配置入口、启动按钮、当前阶段说明和阶段预计耗时。

### P1.3 UI 线程与后台任务

- [x] UI isolate 只处理渲染和交互；耗时 Runtime 工作由原生 Service 承担。
- [ ] JSON 解析、日志筛选、配置备份、哈希计算放入 Dart isolate。
  - [x] 角色卡文本和文件导入的 JSON 解析已移到 Dart 后台 isolate，并有单元测试。
  - [x] Runtime 日志级别和模块筛选已移到 Dart 后台 isolate，并有单元测试。
  - [x] 在线更新清单的 JSON 解析已移到 Dart 后台 isolate。
- [ ] APK 下载、文件复制、签名校验放入原生后台线程。
  - [x] 本地 APK 导入的文件复制、在线/本地包 SHA-256、签名和版本校验已放入原生 IO executor；在线下载仍由 Dart HttpClient 执行。
  - [x] 已将更新包 SHA-256、签名和版本校验放入 MainActivity 的单线程 IO executor；安装器调用回到 UI 线程。
- [ ] AI 请求由 Node/DSH Runtime 负责，不在 Flutter UI 中直接请求。
- [ ] 增加主线程卡顿和长任务检测。
  - [x] Debug/Profile 构建启用 32ms 帧耗时监测，记录 build/raster 时长；Release 构建不启用调试监测。

## P2：公网 IP 展示

### P2.1 IP 查询服务

- [x] 设计公网 IP 查询接口抽象，不把服务商地址写死在 UI（`PublicIpService` 可注入 IPv4/IPv6 端点）。
- [x] 默认使用 HTTPS 查询，设置请求超时和失败回退（代码完成，真机网络场景待验收）。
- [x] 支持 IPv4 和 IPv6 分开显示（代码完成，IPv6 可用网络待验收）。
- [x] 查询失败时显示“无法获取”，不能把局域网 IP 当公网 IP（代码完成，离线场景待验收）。
- [x] 不上传 AppID、API Key、QQ 号或会话数据（查询请求不携带应用凭据）。
- [x] 仅在用户打开页面或手动刷新时查询，避免后台频繁请求。
- [x] 公网 IP 服务支持注入式查询器，并覆盖 IPv4/IPv6 成功和双端失败单元测试。

### P2.2 展示与隐私

- [x] 总览卡片显示：`公网 IPv4`、`公网 IPv6`、`最近检测时间`。
- [x] 支持复制 IP。
- [x] 提供隐藏 IP 的开关，默认显示，用户可在总览卡片切换。
- [x] 日志只记录查询成功/失败和耗时，不记录完整请求头。
- [x] 明确提示公网 IP 可能变化，不能作为设备永久标识。

**P2 验收：** Wi-Fi、移动网络、无网络、IPv6 可用和代理网络下结果正确或有明确失败状态；代码已完成，设备网络矩阵尚未全部验收。

## P3：AI 多协议和配置历史

### P3.1 协议适配层

- [x] 定义统一协议接口：模型列表、文本请求、流式响应、取消请求、错误归一化（Flutter/Runtime 契约已建立）。
- [x] 接入 OpenAI Chat Completions（DSH `relay` 路由）。
- [x] 接入 OpenAI Responses（通过 `LLM_API` 选择 wire protocol）。
- [x] 接入 Anthropic Messages（通过 `LLM_API` 选择 wire protocol）。
- [x] 保留自定义 OpenAI-compatible 接口（`openai-compatible` 映射到 DSH `openai-completions`，Base URL 可自定义）。
- [x] 每个协议提供能力声明：是否支持流式、视觉、工具调用、思考参数。
- [x] 协议错误统一转换为可读错误码。

### P3.2 配置页面

- [x] 协议类型使用下拉框，不允许手写协议名。
- [x] 模型名称默认留空，可从历史配置快速选择。
- [x] Base URL 默认留空，可保存历史但不自动填入真实地址。
- [x] API Key 默认留空，并显示“已保存/未保存”提示；AppSecret 同样显示保存状态。
- [x] 提供“测试接口”按钮，显示 DNS/网络、TLS、HTTP 状态和响应耗时（代码完成，真实服务端场景待验收）。
- [x] 配置保存前进行字段校验，避免保存无效 URL。
- [x] 删除历史配置时二次确认。

### P3.3 安全存储

- [x] AppSecret、API Key 使用 Keystore 加密。
- [x] 配置导出默认脱敏，不导出密钥（备份 JSON 只包含公开配置、主题和角色数据）。
- [x] 日志过滤 `Bearer`、`API_KEY`、`APP_SECRET`、Token、Authorization 及常见 JSON 密钥字段；Runtime 输出和复制导出分别脱敏。
- [x] 清除全部配置时明确提示凭据会被删除；卸载行为仍由 Android 系统处理。

## P4：重启流程和精准日志

### P4.1 重启阶段

- [x] `restart.begin`：记录重启开始时间和 runId。
- [x] `process.stop`：停止旧 Runtime，记录耗时和结果。
- [x] 停止/重启命令发送后立即显示 `stopping/process.stop`，不等待 Service 销毁回调才更新 UI。
- [x] `config.load`：读取公开配置和 Keystore 凭据。
- [x] `runtime.prepare`：检查 Node、profile、权限和运行目录。
- [x] `runtime.spawn`：启动 Node 子进程。
- [x] `plugin.load`：记录插件加载开始及插件输出的成功、跳过和失败原因。
- [x] `network.check`：记录当前网络可用性，并由 Runtime 输出 DNS/HTTPS 失败原因。
- [x] `qq.connect`：记录官方 QQ Bot WebSocket 连接阶段；真实握手结果仍待账号验收。
- [x] `session.restore`：记录会话目录准备，不把敏感会话内容写入日志。
- [x] `ready`：标记 Runtime 可用。
- [x] `restart.complete`：记录总耗时。
- [x] 重启启动线程带代次校验；旧重启在新重启/停止后不会继续拉起 Node 或覆盖状态。
- [x] Runtime 子进程退出监听按进程实例校验；旧进程退出不会覆盖新进程状态。

### P4.2 日志模型

- [x] 字段包含时间、级别、模块、阶段、消息、耗时、错误码、runId。
- [x] 支持 `info`、`warn`、`error` 三种级别筛选。
- [x] 支持模块筛选：Runtime、QQ、AI、网络、更新、存储（按实际事件模块过滤）。
- [x] 支持实时日志流和最近一次重启摘要。
- [x] Android 端持久化最近 500 条结构化日志，Flutter 启动时恢复并继续接收实时日志。
- [x] 保留最近 N MB 或最近 N 条日志，防止无限增长。
- [x] 旧错误在新一轮启动前清除或标记为历史错误。
- [x] 日志导出自动脱敏（复制到剪贴板）。

**P4 验收：** 用户能从日志看出“现在在做什么、已耗时多久、下一步是什么、失败在哪里”。

## P5：QQ 配置、连接和指令体验

- [x] 移除含义不明的按钮，改为“测试 QQ 连接”并展示状态。
- [x] AppID 只显示完整值；AppSecret 只显示已配置状态。
- [x] 测试连接已接入配置校验和官方网关 HTTPS 可达性；Token 获取和 WebSocket 连接待 Runtime 实际凭据验收。
- [x] QQ 在线、重连中、离线、凭据错误分别通过运行状态和日志显示；总览页显示 QQ/AI/网络状态。
- [x] 总览页提供 `/preset`、`/presets`、`/new` 指令帮助，并支持逐条复制。
- [x] 私聊和群聊会话隔离逻辑继续由 DSH Runtime 负责；官方事件、角色存储和编排器隔离冒烟测试通过。
- [x] 没有角色卡时，`/presets` 返回空列表和添加说明，不抛异常。

## P6：后台保活与网络重连

### P6.1 前台服务

- [x] 运行 Runtime 时使用 Foreground Service。
- [x] 常驻通知已建立；显示 Runtime 阶段，细分状态在总览、小组件和日志中展示。
- [x] 通知提供“打开应用”“停止 Runtime”操作。
- [x] 引导用户关闭电池优化，但不强制修改系统设置（设置页跳转系统页面）。
- [ ] 处理 Android 9、MIUI/HyperOS 的后台限制差异。

### P6.2 网络重连

- [x] 监听网络连接变化（Android ConnectivityManager，代码完成，真机断网/恢复待验收）。
- [ ] QQ WebSocket 断开后指数退避重连。
- [x] Runtime 进程在网络恢复后按 1/2/4/8/16/32/60 秒指数退避重启，并在连续失败后进入冷却。
- [x] AI 接口失败和 QQ 连接失败分开计数，并在总览页显示。
- [x] 网络恢复后立即进行一次快速重连；快速重连失败后回到指数退避。
- [x] Runtime 进程连续失败达到阈值后进入冷却状态，避免耗电和频繁请求；QQ/AI 分项阈值待 Runtime 提供独立事件。
- [x] UI 和通知显示重连次数、下一次重试时间；最近错误通过日志页和错误码显示。

## P7：应用内更新和本地更新

### P7.1 在线更新

- [x] 检查更新接口抽象化，不把 GitHub 页面作为唯一入口（公开 JSON 清单 URL）。
- [x] 获取版本号、更新说明、ABI、APK 下载地址、SHA-256。
- [x] 更新清单在下载前校验版本、ABI、HTTPS/HTTP 地址、SHA-256 格式和文件大小，并有单元测试。
- [x] 应用内显示更新说明和包大小。
- [x] 下载进度可暂停、继续、取消和重试（断点续传使用 HTTP Range）。
- [x] 下载完成后校验 SHA-256、包名、签名和版本号。
- [x] 调用 Android PackageInstaller 安装。
- [x] 无未知来源权限时显示系统设置引导。
- [x] 安装/校验失败保留下载文件和错误原因。

### P7.2 本地更新

- [x] 使用系统文件选择器选择本地 APK。
- [x] 解析 APK 元数据（代码完成，正式签名升级包待真机验收）。
- [x] 拒绝包名不匹配、签名不匹配和版本回退包。
- [x] 支持从本地存储导入更新包后安装（交由系统安装器处理）。
- [x] 更新过程使用 Android 包安装器覆盖安装，不删除应用私有数据；凭据、角色卡和会话由应用数据目录独立保存。

## P8：桌面小组件

- [x] 设计 Android AppWidget 数据模型。
- [x] 小组件显示 Runtime 阶段和状态，并展示 QQ、AI、网络细分状态及重连次数。
- [x] 支持点击小组件打开应用。
- [x] 支持系统手动刷新；定时刷新关闭以避免后台唤醒。
- [x] Runtime 状态变化后主动刷新小组件。
- [x] 小组件不直接启动 AI 请求、不直接运行 Node。
- [ ] Android 9 和 Android 14 分别验收尺寸、刷新和锁屏行为。

## P9：主题和 UI 能力迁移

- [x] 建立统一主题控制入口。
- [x] 支持深色、浅色和跟随系统。
- [x] 支持主色、卡片圆角、卡片透明度和柔和背景样式。
- [x] 支持最近主题和恢复默认。
- [x] 主题设置写入 Android 私有配置并在启动时恢复。
- [x] 主题切换不重启 Runtime。
- [x] 日志、配置、角色、更新、小组件状态使用统一设计令牌；主题扩展提供 muted/success/warning/error 语义色。
- [ ] Android 9 低性能设备禁用高成本模糊效果。

## P10：数据、迁移与恢复

- [x] 定义版本化本地数据格式（当前 schemaVersion=1）。
- [x] 配置、默认角色卡和主题分别存储；会话索引、日志仍由 Runtime 独立管理。
- [x] 导出时默认脱敏。
- [x] 导入前自动创建本地备份。
- [x] 应用私有目录保留最近 5 份自动备份，并可在设置页查看列表、恢复指定备份。
- [x] 备份恢复和清空配置会同步/清理 Runtime 自定义 `preset.*` 文件，恢复后的角色可被 `/preset` 发现。
- [x] 支持导入旧版 WebView 脱敏备份 JSON：迁移协议、模型、Base URL 和 `custom.*` 角色卡；不迁移旧凭据/AppID。
- [x] 不迁移旧版中的真实凭据，备份不包含密钥，凭据继续从 Keystore 读取。
- [x] 清除数据功能明确区分“清除日志”“清除会话”“清除全部配置”。

## P11：测试矩阵

### 真机

- [ ] Android 9 arm64：冷启动、空配置、配置保存、Runtime 启停、重启、锁屏。
- [ ] Android 9：Wi-Fi 断开/恢复、移动网络切换、DNS 失败、TLS 失败。
- [x] Android 16 arm64：最新 Debug 包已实机安装、冷启动并验证启动引导、空配置启动拦截；旧包已验证设置页、角色页、包名/ABI 和小组件 Provider 注册。真实 Runtime 启动需先填写凭据。
- [ ] MIUI/HyperOS：省电限制、自动启动、后台冻结、通知权限。

### 功能

离线 Runtime 回归脚本 `tool/test-runtime-suite.ps1` 当前 11 项全部通过；真实 QQ/AI 网络收发仍需账号和网络验收。

- [ ] 私聊文字消息。
- [ ] 群聊 @ 消息。
- [ ] `/preset`、`/presets`、`/new`。
- [ ] 多角色和空角色列表。
- [ ] OpenAI Chat Completions。
- [ ] OpenAI Responses。
- [ ] Anthropic Messages。
- [ ] 自定义 OpenAI-compatible 接口。
- [ ] AI 请求超时、取消和重试。
- [ ] 应用内在线更新。
- [ ] 本地 APK 更新。
- [ ] 公网 IPv4/IPv6 展示。
- [ ] 桌面小组件状态同步。

### 稳定性

- [ ] 连续重启 20 次。
- [ ] 锁屏运行 2 小时。
- [ ] 网络断开 10 分钟后恢复。
- [ ] 日志达到上限后自动滚动清理。
- [ ] 空配置和错误配置不闪退。
- [ ] 杀死应用后恢复前台服务和 Runtime 状态。
- [ ] 更新失败后能够恢复到旧版本运行。

## P12：发布前检查

- [x] Release APK 通过自动审计，不包含凭据、会话目录、用户角色卡或 `.env` 文件；模型/地址需在正式发布前继续人工复核。
- [x] APK 使用工作区专用正式签名；Release 构建会拒绝缺少 keystore 配置的环境，当前 Release SHA-256、包名、版本、ABI 和签名方案已记录并核验。
- [x] APK ABI、最低 Android 版本和目标版本写入 README。
- [ ] Release 页面包含更新说明、文件大小和校验值。
- [x] 最新 arm64 Debug APK 和签名 Release APK 均通过相同隐私/用户数据审计；Release SHA-256 已记录到 README。
- [x] `tool/verify-offline.ps1` 已统一执行 Flutter 测试、静态分析、11 项 Runtime 回归、角色/会话隔离和 APK 审计，当前门禁通过。
- [x] Git 历史未跟踪 Runtime 用户目录，构建目录被忽略；Release 审计通过。
- [x] README 已提供干净安装、升级安装和旧版本迁移说明。
- [x] README 已记录系统安装确认、Android 版本、厂商后台和网络依赖等已知限制。

## 阶段出口

- [ ] P0：Android 9 空配置不崩溃。
- [ ] P1：Flutter UI 能控制现有 Runtime。
- [ ] P2：公网 IP 展示可用且失败可解释。
- [ ] P3：多 AI 协议和历史配置可用。
- [ ] P4：重启和日志可观测。
- [ ] P5：QQ 配置和连接状态清晰。
- [ ] P6：锁屏、断网和恢复可用。
- [ ] P7：在线和本地更新可用。
- [ ] P8：桌面小组件可用。
- [ ] P9：主题系统完成。
- [ ] P10：迁移、备份和恢复完成。
- [ ] P11：真机矩阵通过。
- [ ] P12：干净 APK 和发布审计通过。





