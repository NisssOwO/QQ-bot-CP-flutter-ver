# 使用问题修复 TODO

来源：2026-11-12 真机使用反馈 + 只读代码排查。路径相对仓库根目录。
优先级：P0 = 功能不可用，P1 = 结果错误或误导，P2 = 体验问题。

## 角色卡

- [x] **P0 修改默认角色后保存，提示"角色 ID 已存在"并失败**
  - 原因：`_load()` 把默认角色填进编辑框，但没有设置 `editingId`，它仍是空值（`lib/src/screens/home_shell.dart:1333`）。保存时的重复检查 `role.id == id && role.id != editingId`（`:1349`）因此一定成立。删除角色后也会进入同样的状态。
  - 修复：`_load()` 填入默认角色时同时设置 `editingExisting = true`、`editingId = id`；没有默认角色时调用 `_newRole()`。
  - 验收：进入角色页直接改提示词并保存成功；删除角色后新建角色正常。
- [x] **P0 保存角色卡后，运行中的机器人仍用旧人格**
  - 原因：`role-presets` 插件只在第一次用到时读一次文件（`this.loaded = true`，`android/app/src/main/assets/runtime/node_modules/@shiny-colors/role-presets/index.js:39-41`）。
  - 修复（二选一）：插件按文件 mtime 重新加载；或保存后提示"需重启 Runtime 生效"并提供重启按钮。
- [x] **P1 "设为默认"会存下编辑框里还没保存的内容**
  - 原因：`_setDefault` 用编辑框的值写入 `default-role`，但不写角色卡文件（`home_shell.dart:1372`），设置和 Runtime 读到的内容可能不一致。
  - 修复：内容有改动时先保存再设为默认，或只允许把已保存的角色设为默认。
- [x] **P1 导入 JSON 或文件时直接覆盖同 ID 角色，没有确认**（`home_shell.dart:1375`、`:1377`）。和手动保存一样弹出覆盖确认。
- [x] ~~**P1 APK 更新不会更新内置角色卡**~~（不适用：按用户要求不提供内置角色卡，APK 里没有角色卡文件，所有角色卡都由用户创建）
  - 原因：`RuntimeAssetInstaller.copyFile` 和 `RolePresetSync.sync` 遇到已有文件都会跳过（`android/app/src/main/kotlin/com/example/qq_bot_cp_flutter/RolePresetSync.kt:26`）。
  - 修复：内置卡带版本号，版本更新时覆盖；用户改过的内置卡和 `custom.*` 卡保持不动。
- [x] **P1 "清除全部配置"没有清掉角色卡**：只清了 `default-role`，`role-cards` 和 `runtime/presets` 下的自定义卡都还在（`MainActivity.kt:598-604`）。修代码，或者改说明文字使两者一致。
- [x] **P2 用 `/preset` 切换过的会话不跟随默认角色变化**，界面上看不出来是哪些会话。在页面上显示这些会话，或提供"全部恢复默认"。

## 主动回复

- [x] **P0 模型写死成 `deepseek-v4.1`，很可能每次触发都失败**
  - 原因：`relay` provider 下只登记了 `LLM_MODEL` 一个模型（`android/app/src/main/assets/runtime/qqbot-android.patch.yml:22-24`），而主动回复调用时用的是 `s.model || 'deepseek-v4.1'`（`.../dsh-qqbot/dist/middleware/proactive-reply.js:66`）。
  - 修复：去掉模型设置项，直接使用 `config.provider` + `config.model`，与机器人一致；同时删除 Flutter model 字段、`MainActivity.defaultProactiveReply()` 中的 `model`、页面说明里写死的模型名（`lib/src/screens/proactive_reply_page.dart:103`）。
- [x] **P0 `maxTokens: 200` 对推理模型太小**：relay 模型配置了 `reasoning: true`，思考过程可能把预算用完，回复为空后静默放弃。调大到 1000 以上，或关闭推理；为空时记日志。
- [x] **P0 没带 `msgId`，走的是额度很紧的完全主动消息**
  - 修复：把触发消息的 `messageId` 作为 `msgId` 发送，即被动回复（5 分钟内有效，每条最多 5 次）。超时就放弃，不退回主动发送。
- [x] **P1 安静时段和每日计数可能按 UTC 计算**：Node 子进程没有设置 `TZ`。先在真机确认 `new Date().getHours()`；如果确实是 UTC，在 `RuntimeService` 的环境变量中传入设备时区。
- [x] **P1 主动回复不用角色卡人格**：提示词只有一句"自然参与讨论"。加载 `LLM_PRESET` 对应的 prompt 作为 system 提示。
- [x] **P1 上下文不完整**：没有记录机器人自己的发言（包括主动回复），也没有记录 @ 机器人的消息（被 `plain()` 排除，`proactive-reply.js:20`），机器人可能重复自己。
- [x] **P1 关掉 `requireMention` 后主动回复会静默失效**（`proactive-reply.js:84`）。页面上加提示，或调整这个判断条件。
- [x] **P2 冷却和每日计数只存在内存里**，Runtime 重启后清零，每日上限可被绕过。持久化到 filesDir。

## 主动回复设置页

- [x] **P1 输入群 OpenID 后不点"应用"，改的其实是全局设置**。输入框内容变化时自动切换，或在顶部醒目显示当前编辑对象。
- [x] **P1 群 OpenID 只能手填**：从收到过消息的群里自动列出来让用户选，并显示群名或最近一条消息帮助辨认。
- [x] **P1 群配置是保存时对全局设置的完整拷贝**，之后改全局不会跟着变。改成只保存与全局不同的字段，读取时与全局合并。
- [x] **P2 数字只能 ±1 调整，而且每点一下就写一次文件**（冷却时间范围 0–86400 秒）。改成输入框或滑块，加防抖或手动保存。
- [x] **P2 页面和 Node 的取值范围不一致**：最短长度页面允许 0，Node 改为 1；上下文条数页面上限 30，Node 上限 100。另外要校验最短长度不能大于最长长度。
- [x] **P2 看不到运行状态**：显示今日已发条数、最近一次触发和失败原因，并提供"立即测试一次"按钮。

## 发布与验证

- [x] **P1 提升 `versionCode`**：当前安装的包仍是 9。
- [ ] **P1 真实 QQ 群端到端测试**（0.2.2 已装到真机；需在群里发言后用"立即测试一次"确认，Logs 页搜"主动回复已加载"可看 TZ）：确认模型调用、被动回复额度、时区、角色人格都正常，并在 Logs 页能看到失败原因。
