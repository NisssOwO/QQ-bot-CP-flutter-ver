# QQ-bot-CP 启动链路问题 TODO

工作区：`本地工程目录`
基线提交：`5ed4585 fix runtime process exec on HyperOS`
真机：Android 16 / arm64-v8a / 序列号 `未公开设备` / HyperOS V816（`未公开机型`）

本文件只登记「进入应用 → 点击启动 Runtime → Node/DSH 起来 → 连上 QQ」这条链路的问题与做法。产品功能规划仍在 `TODO-flutter-refactor.md`。每项都写明：现象、证据、根因、做法、验收方式。改完一项就在本节勾选，并补上提交号和验收结果。

## 0. 实施顺序

分四组按顺序做，每组做完构建、装机、跑一次 `tool/smoke-android16.ps1` 和 logcat 复查，记录提交号。

1. 第一组（启动反馈可信）：S2、S3、S4、S6
2. 第二组（Node/DSH 能起来）：S7、S9、S10、S11
3. 第三组（HyperOS 执行限制）：S8
4. 第四组（性能与保活）：S1、S5、S12、S13

## 1. 问题清单

### S1 冷启动首帧慢、启动期掉帧

- [ ] 现象：点开应用后状态卡迟迟不完整，进入过程中有明显卡顿。
- [ ] 证据：`Fully drawn com.shinycolors.officialbot/.MainActivity: +3s761ms`；`[ui-jank] frame=231ms build=108ms raster=23ms`、`frame=201ms build=183ms`、`frame=108ms build=73ms`；`SmartPower` 记录 `launchTime:3761ms`。无 FATAL、无 `MissingPluginException`。
- [ ] 根因：`lib/src/screens/home_shell.dart` 的 `_HomeShellState.initState` 同时发起 `_refreshState`、`_refreshConfig`、`_refreshPublicIp`、`_loadRecentLogs` 四路 MethodChannel；`_OverviewPage` 用 `ListView(cacheExtent: 5000)` 一次把所有卡片建出来。
- [ ] 做法：
  - `initState` 只保留 `_refreshState()` 和 `_refreshConfig()`，这两条决定状态卡内容。
  - `_refreshPublicIp()`、`_loadRecentLogs()` 移入 `WidgetsBinding.instance.addPostFrameCallback`，首帧后再发。
  - `cacheExtent` 改回默认值（或不超过 800），公网 IP 卡在数据回来前显示「检测中…」。
- [ ] 验收：冷启动 `Fully drawn` 降到 2 秒以内；`ui-jank` 中超过 100ms 的帧消失或只剩个位数。

### S2 通知权限被拒，前台服务通知不可见

- [ ] 现象：点「启动 Runtime」后通知栏没有任何提示，像没反应。
- [ ] 证据：真机 `dumpsys package com.shinycolors.officialbot` 中 `android.permission.POST_NOTIFICATIONS: granted=false`；`RuntimeService.onCreate` 已 `startForeground(1001)` 并建了 `runtime` 通知渠道。
- [ ] 根因：Android 13+ 需要运行时权限，项目没有申请入口。
- [ ] 做法：
  - `MainActivity.kt` 用 `registerForActivityResult(ActivityResultContracts.RequestPermission())` 暴露 MethodChannel 方法 `requestNotificationPermission`。
  - `lib/src/services/runtime_bridge.dart` 增加对应方法；`_restart()` 在 `startRuntime()` 之前先 `await requestNotificationPermission()`。
  - 返回 false 时在总览状态卡下显示常驻提示和按钮「去通知设置」，跳 `Settings.ACTION_APP_NOTIFICATION_SETTINGS` 并带包名。
  - `RuntimeService.createNotificationChannel` 用 `IMPORTANCE_LOW`，通知不响铃但可见。
- [ ] 验收：首次点启动弹出通知权限框；拒绝后总览页出现提示且按钮能跳到本应用通知设置；允许后通知栏能看到 Runtime 前台通知。

### S3 启动入口异常未捕获

- [ ] 现象：后台受限时点启动，界面只显示笼统错误或长时间无响应。
- [ ] 证据：`MainActivity.startRuntimeService()` 直接调用 `startForegroundService`，没有 try/catch；`RuntimeService.onStartCommand` 的 `catch (error: Exception)` 一律写 `runtime_start_failed`。
- [ ] 根因：Android 12+ 的后台启动限制会抛 `ForegroundServiceStartNotAllowedException`，没有映射成可读错误码。
- [ ] 做法：
  - `startRuntimeService()` 外层 `try { } catch (e: Exception) { ... }`，抛出带 `runtime_fgs_blocked` 前缀的错误。
  - MethodChannel 统一把这类异常映射成 `errorCode = runtime_fgs_blocked`。
  - Dart 侧 `_restart()` 对该错误码提示「请回到应用界面，点击总览页的『启动 Runtime』按钮」。
- [ ] 验收：从后台或受限场景触发启动时，界面出现上述可读提示，而不是 `PlatformException` 原文。

### S4 状态机并发写 SharedPreferences，进度来回跳

- [ ] 现象：同一轮启动里阶段耗时从 64864ms 跳回 95ms，状态卡信息前后矛盾。
- [ ] 证据：`shared_prefs/runtime.xml` 的 `logHistory` 中 `restart.failed` 的 `elapsedMs` 出现过 `64864` 与 `95` 两个值；`RuntimeService.onStartCommand` 在匿名线程里推进状态。
- [ ] 根因：`update()` 每次单独 `apply()` 到同一个 `runtime` prefs；`RuntimeWidgetProvider.updateAll` 与 `NotificationManager.notify` 也会读同一文件，读写在时间上交错。
- [ ] 做法：
  - 状态写入口收敛到 `Handler(Looper.getMainLooper())` 串行执行。
  - 每次 `update()` 只做一次 `prefs.edit().putString(...).putLong(...).apply()`。
  - 组件刷新与通知也在同一个 Handler 上执行。
  - 阶段耗时用 `SystemClock.elapsedRealtime()` 记录阶段起点，写入时算差值，不再反复覆盖同一键。
- [ ] 验收：连续三次启动，`runtime.xml` 中耗时单调递增，阶段顺序固定为 `restart.begin → process.stop → runtime.prepare → config.load → plugin.load → network.check → runtime.spawn → qq.connect → session.restore → ready`。

### S5 日志每行一次落盘

- [ ] 现象：启动阶段日志页卡顿，同时阶段推进变慢。
- [ ] 证据：`RuntimeProcessController.readStream()` 每读一行就向 `RuntimeEventBus` 投递，`RuntimeEventBus.emit()` 每次都重建 `logHistory` JSONArray（最多 500 条）并 `apply()`。
- [ ] 根因：日志写入频率与输出行数线性相关，DSH 启动期大量 info 行被放大成大量磁盘写。
- [ ] 做法：
  - `readStream()` 先写内存队列，`Handler.postDelayed` 每 300ms 合并一次 flush。
  - `logHistory` 只在日志页可见时落盘，其余时间只投递事件。
  - 保留最近 500 条上限不变。
- [ ] 验收：启动期 `runtime.xml` 写入次数显著减少，日志页仍能按顺序显示；阶段耗时回到个位数秒。

### S6 ready 过早，界面先显示运行中再回退失败

- [ ] 现象：状态先闪一下「运行中」，随后回到失败。
- [ ] 证据：`RuntimeService.onStartCommand` 在 `runtime.spawn` 后紧接着写 `qq.connect`、`session.restore`、`ready`；真机 logcat 同时出现 `E/nodejs Error: dsh: profile "qqbot" does not exist`。
- [ ] 根因：`ready` 只表示「进程已拉起」，不代表 DSH 与 QQ 已就绪。
- [ ] 做法：
  - `assets/runtime/runtime-entry.mjs` 在 DSH 子进程可用后向 stdout 输出固定标记 `QQBOT_READY`。
  - `RuntimeProcessController.readStream()` 识别该标记并回调 `RuntimeService`，见到后才置 `online`；之前保持 `starting`。
  - 15 秒内未见标记则进入 `failed`，message 写「DSH 启动超时」。
- [ ] 验收：正常启动时状态按 `starting → online` 单调推进，不再闪「运行中」；缺 profile 等错误直接停在 `failed` 并给出原因。

### S7 子进程环境被整体替换

- [ ] 现象：Node 起来后找不到系统工具或临时目录，部分模块报路径错误，曾出现 `Cannot find module '/data/user/0/com.shinycolors.officialbot/android-fs-compat.cjs'`。
- [ ] 证据：`RuntimeProcessController.start()` 中 `val env = HashMap(System.getenv()); env.putAll(environment)`，`environment()` 只提供 `SHINY_*`、`DSH_HOME`、`NODE_OPTIONS` 和凭据键。
- [ ] 根因：Android 应用进程的 JVM 环境缺少 `PATH`、`HOME`、`TMPDIR`、`ANDROID_DATA`、`ANDROID_ROOT`、`ANDROID_STORAGE`、`LANG`，子进程继承到的是残缺环境。
- [ ] 做法：
  - 以 `HashMap(environment)` 为基底，显式补 `PATH=/system/bin:/system/xbin:/product/bin`、`HOME=cacheDir`、`TMPDIR=cacheDir`、`ANDROID_DATA=/data`、`ANDROID_ROOT=/system`、`ANDROID_STORAGE=/storage`、`LANG=en_US.UTF-8`。
  - `environment()` 直接返回完整 map，调用方不再第二次合并。
  - 只覆盖需要控制的键：`SHINY_*`、`DSH_HOME`、`NODE_OPTIONS`、凭据。
- [ ] 验收：启动后日志中不再出现 `Cannot find module`；`process.env.PATH` 能解析到 `/system/bin`。

### S8 HyperOS 拒绝执行应用私有目录里的 ELF（`error=13`）

- [ ] 现象：点启动后 Runtime 直接失败，日志页写「Permission denied」。
- [ ] 证据：
  - `Cannot run program "/data/user/0/com.shinycolors.officialbot/files/runtime/bin/node" (in directory "/data/user/0/com.shinycolors.officialbot/files/runtime"): error=13, Permission denied`。
  - 复制到 `code_cache/qqbot-runtime-node` 后同样 `error=13`。
  - `run-as com.shinycolors.officialbot` 手动执行同一个 node 成功输出 `v26.11.2-pre`；SELinux 审计为 `avc: granted { execute } ... scontext=u:r:runas_app:s0 tcontext=u:object_r:app_data_file:s0`。
  - 文件权限本身正常（`-rwx--x--x`，bin 目录 `drwx------`）；`getconf PAGE_SIZE=4096`，不涉及 16KB 对齐。
  - 当前 `/data/app/.../lib/arm64` 为空，`dumpsys` 显示 `extractNativeLibs=false`；APK 内已有 `lib/arm64-v8a/libnode.so`（60,046,216 字节）。
- [ ] 根因：不是文件权限、不是 SELinux 拒绝，而是 HyperOS 对从 zygote 派生的普通应用进程 `execve` 应用私有目录的限制；换目录（files → code_cache）无效。
- [ ] 做法（提交 `5ed4585` 已完成前半）：
  - [x] `assets/runtime/bin/node` 复制为 `android/app/src/main/jniLibs/arm64-v8a/libnode.so`，`AndroidManifest.xml` 加 `android:extractNativeLibs="true"`。
  - [x] `RuntimeProcessController` 优先取 `applicationInfo.nativeLibraryDir/libnode.so`，缺失时回退到 `stageExecutable()` 复制到 `code_cache`。
  - [ ] 验证安装后 `lib/arm64` 下真有 `libnode.so`，且 `nativeLibraryDir` 路径可被执行。
  - [ ] 若 `nativeLibraryDir` 仍 `error=13`，改为 `System.loadLibrary("node")` 后在同进程内调用 Node 入口，不再起独立进程；兜底开关放设置页。
- [ ] 验收：启动后真实输出 `v26.11.2-pre`，`restart.failed` 不再出现 `error=13`。

### S9 `runtime-entry.mjs` 重复注入 `--require`

- [ ] 现象：补丁脚本可能被加载两次，日志出现重复初始化。
- [ ] 证据：`assets/runtime/runtime-entry.mjs` 里 `NODE_OPTIONS: [process.env.NODE_OPTIONS, "--require=${root}/android-fs-compat.cjs"].filter(Boolean).join(" ")`，父进程启动 Node 时若也带 `--require` 就会叠加。
- [ ] 根因：补丁注入职责分散在父进程与入口脚本两处。
- [ ] 做法：`runtime-entry.mjs` 自己拼接 `NODE_OPTIONS`（只含一次 `--require`），`RuntimeProcessController.start()` 不再给父进程设 `NODE_OPTIONS`；由入口脚本负责给 DSH 子进程注入。
- [ ] 验收：启动日志中 `android-fs-compat.cjs` 只被加载一次。

### S10 DSH profile 没进安装包

- [ ] 现象：启动后 DSH 报 `dsh: profile "qqbot" does not exist`，Runtime 起不来。
- [ ] 证据：`unzip -l` 中 `.dsh-home` 计数为 0；`assets/runtime/.dsh-home/profiles/qqbot/{cordis.yml,cordis.patch.yml,package.json}` 在本地产包里存在；`dsh-app-boot` 的 `loadProfile` 只认 `package.json` 存在。
- [ ] 根因：Android 构建忽略以点开头的资源目录，`RuntimeAssetInstaller.copyTree` 用 `assets.list()` 也看不到点目录。
- [ ] 做法：
  - `assets/runtime/.dsh-home` 改名为 `assets/runtime/dsh-home`。
  - `RuntimeAssetInstaller` 解包后复制到 `files/runtime/.dsh-home`。
  - `VERSION` 提升到 `node26-bundle-v41`，让老设备重新解包。
- [ ] 验收：启动后 `files/runtime/.dsh-home/profiles/qqbot/package.json` 存在；logcat 不再出现 `dsh: profile "qqbot" does not exist`。

### S11 QQ 服务默认地址不一致

- [ ] 现象：QQ 长期停在「连接中」。
- [ ] 证据：`dsh-qqbot/dist/gateway/bootstrap.js` 默认 `https://api.bot.qq.com`；`qqbot-nodejs/dist/protocol/api/api-client.js` 默认 `https://api.sgroup.qq.com`；当前 `runtimeEnvironment()` 没有设置 `QQBOT_BASE_URL`、`QQBOT_TOKEN_BASE_URL`。
- [ ] 根因：两个包各自的默认值不同，环境变量缺失时上下游走不同域名。
- [ ] 做法：
  - `RuntimeService.runtimeEnvironment()` 显式设置 `QQBOT_BASE_URL` 与 `QQBOT_TOKEN_BASE_URL`。
  - 默认生产 `https://api.sgroup.qq.com`，沙箱 `https://sandbox.api.sgroup.qq.com`。
  - 配置页增加「正式 / 沙箱」选择，保存后通过环境变量传入。
- [ ] 验收：启动日志中出现的 QQ 域名一致；切换沙箱后实际请求打到 `sandbox.api.sgroup.qq.com`。

### S12 运行期保活不足

- [ ] 现象：切到后台一段时间或从最近任务划掉后，Runtime 不再运行。
- [ ] 证据：`RuntimeService` 只返回 `START_STICKY`，无 `onTaskRemoved`，无 `BOOT_COMPLETED` 接收器；`dumpsys deviceidle` 的 `Whitelist user apps:` 为空；`AndroidManifest.xml` 无 `RECEIVE_BOOT_COMPLETED`。
- [ ] 根因：缺少系统事件与任务移除的重建路径，且用户从未被引导把应用加入电池优化白名单。
- [ ] 做法：
  - `RuntimeService.onTaskRemoved()` 中按配置重启服务；`android:stopWithTask="false"`。
  - 增加 `BOOT_COMPLETED` 接收器，设置页提供「开机自启」开关（默认关闭）。
  - 总览页状态卡下方直接放「电池优化设置」按钮（复用已有 `openBatteryOptimizationSettings()`）。
- [ ] 验收：划掉最近任务后 `dumpsys activity services com.shinycolors.officialbot` 仍能看到 RuntimeService；重启设备且开关打开时 Runtime 自动恢复。

### S13 体积与首次解包过重

- [ ] 现象：首次启动解包约 65 秒，安装包偏大。
- [ ] 证据：`RuntimeAssetInstaller.install()` 递归复制 `assets/runtime`（约 545MB、数万文件），只跳过 `length>0` 的已有文件；`VERSION="node26-bundle-v40"` 只写 prefs 不参与短路。Debug APK 333MB、Release APK 167MB；首次 `elapsedMs=64864`。
- [ ] 根因：逐文件跨分区复制，小文件数量多，且版本号未用于快速短路。
- [ ] 做法：
  - `assets/runtime` 打包成 `runtime.zip`，首次启动用 `ZipFile.getInputStream` 遍历解一次。
  - 把 `VERSION` 与 zip 内容哈希写入 prefs，二次启动命中即返回，不做逐文件比对。
- [ ] 验收：首次解包耗时降到 20 秒左右，二次启动几十毫秒内完成安装步骤。

## 2. 每项完成后的记录格式

改完一项后，在本节追加一行：

```
SXX | 提交 <hash> | 构建 <apk 路径/大小/sha256 前 12 位> | 真机：<关键 logcat 或 dumpsys 证据> | 结果 <通过/部分通过/失败>
```

## 3. 已知风险与前提

- 所有验证都在 `未公开设备` 这一台 HyperOS 设备上做，通用性需要另一台设备复核。
- 真实 QQ AppID/AppSecret、AI API Key 只保存在手机内，验证时只读取是否已配置，不读取内容。
- `F:\` 在 2026-10-31 曾出现整个盘只读，导致 `git add` 写 `.git/index.lock` 失败；后续提交前先确认 `.git` 可写。