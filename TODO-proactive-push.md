# QQ-bot-CP 定时主动推送 TODO（方案 A）

工作区：本地 Flutter 工程目录（`F:\work\official-bot-migration\Flutter-ver`）
基线提交：`c732b0c chore(release): 0.2.0`
真机：Android 16 / arm64-v8a / HyperOS V816

本文件只登记「让机器人按计划在群里主动发消息」这一件事的做法。产品方向仍在 `TODO-flutter-refactor.md`，启动链路问题在 `TODO-runtime-startup.md`。每项写明：现象、证据、根因、做法、验收。改完一项就勾选并补提交号。

---

## 0. 方案与边界

### 0.1 为什么是"运行时内调度器"

QQ 官方接口不提供"定时发送"能力，平台侧只有「主动消息」这一种无上下文发送：调用 `/v2/groups/{group_openid}/messages` 时**不带 `msg_id` / `event_id`**（证据：`dist/transport/reply-target.js` 的三级兜底最后一级就是 `{ ...target, msgId: undefined, eventId: undefined }`；`QQBot.send()` 在 `target.msgId` 为空时不写 `msg_id`，见 `node_modules/@tencent-connect/qqbot-nodejs/dist/QQBot.js:446-468`）。所以"定时"必须由我们自己的进程算。

三条路里选 A：

| 方案 | 做法 | 结论 |
| --- | --- | --- |
| A | 运行时（`filesDir/runtime` 里的 Node）内做调度器，Node 进程在 = 定时器在 | **采用**。复用已有的 bot 实例与会话，零额外依赖 |
| B | Android 侧 `AlarmManager` / `WorkManager` 唤醒 | 弃。Java 层起来后仍要经 MethodChannel 进 Node 发消息，链路更长，且进程被杀时照样发不出 |
| C | 外部服务器 cron 调 API | 弃。用户没有服务器，违背"手机上自足"的产品前提 |

### 0.2 内嵌 feature 还是独立插件（A-1 / A-2）

**采用 A-1：作为 `@tencent-connect/dsh-qqbot` 的 feature 实现。**

理由：定时推送需要两样东西——① 主动发送能力（`bot` 实例）；② 群 `openid` 清单。两者都只存在于 `bootstrapGateway()` 的作用域里（`dist/gateway/bootstrap.js:33-101`），`bot` 没有被挂到 cordis 服务上，独立插件既拿不到 `bot`、也收不到入站消息事件。走独立插件就得先改 `bootstrap.js` 暴露服务，改的位置一样多，还多一层服务契约要维护。

A-2（独立插件 `@shiny-colors/qqbot-scheduler` + bootstrap 暴露 `ctx.set('qqbotSender', sender)`）留作后手：如果后续要把这套能力开源成分包，再按 P4 拆出去，feature 里的 `pusher.tick()` 已经与 cordis 解耦，迁移成本低。

### 0.3 不引第三方依赖

不装 `cron-parser` / `node-cron`：bundle 体积敏感（`assets/runtime` 已 434.7 MB），且这些库默认按服务器时区算，手机端容易被系统时区带跑。只支持三种够用的模式（`once` / `daily` / `interval`），时区由配置显式指定并用 `Intl.DateTimeFormat` 换算（P2）。

### 0.4 一期不做的事

- 不做群内指令（`/推送 on`）。一期群清单靠"群里有消息就自动登记"（P4）+ 手工编辑 JSON。指令留到二期（P5）。
- 不做 Flutter 首页卡片。一期靠 `logs/runtime.log` + 配置文件自证；卡片留到二期（P5）。
- 不支持图/语音推送。一期只发文本（`msg_type=0`），markdown 作为可选开关并在真机验证（见 4.3 风险）。

---

## 1. 数据与配置契约

### 1.1 落盘位置（关键约束）

`filesDir/runtime` 在 bundle 版本升级时会被**整树删除**（`RuntimeAssetInstaller.kt:17` `val target = File(context.filesDir, "runtime")` + `deleteRecursively()`）。而 `RuntimeProcessController.kt:109` 设了 `env["HOME"] = context.filesDir.absolutePath`，所以 `~/.dsh-qqbot/`（手机即 `filesDir/.dsh-qqbot/`）可以跨升级幸存——现成的 `dist/model/prefs-store.js` 就是这么存 `model-prefs.json` 的。

**结论：配置与状态一律写 `~/.dsh-qqbot/proactive-push.json`，不写 `runtime/` 下。**

### 1.2 Schema

```jsonc
{
  "version": 1,
  "enabled": true,
  "timeZone": "Asia/Shanghai",
  "groups": {
    "<group_openid>": {
      "name": "研发群",              // 仅备注，登记时尽量带上；拿不到就留空
      "enabled": true,
      "firstSeenAt": "2026-11-02T19:00:00+08:00",
      "lastSeenAt":  "2026-11-02T19:00:00+08:00"
    }
  },
  "tasks": [
    {
      "id": "morning-report",
      "enabled": true,
      "groups": ["<group_openid>", "all"],   // "all" = 所有已登记且 enabled 的群
      "text": "早上好，今天是 {date} {weekday}。",
      "mode": "daily",                       // once | daily | interval
      "time": "09:00",                       // daily 用
      "weekdays": [1, 2, 3, 4, 5],           // 可选，1=周一…7=周日
      "lastRunAt": "2026-11-02T09:00:03+08:00",
      "lastResult": { "ok": true, "code": 0 }
    },
    {
      "id": "hourly-ping",
      "enabled": false,
      "groups": ["all"],
      "text": "整点巡检 {time}",
      "mode": "interval",
      "everyMinutes": 60,
      "activeHours": ["08:00", "23:00"]
    },
    {
      "id": "self-test",
      "enabled": false,
      "groups": ["<group_openid>"],
      "text": "这条是定时任务自测。",
      "mode": "once",
      "at": "2026-11-02T19:40:00+08:00"
    }
  ],
  "dailyCount": { "2026-11-02": { "<group_openid>": 3 } }   // 每群每日配额账本
}
```

模板变量：`{date}`（`2026-11-02`）、`{time}`（`19:40`）、`{weekday}`（`周一`）、`{group}`（群名或 openid 后 6 位）。未知变量原样保留，不抛错。

### 1.3 一期验证用的最小配置

只配 `self-test` + 一个 `once` 任务、时间设在 3 分钟后，就能在不等一整天的前提下验证全链路（P8 第一项）。

---

## 2. 实施顺序

1. 第一组（打通发送）：P1、P2、P3
2. 第二组（接入运行时 + 本地跑通）：P4、P7
3. 第三组（打包装机验收）：P0、P6、P8
4. 二期（可选）：P5

P0 是打包依赖，必须先确认同步方向，否则 P6 重跑 `prepare-runtime-bundle.ps1` 会把改动冲掉。

---

## 3. 任务清单

### P0 确认父目录 runtime 与打包副本的同步方向

- [ ] 现象：`F:\work\official-bot-migration\runtime`（源）与 `Flutter-ver\android\app\src\main\assets\runtime`（打包副本）已经脱节，重跑打包脚本会覆盖新代码。
- [ ] 证据：两边 `runtime/role-command.mjs`、`runtime/test-official-orchestrator.mjs` 内容不同；打包副本里还多出 9 个父目录没有的文件；父目录没有 `plugins/`，而 assets 里有 `plugins/role-presets`。
- [ ] 根因：历史上直接改 assets 侧的 bundle 做过发版，没有回写源目录。
- [ ] 做法：
  - 本次改动按"以 assets 为准"落地：先改 `assets/runtime/...`，跑通后再把同一份文件回写到父目录 `runtime/...`（父目录没有的目录结构就新建）。
  - 在 `tool/prepare-runtime-bundle.ps1` 头部注释里记一句"源目录与 assets 的差异清单见 TODO-proactive-push.md P0"，避免下次又踩。
- [ ] 验收：`git -C F:\work\official-bot-migration status` 中 `runtime/` 侧新增文件可见且不被 gitignore；重跑 `tool/prepare-runtime-bundle.ps1` 后比对 `dist/features/proactive-push/*` 仍是最新版。

### P1 配置与群登记持久化

- [ ] 现象：现在没有任何地方记录"这个机器人被加进过哪些群"。`SessionManager` 的 `sessions` 是内存 `Map`，进程一重启，群清单就没了，定时任务无从下手。
- [ ] 证据：`node_modules/@tencent-connect/dsh-qqbot/dist/session/session-manager.js` 的 `sessions` 为内存结构；`dist/model/prefs-store.js` 只存 `model-prefs.json`（模型/preset 偏好），没有群维度数据。
- [ ] 根因：现有持久化粒度是"每个 peer 的偏好"，没有"机器人可见的群"这一实体。
- [ ] 做法：
  - 新增 `dist/features/proactive-push/store.js`：
    ```js
    import { readFileSync, writeFileSync, mkdirSync, renameSync, existsSync } from 'node:fs';
    import { resolve, dirname } from 'node:path';
    import { homedir } from 'node:os';

    export function statePath() {
      const home = process.env.HOME || homedir();
      return resolve(home, '.dsh-qqbot', 'proactive-push.json');
    }
    ```
  - `ProactivePushStore` 类：`load()` 容错（文件不存在/JSON 损坏 → 用默认值并 `logger.warn`，禁止抛错打断启动）；`save()` 用"写 `.tmp` + `renameSync`"原子替换；内容没变化就跳过写盘（避免 30 秒一次无谓 I/O 唤醒闪存）。
  - `rememberGroup(targetId)`：`firstSeenAt` 只在首次写，`lastSeenAt` 每次更新但**只在超过 10 分钟才落盘**，防抖。
  - 群被移出（发送返回 `40034101` / `40054003`）时把该群 `enabled=false` 并记 `lastError`，不删记录。
- [ ] 验收：手工往 `~/.dsh-qqbot/proactive-push.json` 写一条群记录，Node 重启后 `store.list()` 仍能读到；文件损坏时进程正常启动并在日志里看到 warn。

### P2 调度器 tick 与时间计算

- [ ] 现象：无。
- [ ] 证据：`@deepseek-ai/dsh-base/cordis.patch.yml` 里有 `- id: timer` / `name: '@deepseek-ai/cordis-plugin-timer'`（默认启用），`node_modules/@deepseek-ai/cordis-plugin-timer/lib/index.js` 把 `timeout` / `interval` 混入 ctx，且两者都包在 `ctx.effect()` 里随 fiber 释放。
- [ ] 根因：无（能力已具备，只是没用）。
- [ ] 做法：
  - 新增 `dist/features/proactive-push/scheduler.js`，导出纯函数便于单测：
    ```js
    export function nextDueAt(task, fromMs, tz)   // 返回下一次触发时间戳；不再触发返回 null
    export function isDue(task, nowMs, tz)        // nowMs >= nextDueAt 且未超过补发窗口
    ```
  - 时区换算用 `Intl.DateTimeFormat('en-CA', { timeZone: tz, ... })` 拆出年月日时分，不要依赖进程 `TZ`（HyperOS 上进程时区与系统时区偶有偏差）。
  - 30 秒一个 tick（`ctx.interval('proactive-push:tick', () => pusher.tick(), 30_000)`）。不追求秒级精度：QQ 主动消息频控是分钟级，且 30 秒粒度能让"设备休眠后闹钟漂移"自然收敛。
  - **补发窗口 30 分钟**：`now - due > 30min` 时视为漏发，只记 `lastResult.missed`，不补发。理由：手机被 Doze 冻结几小时后一口气补发 N 条，会直接撞群维度频控并刷屏。
  - `once` 任务发送后置 `enabled=false`；`daily` / `interval` 记 `lastFireKey`（如 `2026-11-02T09:00`），同一 key 只发一次，杜绝 tick 抖动带来的重复发送。
  - `interval` 的 `activeHours` 用 `[起, 止)` 半开区间；跨零点（如 `["22:00","02:00"]`）按"或"处理。
- [ ] 验收：`test-proactive-push.mjs`（P7）覆盖：daily 当天已过 → 顺延次日；weekdays 过滤；interval 边界与跨零点；休眠 3 小时后 tick 不补发；连续 10 次 tick 同一分钟只产出 1 条发送请求。

### P3 主动发送通道与频控守卫

- [ ] 现象：无。
- [ ] 证据：`QQBot.send()` 支持完全体参数（`node_modules/@tencent-connect/qqbot-nodejs/dist/QQBot.js:446-468`），JSDoc 第 438-444 行明确给了"Send a proactive message (no msgId)"的示例：`bot.send({ target: { scope: 'c2c', targetId: openid }, content: 'Hello from bot!' })`。群同理，把 `scope` 换成 `'group'`、`targetId` 换成 `group_openid`。
- [ ] 根因：无。
- [ ] 做法：
  - 发送**直连 `bot.send()`，不要走 `sender.sendMarkdown`**：`sender` 会先过 `resolveReplyTarget()`，msgid-cache 里若还留着 5 分钟内的 msgId，定时推送就会退化成"被动回复"，语义错位且受单关系 4 次回复额度约束。
    ```js
    const target = { scope: 'group', targetId: openid };   // 故意不带 msgId / eventId
    const body = { target, msgType: 0, content: text };
    await bot.send(body);
    ```
  - 频控守卫（`quota.js`）：单群两次发送最小间隔 3 秒（对应 20 qpm）；Bot 维度 60 条/分钟滑窗；单群每日计数落 `dailyCount`，到 950 条硬停并 `logger.error` 告警一次（留 50 条余量）。
  - 错误码映射（记录到该群的 `lastError`，并决定是否重试）：

    | 返回码 | 含义 | 处理 |
    | --- | --- | --- |
    | `40034100` | 主动消息超频控 | 60 秒后重试 1 次，仍失败则放弃并告警 |
    | `40034105` | 无权限（用户关了"允许主动发送"） | 不重试；该群标记 `enabled=false` + 明确日志"请让群成员在 QQ 设置里允许机器人主动消息" |
    | `40034101` / `40054003` | 机器人不在群 / 非群成员 | 不重试；该群标记 `enabled=false` |
    | `40054005` | 消息被去重 | 递增内部 msg_seq 后重试 1 次（主动消息不带 msg_id，正常不该出现；出现说明误带了 msgId） |
    | `40054010` / `40034006` | 内容含 URL / 内容违规 | 不重试；日志附任务 id，提示改文案 |
    | 其他 / 网络错误 | — | 重试 2 次，间隔 5s、15s |

  - 日志格式统一：`[proactive-push] task=<id> group=<openid后6位> ok|fail code=<n> elapsed=<ms>`，一期验收全靠这行。
- [ ] 验收：手工构造一次发送，群里能收到纯文本；把某群从机器人可见范围里移除后再发，日志出现 `code=40034101` 且该群下次 tick 不再被选中。

### P4 接入 bootstrap 与群自动登记

- [ ] 现象：无。
- [ ] 证据：`dist/gateway/bootstrap.js:50-58` 的 `bot.on('message')` 回调里已经有 `mCtx.replyTarget.scope` / `.targetId`，且紧跟着 `cacheMsgId(...)`；`dist/transport/inbound.js:12-19` 里 `scope === 'group' ? (msg.groupOpenid ?? msg.senderId) : msg.senderId` 就是群 openid 的来源。
- [ ] 根因：无（挂载点现成）。
- [ ] 做法：
  - `bootstrap.js` 顶部 `import { ProactivePushService } from '../features/proactive-push/index.js';`
  - 在 `bot.on('message')` 回调里、`cacheMsgId(...)` 之后加：
    ```js
    if (mCtx.replyTarget.scope === 'group') {
        pusher?.rememberGroup(mCtx.replyTarget.targetId);
    }
    ```
  - 在 `ctx.effect()` 之前构造：`const pusher = new ProactivePushService({ bot, config, logger });`，并在已有的生命周期 `ctx.effect(...)` 里加 `pusher.start(ctx)`（内部用 `ctx.interval`，随 fiber dispose 自动停）。
  - 配置开关走 `im-qqbot` 的既有 config 形态（`assets/runtime/qqbot-android.patch.yml` 的 `- id: im-qqbot / config:` 段），新增 `proactivePush: { enabled: true, timeZone: 'Asia/Shanghai' }`；不传时 `enabled` 默认 **true**（手机上发布版就是要能用），但 `tasks` 为空时什么也不做。
  - 注意 `config.debug` 下不要打印整份 JSON（含群 openid），只打数量。
- [ ] 验收：群里 @ 一次机器人后，`~/.dsh-qqbot/proactive-push.json` 出现该群 openid；杀掉 Node 重启，群清单仍在，且下一步 tick 能发出去。

### P5【二期】群内指令与首页卡片

- [ ] 现象：一期只能手工改 JSON 文件，普通用户不会。
- [ ] 做法（概要，二期再细化）：
  - 群内指令复用 `dist/commands/` 既有命令框架，新增 `dist/commands/push.js`：`/推送` 查看本群状态、`/推送 on|off` 切本群、`/推送 test` 立即发一条。新文件要进 P6 的刷新清单。
  - Flutter 首页在总览页加一张"定时推送"卡：读 `~/.dsh-qqbot/proactive-push.json` 摘要（任务数/今日成功数/上次结果），按钮「立即执行一次」→ MethodChannel → `MainActivity` 写一个触发文件（如 `~/.dsh-qqbot/proactive-push.trigger`），Node 侧 tick 检测到就执行一次并删除。避免在 Java 层直接调 Node 发送。
- [ ] 验收：二期定。

### P6 安装器刷新与打包

- [ ] 现象：已安装设备升级 APK 时，bundle 只按白名单增量刷新；新增文件不加白名单就永远不生效（表现为"PC 上好的，手机上没反应"）。
- [ ] 证据：`RuntimeAssetInstaller.kt:9` `VERSION = "node26-bundle-v44"`；`assetVersion` 相同则只走 `refreshEntry / refreshProfile / refreshProfilePlugins / refreshPiAiManifest / refreshOpenAiParser / refreshTurnErrorNormalizer / refreshAndroidRuntimeOverrides`。后者的硬编码清单目前是 9 个文件（`runtime/android-log-tap.cjs`、dsh-qqbot dist 的 `gateway/middleware-setup.js`、`transport/inbound.js`、`transport/outbound.js`、`commands/session.js`、`commands/preset.js`、`session/session-manager.js`、`model/prefs-store.js`、qqbot-nodejs dist 的 `middleware/typing-indicator.js`）。
- [ ] 根因：增量刷新靠白名单，不是全量比对。
- [ ] 做法：
  - `refreshAndroidRuntimeOverrides` 增加：
    - `node_modules/@tencent-connect/dsh-qqbot/dist/gateway/bootstrap.js`
    - `node_modules/@tencent-connect/dsh-qqbot/dist/features/proactive-push/index.js`
    - `node_modules/@tencent-connect/dsh-qqbot/dist/features/proactive-push/store.js`
    - `node_modules/@tencent-connect/dsh-qqbot/dist/features/proactive-push/scheduler.js`
    - `node_modules/@tencent-connect/dsh-qqbot/dist/features/proactive-push/quota.js`
  - 若要合并成单文件（`dist/features/proactive-push.js`），只登记 1 个路径——**推荐合并**，少 4 个白名单项，也少 4 次文件拷贝。
  - `VERSION` 从 `node26-bundle-v44` 升到 `node26-bundle-v45`，触发整树重解包（同时让新增文件落盘）。
  - 打包链：`tool/prepare-runtime-bundle.ps1` 会把 `runtime/` 同步进 assets，按 P0 的结论先改 assets 再回写源目录。
  - 检查 `android/app/build.gradle` 的 `aaptOptions` / `noCompress` 无需改动（`.js` 本来就以压缩形式打进 assets，运行时读取用 `copyTree` 流式拷出，不受影响）。
- [ ] 验收：用旧版 APK 覆盖安装新 APK（不清数据），进应用后 `filesDir/runtime/node_modules/@tencent-connect/dsh-qqbot/dist/features/proactive-push.js` 存在且 mtime 是新的；`filesDir/.dsh-qqbot/proactive-push.json` 未被清空。

### P7 单元测试接入既有回归套件

- [ ] 现象：现在的 `tool/test-runtime-suite.ps1` 跑 18 个 `assets/runtime/runtime/test-*.mjs`，没有任何调度相关用例。
- [ ] 做法：新增 `assets/runtime/runtime/test-proactive-push.mjs`（与既有用例同风格：纯 node，无第三方框架，断言失败 `process.exitCode = 1`），覆盖：
  - `nextDueAt`：daily 当天已过顺延次日；`weekdays` 过滤；`interval` 对齐；`activeHours` 跨零点。
  - 时区：`timeZone: 'Asia/Shanghai'` 与 `'UTC'` 对同一任务算出不同 due。
  - 补发窗口：due 在 40 分钟前 → 不触发。
  - 幂等：同一 `lastFireKey` 连续 10 次 tick 只发 1 次。
  - 频控：单群 3 秒内第二次请求被丢弃；每日 950 条后停止。
  - store：损坏 JSON 容错、原子写（写临时文件后 rename）、无变化不写盘。
  - 发送体：`bot.send` 收到的 body **不含** `msg_id`（用假 bot 断言），且 `msg_type=0`。
  把这个文件加入 `tool/test-runtime-suite.ps1` 的用例列表。
- [ ] 验收：`tool/test-runtime-suite.ps1` 从 18 个变 19 个且全 PASS；`dart analyze` 仍 No issues；`flutter test` 38 个仍通过。

### P8 真机验收

- [ ] 前置：在 PC 上先用 `.dsh-home` 起一次运行时，配 `once` 任务 3 分钟后触发，确认 `node` 侧全链路 OK 再装机。
- [ ] 验收清单：
  1. 群内 @ 机器人一次 → `~/.dsh-qqbot/proactive-push.json` 出现群 openid（P4）。
  2. 配 `once` 任务 3 分钟后 → 群里收到纯文本，日志有 `[proactive-push] task=... ok code=0`。
  3. 配 `daily 09:00` 任务 → 次日 09:00 收到（允许 ±60 秒误差）。
  4. 锁屏 1 小时后解锁 → 不补发、不刷屏（补发窗口生效）。
  5. 断网 10 分钟后恢复 → 恢复后该 tick 补一次，且日志显示一次重试成功。
  6. 关掉 QQ 客户端里"允许主动发送"再发 → 日志 `code=40034105`，该群被标记 `enabled=false`，无循环重试。
  7. 连续两个任务同时命中同一群 → 间隔 ≥3 秒错开发送（频控守卫）。
  8. 覆盖安装新 APK 不清数据 → 群清单与任务配置仍在（P6）。
- [ ] 验收方式：`adb logcat -s RuntimeNode:*` + 应用内日志页 + `adb shell run-as com.shinycolors.officialbot cat files/.dsh-qqbot/proactive-push.json`。

---

## 4. 风险与回滚

### 4.1 进程被冻结/杀死

Android 的 Doze 会把后台 Node 的定时器拖后。现有 `RuntimeService` 是前台服务，配合电池优化白名单可大幅缓解，但"绝对准时"不保证。**产品口径写清楚**：定时推送是"尽力而为"，漏发一次不算 bug（补发窗口 30 分钟，可接受漂移）。

### 4.2 主动消息权限

用户可在 QQ 客户端关闭「允许主动发送」，此时接口一律失败（`40034105`）。这是平台侧限制，只能提示、不能绕过。首次配置成功后建议在群里发一条说明，让群成员别关。

### 4.3 markdown 与 URL

群聊 `msg_type=2` 的 markdown 在部分机器人形态下要求自定义模板，纯文本最稳。若用户开 markdown 开关后收到 `40034006` / `40034004`，回退 `msg_type=0`。文案含 `http(s)://` 会命中 `40054010`，P3 的守卫里在发送前做一次 URL 预检并替换成 `hxxp://` 提示改文案。

### 4.4 回滚

feature 是新增文件 + `bootstrap.js` 两处小改动（import 一行、回调里一行、effect 里一行），patch yml 里 `proactivePush.enabled: false` 即可整体关闭，不需要回退 APK。所以 `enabled` 必须做到"关掉后 tick 不注册、群登记也不写盘"。

---

## 5. 待确认

1. 群 `openid` 是否稳定长久不变？官方文档只说"同一群在同一机器人下 openid 固定"，**换绑/迁移机器人 appId 后会变**。若用户换机器人，需要重新登记；P1 的 `firstSeenAt` 足以让用户看出"新群"。
2. 一期是否需要"每天多条不同文案轮换"？现在 `text` 是单条模板，多文案靠建多个任务绕过（任务 id 不同即可）。若需要轮换，在 P1 里把 `text` 扩展成数组 + `rotation: sequential|random`，成本很小，先不做。
3. 单群每日 1000 条上限是平台硬限，本方案的 950 软限是否需要暴露给用户配置？建议先写死。