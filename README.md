# QQ-bot-CP Flutter 重构工程

这是 QQ-bot-CP 的独立 Flutter Android 工程。Flutter 负责界面、配置、角色管理、日志、主题、更新和小组件；Android Foreground Service 负责在应用私有目录启动 DSH/Node Runtime。工程不修改普通 QQ 客户端，也不依赖 Root、NapCat 或 OneBot。

## 当前状态

- Android applicationId：`com.shinycolors.officialbot`
- 应用名称：`QQ-bot-CP`
- 最低 Android SDK：24（Android 7.0）；目标 SDK：36
- 当前验证设备：Android 16、`arm64-v8a`
- Flutter 版本：3.47.9 stable
- JDK：17
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

APK 输出位置：`build\app\outputs\flutter-apk\app-debug.apk`。

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
