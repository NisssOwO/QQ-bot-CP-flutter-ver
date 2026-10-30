# QQ-bot-CP Flutter 重构工程

这是新 Flutter 架构工作区，不依赖旧 WebView 页面。当前 P0 已建立：

- Flutter 页面入口和基础导航；
- 空配置模型；
- Runtime MethodChannel/EventChannel 契约；
- 日志和运行状态模型；
- Android 原生桥接占位；
- 不包含任何 AppID、模型、URL、角色卡或会话数据。

本机当前没有 Flutter/Dart SDK，因此尚未执行 `flutter pub get` 或 APK 构建。

## P0 构建前置

将 Flutter SDK 放入工作区后执行：

```powershell
$env:PATH = "F:\产出\official-bot-migration\Flutter ver\toolchain\flutter\bin;$env:PATH"
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```
