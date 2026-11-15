# QQ-bot-CP Flutter 重构工程

这是 QQ-bot-CP 的独立 Flutter Android 工程。Flutter 负责界面、配置、角色管理、日志、主题、更新和小组件；Android Foreground Service 负责在应用私有目录启动 DSH/Node Runtime。工程不修改普通 QQ 客户端，也不依赖 Root、NapCat 或 OneBot。

## 当前状态

- Android applicationId：`com.shinycolors.officialbot`
- 应用名称：`QQ-bot-CP`
- 最低 Android SDK：24（Android 7.0）；目标 SDK：36
- 当前验证设备：Android 16、`arm64-v8a`
- Flutter 版本：3.47.9 stable
- JDK：25（版本基线见 `tool/toolchain.json`）
- 当前版本：`0.2.24 (33)`
- Release 使用不提交到 Git 的工作区 keystore；不要删除或更换它，否则升级安装会因签名不一致失败
- 当前签名 Release APK：`192,208,321` 字节（约 183.3 MiB）；SHA-256：`bb81bbbad9cd0f062e3f7199c37609ff8a85b7b3d58d6637bd20dca4ddb9a078`；已通过 Release 隐私审计和 APK v2 签名校验
- 应用内更新：设置页固定使用官方清单 `release/manifest-arm64.json`，支持检查、下载、SHA-256 校验和交给 Android 安装器安装。该清单当前指向已发布的 `0.2.5 (14)`，升级到更新版本前需要先重新发布。
- Release 元数据：包名 `com.shinycolors.officialbot`、ABI `arm64-v8a`、最低 Android 24、目标 Android 36；APK Signature Scheme v2 验证通过

## 主要功能

- **AI 对话**：「AI」页配置接口类型、Base URL、模型和 API Key；DeepSeek 官方端点自动切换到 OpenAI 兼容路径并锁定「思考程度」。
- **联网搜索**：Base URL 指向 `deepseek.com` 时，运行时会给每轮请求追加 DeepSeek 服务端搜索工具 `deepseek_web_search`，模型自己决定是否搜索、并带引用作答；Flutter 端无需配置，默认跟随 Base URL 自动启用（配置项 `webSearch`，暂未暴露到界面）。**代价**：普通搜索模式下客户端 function 工具不能与服务端搜索共存，运行时会把它们从请求里剔除（日志会打印被省略的工具名）。
- **主动回复**：本地规则先抽样、命中才调模型；全部参数在「主动回复」页可调，支持全局默认与单群覆盖，默认关闭。
- **网关观测**：「总览」页显示网关在线/心跳/重连次数/错误码；「网关事件」页展示只追加不覆盖的 `gateway-events.jsonl`，断开时会区分服务端关闭帧与本地判定。
- **日志**：保留最近 2000 条，重启不清空最后错误，「日志」页可按级别/模块/关键字筛选并导出。

## 构建

```powershell
$env:JAVA_HOME = '<Android Studio 的 jbr 目录>'
$env:Path = "$env:JAVA_HOME\bin;<Flutter SDK 的 bin 目录>;$env:Path"
flutter pub get
dart analyze
flutter test
flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons
powershell -ExecutionPolicy Bypass -File .\tool\audit-release.ps1 -Apk .\build\app\outputs\flutter-apk\app-release.apk
```

构建 arm64 专用 Debug APK：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\build-arm64-debug.ps1
```

连接 Android 16 arm64 设备后运行烟测：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\smoke-android16.ps1
```

验证空角色列表和 `/presets` 行为：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\test-empty-role-preset.ps1
```

验证官方事件规范化、私聊/群聊角色隔离和多群隔离：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\test-official-session-isolation.ps1
```

执行全部离线 Runtime 回归测试：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\test-runtime-suite.ps1
```

运行完整离线验收门禁：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\verify-offline.ps1
```

APK 输出位置：`build\app\outputs\flutter-apk\app-debug.apk`。

## 安装与迁移

### 干净安装

1. 在 Android 手机上安装签名 APK。
2. 首次打开后，进入“AI”和“设置”页面填写接口、QQ Bot 和更新清单配置。
3. 角色卡从“角色”页新建或导入；空配置不会自动启动 Runtime。

### 升级安装

使用相同签名的新版本直接覆盖安装，Android 会保留应用私有数据、Keystore 凭据、角色卡和会话目录。安装前先停止 Runtime；安装完成后重新打开应用并检查设置页状态。

### 旧版迁移

在旧版导出脱敏 JSON 后，在新版“设置 → 配置备份”导入。迁移只接受公开 AI 配置、主题和 `custom.*` 角色卡；AppID、AppSecret、API Key 和会话记录不会从旧备份导入，需要在新版重新填写。

### 已知限制

- 当前主验证设备为 Android 16 arm64；Android 9 适配已后置。
- 真实 QQ 网关、AI 对话和联网搜索已在真机验收；锁屏长时间运行和断网恢复仍需要更长时间观察。
- 联网搜索属于 DeepSeek 服务端能力：换成第三方聚合站后自动关闭，不会报错也不会降级成本地搜索。
- APK 安装仍由 Android 系统安装器确认，未知来源权限由系统管理。
- 当前 Release 签名构建受 Flutter AOT 中文路径兼容性影响，发布前需使用 ASCII 临时构建路径。

### AI 配置使用

- 在“AI”页选择接口类型并填写 Base URL；OpenAI-compatible 接口可以点击“拉取模型”获取 `/models` 列表，也可以手动输入模型名。
- 接口类型和思考程度默认「跟随 Base URL 自动决定」：Base URL 含 `deepseek.com` 时锁定为 OpenAI 兼容 + 关闭思考（服务端联网搜索只在这条路径、这个模式下可用），两个下拉会置灰。
- API Key 保存在 Android Keystore，模型列表请求由 Android 原生层发起，Flutter 页面不读取密钥明文。
- 联网搜索由模型自主判断：问题里带“今天/最近/最新/实时”时才会搜。角色卡里如果有“不要暴露自己是 AI / 不要谈论工具”这类强指令，模型可能因此拒绝搜索，遇到搜不到可以先放宽该条。

### 角色卡使用

角色页支持新建、编辑、导入、导出、删除和设置默认角色。自定义角色 ID 使用 `custom.xxx` 格式；人格提示词建议包含身份、性格、语气、行为规则、边界和示例回复。保存后在 QQ 中使用 `/preset <角色ID>` 切换。

Runtime Bundle 不作为普通 Git 文件提交。准备干净 Runtime 时执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\prepare-runtime-bundle.ps1 -SourceRuntime <干净 Runtime 目录>
```

构建前必须确认 Runtime 目录不含 `credentials`、`sessions`、`storage`、用户角色卡或真实配置。

检查本机工具链：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\check-toolchain.ps1
```

版本基线记录在 `tool/toolchain.json`。

## 凭据和数据

AppID、AppSecret、API Key 由用户在应用内填写，真实凭据只写入 Android Keystore。默认安装包不预置用户凭据、会话记录或自定义角色卡；导出备份会脱敏，不包含密钥和会话内容。内置 Runtime 代码及插件属于运行依赖，不等于用户配置。

AI 协议在应用中选择，DSH 使用固定的 `relay` 路由，并通过 `LLM_API` 选择 OpenAI Chat Completions、OpenAI Responses 或 Anthropic Messages。Base URL 含 `deepseek.com` 时运行时强制改用 Chat Completions（`openai-completions`），因为服务端搜索工具与 DeepSeek 的 `thinking` 参数只在这条协议上验证过。

## 验证范围

已完成并在 Android 16 arm64 真机验证：空配置首页、Flutter 测试、静态分析、Release 构建与升级覆盖安装、角色卡管理、主题和公网 IP 页面、前台 Runtime 服务、QQ 官方网关连接与自动恢复、真实群聊 AI 对话、DeepSeek 服务端联网搜索、主动回复测试按钮、网关事件记录、日志筛选与导出。

尚未完成：Android 9/14 真机矩阵、长时间锁屏稳定性、在线更新服务器（当前清单仍指向 0.2.5）、多群并发压力测试。详见 [TODO-flutter-refactor.md](TODO-flutter-refactor.md)。

旧版 WebView 的脱敏备份可以从设置页导入；新应用只接收公开 AI 配置和 `custom.*` 角色卡，不会迁移旧 AppID、AppSecret 或 API Key。

