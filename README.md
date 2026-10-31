# QQ-bot-CP Flutter 重构工程

这是 QQ-bot-CP 的独立 Flutter Android 工程。Flutter 负责界面、配置、角色管理、日志、主题、更新和小组件；Android Foreground Service 负责在应用私有目录启动 DSH/Node Runtime。工程不修改普通 QQ 客户端，也不依赖 Root、NapCat 或 OneBot。

## 当前状态

- Android applicationId：`com.shinycolors.officialbot`
- 应用名称：`QQ-bot-CP`
- 最低 Android SDK：24（Android 7.0）；目标 SDK：36
- 当前验证设备：Android 16、`arm64-v8a`
- 最近一次 Android 16 实机烟测：新包安装成功，空配置首页、设置页、角色页和小组件 Provider 检查通过；未启动真实 Runtime。
- Flutter 版本：3.47.9 stable
- JDK：25（版本基线见 `tool/toolchain.json`）
- 当前 Debug APK 约 330 MB；正式发布前仍需完成签名、ABI 和安装升级验收
- Release 使用不提交到 Git 的工作区 keystore；不要删除或更换它，否则升级安装会因签名不一致失败
- 当前 Release APK：`200,543,659` 字节（约 191.2 MiB）；SHA-256：`c4a011ee03a18c8303e89477930066529a76a36b2016515e25503233ebdfd5d0`

## 构建

```powershell
$env:JAVA_HOME = '<Android Studio 的 jbr 目录>'
$env:Path = "$env:JAVA_HOME\bin;<Flutter SDK 的 bin 目录>;$env:Path"
flutter pub get
dart analyze
flutter test
Set-Location .\android
.\gradlew.bat assembleDebug --no-daemon
# 正式签名 Release（需要本机 android/keystore.properties）
.\gradlew.bat assembleRelease --no-daemon
powershell -ExecutionPolicy Bypass -File .\tool\audit-release.ps1
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
- 真实 QQ WebSocket、AI 请求、锁屏长时间运行和断网恢复需要对应账号、网络和设备条件验收。
- APK 安装仍由 Android 系统安装器确认，未知来源权限由系统管理。
- 当前 Release 签名构建受 Flutter AOT 中文路径兼容性影响，发布前需使用 ASCII 临时构建路径。

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

AI 协议在应用中选择，DSH 使用固定的 `relay` 路由，并通过 `LLM_API` 选择 OpenAI Chat Completions、OpenAI Responses 或 Anthropic Messages。

## 验证范围

已完成：空配置首页、Flutter 测试、静态分析、Android Debug 构建、角色卡管理、主题和公网 IP 页面、前台 Runtime 服务、通知操作、更新校验骨架、Runtime 协议路由配置。

尚未完成：Android 9/14 真机矩阵、真实 QQ WebSocket 私聊/群聊验收、真实联网 AI 三协议请求、正式签名 Release、在线更新服务器和长时间锁屏稳定性测试。详见 [TODO-flutter-refactor.md](TODO-flutter-refactor.md)。

旧版 WebView 的脱敏备份可以从设置页导入；新应用只接收公开 AI 配置和 `custom.*` 角色卡，不会迁移旧 AppID、AppSecret 或 API Key。
