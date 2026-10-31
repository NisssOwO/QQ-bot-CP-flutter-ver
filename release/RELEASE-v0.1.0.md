# QQ-bot-CP v0.1.0

## 构建信息

- 包名：com.shinycolors.officialbot
- 版本：0.1.0 (1)
- ABI：arm64-v8a
- 最低 Android：24
- 目标 Android：36
- APK 大小：176,880,840 字节（约 168.7 MiB）
- SHA-256：5b87e45c82c2a35f30a61450a6420ed6c33f2caf556e3a1211d56ab3624f6ad4
- 签名：工作区专用 Release keystore，APK v2 验证通过

## 本版本内容

- Flutter 新架构和深色主题界面
- AI 接口、模型拉取和思考程度配置
- QQ 官方机器人配置
- 角色卡新建、编辑、导入、删除和默认角色
- Android Runtime 自动恢复默认角色 preset；禁用不兼容的 bash、文件读取和工作目录工具
- Runtime 启动引导、阶段日志和预计耗时
- Android Foreground Service、通知和桌面小组件
- 公网 IPv4/IPv6 展示
- 在线/本地更新校验链路

## 验证记录

- Flutter 测试通过
- Dart 静态分析通过
- Android 16 arm64 烟测通过
- Runtime 离线回归通过
- APK 用户数据和凭据审计通过

真实 QQ WebSocket、AI 网络请求和 Android 9 矩阵仍需配置凭据与对应设备后验收。
