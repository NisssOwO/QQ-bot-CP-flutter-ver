import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/runtime_log.dart';
import '../models/public_config.dart';
import '../models/endpoint_test_result.dart';
import '../models/runtime_state.dart';
import '../models/gateway_status.dart';
import '../models/role_card.dart';
import '../services/runtime_bridge.dart';
import '../services/role_id.dart';
import '../services/log_presenter.dart';
import '../services/public_ip_service.dart';
import '../services/startup_stats.dart';
import '../services/config_draft.dart';
import '../services/background_tasks.dart';
import '../models/update_manifest.dart';
import '../services/update_service.dart';
import '../services/release_check.dart';
import '../theme/theme_controller.dart';
import '../theme/theme_bridge.dart';
import '../theme/app_theme_tokens.dart';
import '../theme/app_theme.dart';
import 'proactive_reply_page.dart' show ProactiveReplyPage;

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.onThemeChanged});
  final ValueChanged<ThemeSettings>? onThemeChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _bridge = RuntimeBridge();
  final _logs = <RuntimeLogEntry>[];
  Timer? _watchdog;
  String? _lastStageSignature;
  DateTime? _lastStageProgressAt;
  bool _recovering = false;
  StreamSubscription<RuntimeLogEntry>? _subscription;
  RuntimeState _state = const RuntimeState();
  GatewayStatus _gateway = const GatewayStatus();
  PublicConfig _publicConfig = const PublicConfig();
  int _index = 0;
  String _publicIp = '未检测';
  String _publicIpv6 = '未检测';
  String _ipCheckedAt = '';
  String _ipChangedAt = '';
  bool _ipLoading = false;
  bool _hidePublicIp = false;
  String? _lastSeenIpv4;

  @override
  void initState() {
    super.initState();
    _subscription = _bridge.logs.listen((entry) {
      if (!mounted) return;
      setState(() {
        _logs.add(entry);
        if (_logs.length > 500) _logs.removeAt(0);
      });
      // Runtime status is persisted by the Android service as each stage arrives. Refresh
      // the summary card when a state-bearing event arrives so the page does not remain on
      // the pre-restart "starting/unknown" snapshot until the user taps the toolbar button.
      if (entry.module == 'runtime' || entry.module == 'qq' || entry.module == 'ai' || entry.module == 'network') {
        unawaited(_refreshState());
      }
      if (entry.module == 'qq' || entry.message.contains('preset')) unawaited(_refreshSessionRoles());
    });
    _loadRecentLogs();
    _refreshState();
    _refreshConfig();
    _refreshSessionRoles();
    _refreshPublicIp();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoStartRuntime());
    _startStateWatchdog();
  }

  /// A start whose persisted stage stops advancing for this long is reported instead of
  /// leaving the card on "初始化中" until the user restarts by hand.
  static const Duration _staleStartAfter = Duration(seconds: 60);

  void _startStateWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      // 网关状态独立于启动阶段刷新：进程活着但连接掉了，这里才看得出来。
      unawaited(_refreshGateway());
      final state = _state;
      if (state.status != RuntimeStatus.starting && state.status != RuntimeStatus.reconnecting) {
        _lastStageProgressAt = null;
        return;
      }
      // A start whose stage keeps advancing is progressing. Before the service ever
      // writes a stamp, only a change in text counts as progress.
      final signature = state.stageAt > 0
          ? '${state.status.name}|${state.phase}|${state.stageAt}'
          : '${state.status.name}|${state.phase}|${state.message}';
      final now = DateTime.now();
      final last = _lastStageProgressAt;
      if (last == null || signature != _lastStageSignature) {
        _lastStageSignature = signature;
        _lastStageProgressAt = now;
        return;
      }
      if (now.difference(last) < _staleStartAfter) return;
      _lastStageProgressAt = null;
      if (_recovering) return;
      _recovering = true;
      try {
        await _restart(quiet: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('启动卡在「${state.phase}」超过 60 秒，已自动重启 Runtime'),
          ));
        }
      } finally {
        _recovering = false;
      }
    });
  }

  Future<void> _autoStartRuntime() async {
    if (!mounted) return;
    try {
      final config = await _bridge.config();
      final state = await _bridge.state();
      // Show the Flutter shell first, then recover a service that was killed by Android,
      // an APK update, or a task swipe. Respect an explicit user stop.
      if (config.qqConfigured && config.llmConfigured && !state.processAlive && !state.userStopped && (state.status == RuntimeStatus.stopped || state.status == RuntimeStatus.failed || state.status == RuntimeStatus.starting)) {
        await _restart(quiet: true);
      }
    } catch (_) {}
  }

  Future<void> _loadRecentLogs() async {
    try {
      final recent = await _bridge.recentLogs();
      if (!mounted) return;
      setState(() {
        _logs.addAll(recent);
        if (_logs.length > 500) _logs.removeRange(0, _logs.length - 500);
      });
    } catch (_) { }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshState() async {
    try {
      final state = await _bridge.state();
      if (mounted) setState(() => _state = state);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _state = RuntimeState(status: RuntimeStatus.failed, message: error.message ?? '桥接失败'));
    }
  }

  Future<void> _refreshConfig() async {
    try { final config = await _bridge.config(); if (mounted) setState(() => _publicConfig = config); } catch (_) {}
  }

  /// 拉取 QQ 网关真实状态；只在内容变化时重建，避免 5 秒一次无意义刷新。
  Future<void> _refreshGateway() async {
    try {
      final gateway = await _bridge.gatewayStatus();
      if (!mounted) return;
      final changed = gateway.state != _gateway.state ||
          gateway.updatedAt != _gateway.updatedAt ||
          gateway.since != _gateway.since ||
          gateway.code != _gateway.code ||
          gateway.attempts != _gateway.attempts ||
          gateway.error != _gateway.error ||
          gateway.lastError != _gateway.lastError;
      if (changed) setState(() => _gateway = gateway);
    } catch (_) {}
  }
  Future<void> _refreshSessionRoles() async {
  }

  Future<void> _restart({bool quiet = false}) async {
    try {
      final config = await _bridge.config();
      final missing = <String>[];
      if (!config.qqConfigured || config.appId.trim().isEmpty) missing.add('QQ AppID / AppSecret');
      if (!config.llmConfigured) missing.add('AI API Key');
      if (config.protocol.trim().isEmpty) missing.add('接口类型');
      if (config.model.trim().isEmpty) missing.add('模型名称');
      if (config.baseUrl.trim().isEmpty) missing.add('Base URL');
      if (missing.isNotEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('尚未启动：请先填写 ${missing.join('、')}')));
        return;
      }
      if (!quiet) {
        final permission = await _bridge.requestNotificationPermission();
        if (permission == 'denied' && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('通知权限被拒绝，Runtime 仍会启动，但看不到常驻通知。'),
            action: SnackBarAction(label: '去设置', onPressed: () => _bridge.openNotificationSettings()),
          ));
        }
      }
      setState(() => _state = _state.copyWith(status: RuntimeStatus.starting, phase: 'restart.begin', message: '正在启动 Runtime'));
      final outcome = await _bridge.restart();
      if (outcome['started'] != true && outcome['reason'] == 'preparing' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('运行文件还在解包，完成后会自动启动；现在重启会丢掉已解包的文件'),
        ));
      }
      await _refreshState();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重启请求失败：$error')));
    }
  }

  /// Looks up the phone's public address. The QQ open platform only accepts calls from
  /// whitelisted IPs, and phones on mobile data change address between networks.
  Future<void> _refreshPublicIp() async {
    if (_ipLoading) return;
    final timer = Stopwatch()..start();
    setState(() => _ipLoading = true);
    final result = await const PublicIpService().lookup();
    timer.stop();
    if (!mounted) return;
    final changed = result.ipv4 != null && _lastSeenIpv4 != null && _lastSeenIpv4 != result.ipv4;
    setState(() {
      _ipLoading = false;
      _publicIp = result.ipv4 ?? '无法获取';
      _publicIpv6 = result.ipv6 ?? '无法获取';
      _ipCheckedAt = _clock(result.checkedAt);
      if (changed) _ipChangedAt = _clock(result.checkedAt);
      if (result.ipv4 != null) _lastSeenIpv4 = result.ipv4;
      _logs.add(RuntimeLogEntry(
        time: result.checkedAt,
        level: result.error == null ? LogLevel.info : LogLevel.warn,
        module: 'public-ip',
        message: result.error == null
            ? '公网 IP 查询完成（${timer.elapsedMilliseconds} ms）${changed ? '，地址已变化' : ''}'
            : '公网 IP 查询失败（${timer.elapsedMilliseconds} ms）：${result.error}',
      ));
    });
  }

  static String _clock(DateTime time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

  void _copyPublicIp(String value) {
    if (value == '未检测' || value == '无法获取') return;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制公网 IP：$value')));
  }

  /// Drops both the persisted history and the rows currently on screen.
  Future<void> _clearLogs() async {
    try {
      await _bridge.clearLogs();
      if (!mounted) return;
      setState(_logs.clear);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日志已清空')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清空日志失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final startupStats = summarizeStartup(_logs);
    final pages = <Widget>[
      _OverviewPage(state: _state, gateway: _gateway, startupStats: startupStats, publicIp: _publicIp, publicIpv6: _publicIpv6, ipCheckedAt: _ipCheckedAt, ipChangedAt: _ipChangedAt, loadingIp: _ipLoading, hideIp: _hidePublicIp, qqConfigured: _publicConfig.qqConfigured, llmConfigured: _publicConfig.llmConfigured, onRefreshIp: _refreshPublicIp, onCopyIp: _copyPublicIp, onToggleHideIp: () => setState(() => _hidePublicIp = !_hidePublicIp), onOpenAi: () => setState(() => _index = 1), onRestart: () => _restart()),
      _ConfigPage(bridge: _bridge, onSaved: _refreshConfig),
      _LogPage(logs: _logs, onClear: _clearLogs, bridge: _bridge),
      _RolePage(bridge: _bridge),
      _SettingsPage(bridge: _bridge, onThemeChanged: widget.onThemeChanged),
      ProactiveReplyPage(bridge: _bridge),
    ];
    // 手机上用底部导航，平板横过来后换成左侧导航加更宽的卡片。
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final tokens = AppSurfaceTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('QQ-bot-CP'),
        actions: [
          IconButton(
            onPressed: () async {
              await _refreshState();
              await _refreshConfig();
            },
            tooltip: '刷新状态和配置',
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      body: wide
          ? Row(children: [
              _NavRail(selected: _index, onSelected: (value) => setState(() => _index = value)),
              VerticalDivider(width: 1, color: tokens.outline),
              Expanded(child: pages[_index]),
            ])
          : pages[_index],
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: [
                for (final item in _navItems) NavigationDestination(icon: Icon(item.$1), selectedIcon: Icon(item.$2), label: item.$3),
              ],
            ),
    );
  }
}



/// 页面级滚动容器：手机单列，平板（>=1100）自动排成两列并限制最大宽度。
/// 用 [_FullWidth] 包住的卡片在平板下占满整行（例如状态 hero）。
Widget _pageBody(BuildContext context, List<Widget> children) {
  final wide = MediaQuery.sizeOf(context).width >= 1100;
  Widget unwrap(Widget child) => child is _FullWidth ? child.child : child;
  final content = wide
      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final child in children)
            if (child is _FullWidth) Padding(padding: const EdgeInsets.only(bottom: 12), child: child.child),
          _twoColumns([for (final child in children) if (child is! _FullWidth) child]),
        ])
      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final child in children) unwrap(child)]);
  return SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
    child: Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1320), child: content),
    ),
  );
}

class _FullWidth extends StatelessWidget {
  const _FullWidth(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

Widget _twoColumns(List<Widget> children) {
  final cards = [
    for (final child in children)
      if (child is! SizedBox) child,
  ];
  final left = <Widget>[];
  final right = <Widget>[];
  for (var i = 0; i < cards.length; i++) {
    (i.isEven ? left : right).add(Padding(padding: const EdgeInsets.only(bottom: 12), child: cards[i]));
  }
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
  ]);
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({required this.state, required this.gateway, required this.startupStats, required this.publicIp, required this.publicIpv6, required this.ipCheckedAt, required this.ipChangedAt, required this.loadingIp, required this.hideIp, required this.qqConfigured, required this.llmConfigured, required this.onRefreshIp, required this.onCopyIp, required this.onToggleHideIp, required this.onOpenAi, required this.onRestart});
  final RuntimeState state;
  final GatewayStatus gateway;
  final StartupStats startupStats;
  final String publicIp;
  final String publicIpv6;
  final String ipCheckedAt;
  final String ipChangedAt;
  final bool loadingIp;
  final bool hideIp;
  final bool qqConfigured;
  final bool llmConfigured;
  final VoidCallback onRefreshIp;
  final ValueChanged<String> onCopyIp;
  final VoidCallback onToggleHideIp;
  final VoidCallback onOpenAi;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final tokens = AppSurfaceTokens.of(context);
    final ready = qqConfigured && llmConfigured;
    final ipv4Ready = publicIp != '未检测' && publicIp != '无法获取';
    return _pageBody(context, [
      _FullWidth(_statusHero(context)),
      const SizedBox(height: 12),
      _gatewayCard(context),
      if (state.status == RuntimeStatus.failed) ...[
        const SizedBox(height: 12),
        AppCard(
          title: '启动失败：${state.phase}',
          trailing: Icon(Icons.error_outline, color: AppThemeTokens.of(context).error),
          child: Text('${state.message.isEmpty ? '打开日志查看详细信息' : state.message}${state.errorCode == null ? '' : '（错误码 ${state.errorCode}）'}${state.exitCode == null ? '' : '（退出码 ${state.exitCode}）'}', style: TextStyle(fontSize: 13, color: tokens.mutedText)),
        ),
      ],
      const SizedBox(height: 12),
      AppCard(
        title: '启动耗时统计',
        child: Column(children: [
          _kv(context, '最近一次', '${_formatDuration(startupStats.lastMs ?? 0)}${startupStats.lastUnpacked ? '（含解包）' : ''}'),
          _kv(context, '解包启动平均', startupStats.unpackedAverage == null ? '—' : '${_formatDuration(startupStats.unpackedAverage!)} · 样本 ${startupStats.unpacked.length} 次'),
          _kv(context, '日常启动平均', startupStats.cachedAverage == null ? '—' : '${_formatDuration(startupStats.cachedAverage!)} · 样本 ${startupStats.cached.length} 次'),
          _kv(context, '网络重连', startupStats.reconnects == 0 ? '本次记录内没有发生' : '记录 ${startupStats.reconnects} 次重试', last: true),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        title: '设备公网 IP',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(onPressed: onToggleHideIp, child: Text(hideIp ? '显示' : '隐藏', style: const TextStyle(fontSize: 13))),
          if (loadingIp)
            const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(tooltip: '重新检测', onPressed: onRefreshIp, icon: const Icon(Icons.refresh, size: 18)),
        ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _IpLine(label: 'IPv4', value: publicIp, hidden: hideIp, onCopy: onCopyIp),
          _IpLine(label: 'IPv6', value: publicIpv6, hidden: hideIp, onCopy: onCopyIp),
          if (ipCheckedAt.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('检测时间：$ipCheckedAt${ipChangedAt.isEmpty ? '' : ' · 上次变化：$ipChangedAt'}', style: TextStyle(fontSize: 12, color: tokens.mutedText))),
          if (!hideIp && ipv4Ready) Padding(padding: const EdgeInsets.only(top: 10), child: OutlinedButton.icon(onPressed: () => onCopyIp(publicIp), icon: const Icon(Icons.copy, size: 16), label: const Text('复制 IPv4'))),
          Padding(padding: const EdgeInsets.only(top: 8), child: Text('QQ 开放平台按白名单放行；换网络后地址会变。', style: TextStyle(fontSize: 12.5, color: tokens.mutedText))),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        title: 'Runtime 控制',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            !ready
                ? '还缺 AI 接口或 QQ 凭据，填完再回来启动。'
                : state.status == RuntimeStatus.online || state.status == RuntimeStatus.starting || state.status == RuntimeStatus.reconnecting
                    ? 'Runtime 正在运行；重启会重新加载插件、角色卡与配置。'
                    : '配置已齐全，点上方「重启」即可启动。',
            style: TextStyle(fontSize: 13, color: tokens.mutedText),
          ),
          if (!ready) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: onOpenAi, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('去填写配置')),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(child: Column(children: [
        _statusLine(context, 'QQ 官方机器人', qqConfigured ? 'AppID 与 AppSecret 已配置' : '等待填写 AppID 与 AppSecret', qqConfigured),
        Divider(height: 20, color: tokens.outline),
        _statusLine(context, 'AI 接口', llmConfigured ? 'API Key 已配置' : '等待填写 API Key', llmConfigured),
      ])),
      const SizedBox(height: 12),
      AppCard(child: Wrap(spacing: 8, runSpacing: 8, children: [
        _qqPill(context),
        _Pill(label: 'AI：${state.aiStatus}', tone: state.aiStatus == '在线' ? tokens.heroEnd : tokens.mutedText),
        _Pill(label: '网络：${state.networkStatus}', tone: state.networkStatus == '在线' ? tokens.heroEnd : tokens.mutedText),
        if (state.reconnectAttempts > 0) _Pill(label: '第 ${state.reconnectAttempts} 次重连 · ${state.nextRetryMs ~/ 1000}s', tone: AppThemeTokens.of(context).warning),
        if (state.qqFailureCount > 0) _Pill(label: 'QQ 失败 ${state.qqFailureCount} 次', tone: AppThemeTokens.of(context).warning),
        if (state.aiFailureCount > 0) _Pill(label: 'AI 失败 ${state.aiFailureCount} 次', tone: AppThemeTokens.of(context).warning),
      ])),
      const SizedBox(height: 12),
      AppCard(
        title: '聊天指令',
        subtitle: '点右侧按钮逐条复制到 QQ。',
        child: Column(children: [for (final command in _chatCommands) _CommandCopyRow(command: command.$1, description: command.$2)]),
      ),
    ]);
  }

  /// 底部状态 pill 用网关的真实状态，避免把「进程还活着」显示成「在线」。
  /// 与 [state.qqStatus] 不同，这里读的是 SDK 写出的连接状态文件。
  Widget _qqPill(BuildContext context) {
    final tokens = AppSurfaceTokens.of(context);
    final theme = AppThemeTokens.of(context);
    final now = DateTime.now();
    final (String label, Color tone) = !gateway.hasData
        ? (state.qqStatus, state.qqStatus == '在线' ? tokens.heroEnd : tokens.mutedText)
        : switch (gateway.kind) {
            GatewayState.online => gateway.heartbeatStale(now) ? ('心跳超时', theme.warning) : ('在线', tokens.heroEnd),
            GatewayState.connecting => gateway.stalled(now) ? ('连接卡住', theme.error) : ('连接中', tokens.mutedText),
            GatewayState.reconnecting => gateway.stalled(now) ? ('重连卡住', theme.error) : ('重连中', theme.warning),
            GatewayState.offline => ('已离线', theme.error),
            GatewayState.failed => ('启动失败', theme.error),
            GatewayState.unknown => (state.qqStatus, tokens.mutedText),
          };
    return _Pill(label: 'QQ：$label', tone: tone);
  }

  /// QQ 网关的真实连接状态。这是唯一能区分「进程还在」和「真的在线」的地方：
/// 中间件注册失败、凭据被拒、SDK 放弃重连时，进程照常活着，但这里会变红。
  Widget _gatewayCard(BuildContext context) {
    final tokens = AppSurfaceTokens.of(context);
    final theme = AppThemeTokens.of(context);
    final now = DateTime.now();
    final stale = gateway.heartbeatStale(now);
    final kind = gateway.kind;
    late final String title;
    late final Color tone;
    late final String detail;
    if (kind == GatewayState.online && !stale) {
      final connected = gateway.connectedFor(now);
      title = '在线';
      tone = tokens.heroEnd;
      detail = '已连接 ${connected == null ? '—' : _formatDuration(connected.inMilliseconds)} · 心跳 ${_agoLabel(now, gateway.updated)}';
    } else if (kind == GatewayState.online) {
      title = '心跳超时';
      tone = theme.warning;
      detail = '最后一次心跳 ${_agoLabel(now, gateway.updated)}。进程可能还活着，但这条连接已经没人维护了，消息收不到。App 会自动重启 Runtime。';
    } else if (kind == GatewayState.connecting && gateway.stalled(now)) {
      title = '连接卡住';
      tone = theme.error;
      detail = '最后一次状态写入在 ${_agoLabel(now, gateway.updated)}，握手看起来停在了一个不会返回的请求上。App 会自动重启 Runtime。';
    } else if (kind == GatewayState.connecting) {
      title = '连接中';
      tone = tokens.mutedText;
      detail = '正在建立 QQ 网关长连接…';
    } else if (kind == GatewayState.reconnecting && gateway.stalled(now)) {
      title = '重连卡住';
      tone = theme.error;
      detail = '第 ${gateway.attempts} 次重连后，最后一次状态写入在 ${_agoLabel(now, gateway.updated)}${_gatewayCodeText(gateway)}。重连循环已经卡死，App 会自动重启 Runtime。';
    } else if (kind == GatewayState.reconnecting) {
      title = '重连中';
      tone = theme.warning;
      detail = '第 ${gateway.attempts} 次重连${_gatewayCodeText(gateway)}';
    } else if (kind == GatewayState.offline) {
      title = '已离线';
      tone = theme.error;
      detail = 'SDK 已放弃重连${_gatewayCodeText(gateway)}。需要检查 AppID/Secret 与开放平台的机器人状态，然后重启。';
    } else if (kind == GatewayState.failed) {
      title = '启动失败';
      tone = theme.error;
      detail = gateway.error.isEmpty ? 'bot.start() 失败，打开日志查看原因。' : 'bot.start() 失败：${gateway.error}';
    } else {
      title = '未启动';
      tone = tokens.mutedText;
      detail = '还没有网关状态。Runtime 未启动，或仍在初始化。';
    }
    final notes = <String>[
      if (gateway.lastError.isNotEmpty) '最近错误：${gateway.lastError}',
      if (gateway.error.isNotEmpty && kind != GatewayState.failed) '启动错误：${gateway.error}',
      if (gateway.updated != null) '状态写入：${_agoLabel(now, gateway.updated)}',
    ];
    return AppCard(
      title: 'QQ 网关连接',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tone)),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(detail, style: TextStyle(fontSize: 13, height: 1.45, color: tokens.mutedText)),
        for (final note in notes) Padding(padding: const EdgeInsets.only(top: 6), child: Text(note, style: TextStyle(fontSize: 12, color: tokens.mutedText))),
      ]),
    );
  }

  static String _gatewayCodeText(GatewayStatus status) {
    final parts = <String>[
      if (status.code != null) 'code ${status.code}',
      if (status.reason.isNotEmpty) status.reason,
    ];
    return parts.isEmpty ? '' : '（${parts.join(' · ')}）';
  }

  static String _agoLabel(DateTime now, DateTime? at) {
    if (at == null) return '未知';
    final diff = now.difference(at);
    if (diff.isNegative || diff.inSeconds < 5) return '刚刚';
    if (diff.inSeconds < 60) return '${diff.inSeconds} 秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }

  Widget _statusHero(BuildContext context) {
    final tokens = AppSurfaceTokens.of(context);
    final statusColor = _statusColor(context, state.status);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [tokens.heroStart, tokens.heroEnd], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('运行状态', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85))),
          const Spacer(),
          _HeroButton(icon: Icons.restart_alt, label: '重启', onPressed: onRestart),
        ]),
        const SizedBox(height: 2),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_statusLabel(state.status), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2)),
          const Spacer(),
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle, boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.6), blurRadius: 8)])),
            const SizedBox(width: 7),
            Text(_formatDuration(state.elapsedMs), style: const TextStyle(fontSize: 13, color: Colors.white)),
          ])),
        ]),
        const SizedBox(height: 4),
        Text(_phaseDescription(state, startupStats), style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.9))),
      ]),
    );
  }

  Widget _statusLine(BuildContext context, String title, String subtitle, bool ok) {
    final tokens = AppSurfaceTokens.of(context);
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: ok ? AppThemeTokens.of(context).success : AppThemeTokens.of(context).warning, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        Text(subtitle, style: TextStyle(fontSize: 12, color: tokens.mutedText)),
      ])),
    ]);
  }

  Widget _kv(BuildContext context, String label, String value, {bool last = false}) {
    final tokens = AppSurfaceTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 7),
      child: Row(children: [
        SizedBox(width: 96, child: Text(label, style: TextStyle(fontSize: 13, color: tokens.mutedText))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13.5))),
      ]),
    );
  }

  static String _statusLabel(RuntimeStatus status) => switch (status) {
        RuntimeStatus.stopped => '已停止',
        RuntimeStatus.starting => '启动中',
        RuntimeStatus.online => '运行中',
        RuntimeStatus.reconnecting => '重连中',
        RuntimeStatus.failed => '异常',
        RuntimeStatus.stopping => '停止中',
      };

  static Color _statusColor(BuildContext context, RuntimeStatus status) => switch (status) {
    RuntimeStatus.online => AppThemeTokens.of(context).success,
    RuntimeStatus.failed => AppThemeTokens.of(context).error,
    RuntimeStatus.reconnecting || RuntimeStatus.starting || RuntimeStatus.stopping => AppThemeTokens.of(context).warning,
    RuntimeStatus.stopped => Theme.of(context).colorScheme.outline,
  };

  static String _phaseDescription(RuntimeState state, StartupStats startupStats) {
    if (state.status == RuntimeStatus.stopped && state.message.isEmpty) return '还没有启动 Runtime';
    final estimate = switch (state.phase) {
      'restart.begin' || 'process.stop' => '约 1 秒',
      'runtime.prepare' || 'config.load' => '约 1–3 秒',
      'plugin.load' || 'runtime.spawn' => '约 3–10 秒',
      'network.check' || 'qq.connect' => '约 2–15 秒（取决于网络）',
      'session.restore' || 'ready' || 'restart.complete' => '约 1 秒',
      _ => null,
    };
    final history = startupStats.cachedAverage ?? startupStats.unpackedAverage;
    final historyText = history == null ? null : '历史平均 ${_formatDuration(history)}';
    final current = state.message.isEmpty ? state.phase : state.message;
    return state.status != RuntimeStatus.starting ? current : '$current · ${historyText ?? '预计 $estimate'}';
  }

  static String _formatDuration(int ms) {
    if (ms <= 0) return '—';
    if (ms < 1000) return '$ms ms';
    final seconds = ms / 1000;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)} 秒';
    final minutes = seconds ~/ 60;
    return '$minutes 分 ${((seconds - minutes * 60).round()).toString().padLeft(2, '0')} 秒';
  }
}

/// 平板宽度下替换底部导航的左侧导航条。
class _NavRail extends StatelessWidget {
  const _NavRail({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = AppSurfaceTokens.of(context);
    return Container(
      width: 220,
      color: tokens.surface,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var index = 0; index < _navItems.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelected(index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: index == selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(index == selected ? _navItems[index].$2 : _navItems[index].$1, size: 20, color: index == selected ? const Color(0xFFE6EDF0) : tokens.mutedText),
                  const SizedBox(width: 12),
                  Text(_navItems[index].$3, style: TextStyle(fontSize: 14, fontWeight: index == selected ? FontWeight.w700 : FontWeight.w500, color: index == selected ? const Color(0xFFE6EDF0) : tokens.mutedText)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

const List<(IconData, IconData, String)> _navItems = [
  (Icons.dashboard_outlined, Icons.dashboard, '总览'),
  (Icons.auto_awesome_outlined, Icons.auto_awesome, 'AI'),
  (Icons.article_outlined, Icons.article, '日志'),
  (Icons.person_outline, Icons.person, '角色'),
  (Icons.settings_outlined, Icons.settings, '设置'),
  (Icons.forum_outlined, Icons.forum, '主动回复'),
];

/// 状态卡右上角的小胶囊按钮，避免悬浮按钮压住下面的卡片。
class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: 0.18),
        shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.4))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
            ]),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.tone});
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tone.withValues(alpha: 0.35)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: tone)),
      );
}

/// One address row inside the public IP card. Long addresses get their own line so the
/// copy button keeps a stable position on narrow screens.
class _IpLine extends StatelessWidget {
  const _IpLine({required this.label, required this.value, required this.hidden, required this.onCopy});
  final String label;
  final String value;
  final bool hidden;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final missing = value == '未检测' || value == '无法获取';
    final shown = hidden && !missing ? '••••••••' : value;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      SizedBox(width: 52, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
      Expanded(child: SelectableText(shown, style: TextStyle(fontFamily: missing ? null : 'monospace'))),
      if (!hidden && !missing) IconButton(tooltip: '复制 $label', onPressed: () => onCopy(value), icon: const Icon(Icons.copy, size: 18)),
    ]);
  }
}

class _CommandCopyRow extends StatelessWidget {
  const _CommandCopyRow({required this.command, required this.description});
  final String command;
  final String description;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(command, style: const TextStyle(fontFamily: 'monospace')),
      Text(description, style: Theme.of(context).textTheme.bodySmall),
    ])),
    IconButton(tooltip: '复制 $command', onPressed: () async { await Clipboard.setData(ClipboardData(text: command)); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制 $command'))); }, icon: const Icon(Icons.copy, size: 18)),
  ]));
}

/// QQ 侧可用的聊天指令，说明取自 dsh-qqbot 的指令注册表（name + description）。
const List<(String, String)> _chatCommands = [
  ('/new', '开一个新会话，清空当前聊天上下文（也可用 /reset、/clear）'),
  ('/compact', '把旧对话压缩成摘要，保留上下文又节省 token'),
  ('/preset', '不带参数时列出所有角色卡 ID'),
  ('/preset <角色ID>', '切换这个会话使用的角色卡，下一条消息生效'),
  ('/model', '查看当前模型；加 /provider/model 可切换模型'),
  ('/bot-status', '查看当前会话状态：模型、角色卡和上下文'),
  ('/bot-ping', '测一下机器人到 QQ 的连接延迟'),
  ('/bot-help', '列出全部可用指令'),
  ('/stop', '中止正在生成的回复'),
];

class _LogPage extends StatefulWidget {
  const _LogPage({required this.logs, required this.onClear, required this.bridge});
  final List<RuntimeLogEntry> logs;
  final Future<void> Function() onClear;
  final RuntimeBridge bridge;
  @override State<_LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<_LogPage> {
  LogLevel? level;
  String? module;
  final search = TextEditingController();
  List<RuntimeLogEntry> filtered = const [];
  bool filtering = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  /// 只在日志里实际出现过的模块，避免让用户猜模块名。
  List<String> _moduleOptions() {
    final names = widget.logs.map((entry) => entry.module).toSet().toList()..sort();
    return names;
  }
  @override
  void initState() {
    super.initState();
    _applyFilter();
  }
  @override
  void didUpdateWidget(covariant _LogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyFilter();
  }
  Future<void> _applyFilter() async {
    if (mounted) setState(() => filtering = true);
    final snapshot = List<RuntimeLogEntry>.from(widget.logs);
    // 清空日志或换了筛选后，选中的模块可能已经不存在，此时回退到“全部模块”。
    final selected = _moduleOptions().contains(module) ? module : null;
    final indexes = await filterLogIndexesInBackground(snapshot.map((entry) => <String, Object?>{
      'level': entry.level.name,
      'module': entry.module,
    }).toList(), level?.name, selected ?? '');
    final keyword = search.text.trim().toLowerCase();
    if (!mounted) return;
    setState(() {
      filtered = indexes
          .map((index) => snapshot[index])
          .where((entry) => keyword.isEmpty || entry.message.toLowerCase().contains(keyword) || entry.module.toLowerCase().contains(keyword))
          .toList()
          .reversed
          .toList();
      filtering = false;
    });
  }
  String _redacted(String value) => value
      .replaceAll(RegExp(r'(bearer\s+|api[_-]?key\s*[:=]\s*|app[_-]?secret\s*[:=]\s*|authorization\s*[:=]\s*|secret\s*[:=]\s*|token\s*[:=]\s*)[^\s,;]+', caseSensitive: false), r'\1[REDACTED]')
      .replaceAll(RegExp(r'("(?:api[_-]?key|app[_-]?secret|token|authorization|bearer)"\s*:\s*")[^"]*(")', caseSensitive: false), r'\1[REDACTED]\2');
  /// 诊断包要能独立说明“哪台设备、哪个版本、启动到哪一步”，否则光有日志也对不上。
  Future<void> _export() async {
    final info = await widget.bridge.appInfo();
    final header = [
      'QQ-bot-CP 运行诊断',
      '应用：${info['versionName'] ?? '?'} (${info['versionCode'] ?? '?'}) · ${info['abi'] ?? '?'}',
      '导出时间：${DateTime.now().toIso8601String()}',
      '日志条数：${widget.logs.length}',
      '',
    ].join('\n');
    final body = widget.logs.map((entry) => '${entry.time.toIso8601String()} [${entry.level.name}] ${entry.module} ${entry.errorCode == null ? '' : '[${entry.errorCode}] '}${_redacted(entry.message)}').join('\n');
    await Clipboard.setData(ClipboardData(text: '$header$body'));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制诊断信息')));
  }
  /// Clearing is destructive and cannot be undone from the page, so ask once up front.
  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('清空日志'),
      content: const Text('将删除这台设备上保存的全部运行日志，清空后无法恢复。'),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('清空'))],
    ));
    if (confirmed != true) return;
    await widget.onClear();
    if (mounted) await _applyFilter();
  }
  Color _levelColor(BuildContext context, LogLevel value) => switch (value) {
    LogLevel.error => AppThemeTokens.of(context).error,
    LogLevel.warn => AppThemeTokens.of(context).warning,
    LogLevel.info => AppThemeTokens.of(context).success,
  };
  IconData _levelIcon(LogLevel value) => switch (value) {
    LogLevel.error => Icons.error,
    LogLevel.warn => Icons.warning_amber,
    LogLevel.info => Icons.info,
  };
  @override
  Widget build(BuildContext context) {
    final tokens = AppSurfaceTokens.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
        child: Row(children: [
          Expanded(child: DropdownButtonFormField<LogLevel?>(initialValue: level, decoration: const InputDecoration(labelText: '级别'), items: const [DropdownMenuItem<LogLevel?>(value: null, child: Text('全部')), DropdownMenuItem(value: LogLevel.info, child: Text('信息')), DropdownMenuItem(value: LogLevel.warn, child: Text('警告')), DropdownMenuItem(value: LogLevel.error, child: Text('错误'))], onChanged: (value) { setState(() => level = value); _applyFilter(); })),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<String?>(key: ValueKey('module-${module ?? 'all'}-${_moduleOptions().length}'), initialValue: _moduleOptions().contains(module) ? module : null, decoration: const InputDecoration(labelText: '模块'), items: [const DropdownMenuItem<String?>(value: null, child: Text('全部模块')), for (final name in _moduleOptions()) DropdownMenuItem<String?>(value: name, child: Text(name))], onChanged: (value) { setState(() => module = value); _applyFilter(); })),
          IconButton(tooltip: '清空日志', onPressed: widget.logs.isEmpty ? null : _confirmClear, icon: const Icon(Icons.delete_outline, size: 20)),
          IconButton(tooltip: '复制诊断信息', onPressed: widget.logs.isEmpty ? null : _export, icon: const Icon(Icons.ios_share, size: 20)),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: TextField(controller: search, onChanged: (_) => _applyFilter(), decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: '搜索日志内容或模块'))),
      Expanded(
        child: filtering
            ? const Center(child: CircularProgressIndicator())
            : filtered.isEmpty
                ? Center(child: Text('暂无匹配的 Runtime 日志', style: TextStyle(color: tokens.mutedText)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final entry = filtered[index];
                      final presentation = presentLog(entry);
                      final color = presentation.muted ? tokens.mutedText : _levelColor(context, presentation.level);
                      final meta = '${formatLogTime(entry.time)} · ${presentation.level.name}${presentation.muted ? '（已忽略）' : ''} · ${entry.module}${entry.errorCode == null ? '' : ' · ${entry.errorCode}'}${entry.elapsedMs == null ? '' : ' · ${entry.elapsedMs} ms'}${entry.runId == null ? '' : ' · run ${entry.runId}'}';
                      return Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardTheme.color,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: tokens.outline),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Icon(presentation.muted ? Icons.remove_circle_outline : _levelIcon(presentation.level), size: 13, color: color),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(presentation.message, style: TextStyle(fontSize: 14.5, height: 1.35, fontWeight: FontWeight.w600, color: color)),
                            const SizedBox(height: 4),
                            Text(meta, style: TextStyle(fontSize: 11.5, color: tokens.mutedText)),
                            if (presentation.detail != null) Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text('原始信息：${presentation.detail!}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: tokens.mutedText, fontFamily: 'monospace')),
                            ),
                          ])),
                        ]),
                      );
                    },
                  ),
      ),
    ]);
  }
}

class _ConfigPage extends StatefulWidget {
  const _ConfigPage({required this.bridge, this.onSaved});
  final RuntimeBridge bridge;
  final VoidCallback? onSaved;
  @override State<_ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<_ConfigPage> {
  static const protocols = <String>['', 'openai-compatible', 'openai-responses', 'anthropic-messages'];
  final protocol = TextEditingController();
  final model = TextEditingController();
  final baseUrl = TextEditingController();
  final appId = TextEditingController();
  final secret = TextEditingController();
  final apiKey = TextEditingController();
  bool loading = true;
  bool saving = false;
  List<AiConfigHistory> history = const [];
  int? selectedHistory;
  EndpointTestResult? endpointTest;
  bool testingEndpoint = false;
  EndpointTestResult? requestTest;
  bool testingRequest = false;
  Map<String, Object?>? qqTest;
  bool testingQq = false;
  bool qqConfigured = false;
  bool llmConfigured = false;
  String thinkingLevel = 'medium';
  List<String> modelOptions = const [];
  bool loadingModels = false;
  bool endpointValidated = false;
  String testedConnection = '';
  String savedProtocol = '';
  String savedModel = '';
  String savedBaseUrl = '';
  String savedThinkingLevel = 'medium';
  String savedAppId = '';
  static const _savedMask = '••••••••';

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { for (final c in [protocol, model, baseUrl, appId, secret, apiKey]) { c.dispose(); } super.dispose(); }
  Future<void> _load() async {
    try {
      final c = await widget.bridge.config();
      protocol.text = c.protocol; model.text = c.model; baseUrl.text = c.baseUrl; appId.text = c.appId; thinkingLevel = c.thinkingLevel;
      savedProtocol = c.protocol; savedModel = c.model; savedBaseUrl = c.baseUrl; savedAppId = c.appId; savedThinkingLevel = c.thinkingLevel;
      qqConfigured = c.qqConfigured; llmConfigured = c.llmConfigured;
      secret.text = qqConfigured ? _savedMask : ''; apiKey.text = llmConfigured ? _savedMask : '';
      history = await widget.bridge.configHistory();
    }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> _restoreSavedConfig() async {
    if (mounted) setState(() { loading = true; endpointValidated = false; testedConnection = ''; endpointTest = null; requestTest = null; });
    await _load();
  }
  Future<void> _save() async {
    final url = baseUrl.text.trim();
    if (url.isNotEmpty) {
      final parsed = Uri.tryParse(url);
      if (parsed == null || (parsed.scheme != 'http' && parsed.scheme != 'https') || parsed.host.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Base URL 必须是有效的 HTTP/HTTPS 地址')));
        return;
      }
    }
    setState(() => saving = true);
    try {
      final enteredSecret = _credentialValue(secret);
      final enteredApiKey = _credentialValue(apiKey);
      await widget.bridge.saveConfig(protocol: protocol.text.trim(), model: model.text.trim(), baseUrl: baseUrl.text.trim(), thinkingLevel: thinkingLevel, appId: appId.text.trim(), secret: enteredSecret, apiKey: enteredApiKey);
      final nextHistory = await widget.bridge.configHistory();
      if (secret.text.isNotEmpty) secret.text = _savedMask;
      if (apiKey.text.isNotEmpty) apiKey.text = _savedMask;
      qqConfigured = qqConfigured || enteredSecret.isNotEmpty;
      llmConfigured = llmConfigured || enteredApiKey.isNotEmpty;
      savedProtocol = protocol.text.trim(); savedModel = model.text.trim(); savedBaseUrl = baseUrl.text.trim(); savedAppId = appId.text.trim(); savedThinkingLevel = thinkingLevel;
      if (mounted) setState(() { history = nextHistory; selectedHistory = nextHistory.isEmpty ? null : 0; });
      widget.onSaved?.call();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('配置已保存到 Android Keystore')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _testEndpoint() async {
    setState(() { testingEndpoint = true; endpointValidated = false; testedConnection = ''; requestTest = null; });
    try {
      final result = await widget.bridge.testLlmConnection(baseUrl.text.trim(), apiKey: _credentialValue(apiKey));
      if (mounted) setState(() { testingEndpoint = false; endpointTest = result; endpointValidated = result.ok; testedConnection = result.ok ? _connectionFingerprint : ''; });
    } catch (error) {
      if (mounted) setState(() { testingEndpoint = false; endpointTest = EndpointTestResult(ok: false, stage: '测试', message: '$error'); });
    }
  }
  Future<void> _testRequest() async {
    if (protocol.text.trim().isEmpty || baseUrl.text.trim().isEmpty || model.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先填写接口类型、Base URL 和模型名称')));
      return;
    }
    setState(() { testingRequest = true; requestTest = null; });
    try {
      final result = await widget.bridge.testLlmRequest(protocol: protocol.text.trim(), baseUrl: baseUrl.text.trim(), model: model.text.trim(), apiKey: _credentialValue(apiKey));
      if (mounted) setState(() { testingRequest = false; requestTest = result; });
    } catch (error) {
      if (mounted) setState(() { testingRequest = false; requestTest = EndpointTestResult(ok: false, stage: '测试请求', message: '$error'); });
    }
  }

  Future<void> _testQq() async {
    setState(() { testingQq = true; qqTest = null; });
    Map<String, Object?> result;
    try {
      result = await widget.bridge.testQqConnection(appId: appId.text.trim(), secret: _credentialValue(secret));
    } catch (error) {
      result = {'ok': false, 'stage': '测试', 'message': '$error'};
    }
    if (mounted) setState(() { testingQq = false; qqTest = result; });
  }
  Future<void> _copyEndpointDiagnostic() async {
    final result = endpointTest;
    if (result == null) return;
    final details = [
      '接口测试诊断',
      '阶段：${result.stage}',
      if (result.statusCode != null) 'HTTP：${result.statusCode}',
      if (result.elapsedMs != null) '耗时：${result.elapsedMs} ms',
      '结果：${result.message}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: details));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制接口诊断（未包含 API Key）')));
  }
  Future<void> _fetchModels() async {
    if (baseUrl.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先填写 Base URL'))); return; }
    setState(() => loadingModels = true);
    try {
      final models = await widget.bridge.fetchModels(baseUrl.text.trim(), apiKey: _credentialValue(apiKey));
      if (mounted) setState(() { modelOptions = models; if (models.contains(model.text.trim())) model.text = model.text.trim(); if (models.isNotEmpty) { endpointValidated = true; testedConnection = _connectionFingerprint; } });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(models.isEmpty ? '接口没有返回可用模型' : '已拉取 ${models.length} 个模型')));
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('拉取模型失败：$error'))); }
    finally { if (mounted) setState(() => loadingModels = false); }
  }
  @override
  Widget build(BuildContext context) {
    final tokens = AppSurfaceTokens.of(context);
    return _pageBody(context, [
      if (history.isNotEmpty) ...[
        AppCard(
          title: '历史配置',
          trailing: IconButton(tooltip: '清除历史配置', onPressed: _clearHistory, icon: const Icon(Icons.delete_outline, size: 18)),
          child: DropdownButtonFormField<int>(
            key: ValueKey('history-$selectedHistory-${history.length}'),
            initialValue: selectedHistory,
            items: [const DropdownMenuItem<int>(value: null, child: Text('不使用历史配置')), ...history.asMap().entries.map((entry) => DropdownMenuItem<int>(value: entry.key, child: Text(entry.value.label, overflow: TextOverflow.ellipsis)))],
            onChanged: (value) { if (value == null) return; final item = history[value]; setState(() { selectedHistory = value; protocol.text = item.protocol; model.text = item.model; baseUrl.text = item.baseUrl; }); },
          ),
        ),
        const SizedBox(height: 12),
      ],
      AppCard(
        title: 'AI 接口',
        child: Column(children: [
          DropdownButtonFormField<String>(key: ValueKey('protocol-${protocol.text}'), initialValue: protocols.contains(protocol.text) ? protocol.text : '', decoration: const InputDecoration(labelText: '接口类型'), items: protocols.map((item) => DropdownMenuItem<String>(value: item, child: Text(item.isEmpty ? '请选择接口类型' : item))).toList(), onChanged: (value) { if (value != null) setState(() => protocol.text = value); }),
          const SizedBox(height: 12),
          _field(baseUrl, 'Base URL', 'https://api.example.com/v1', onChanged: (_) => setState(() { requestTest = null; })),
          _credentialField(apiKey, 'AI API Key', llmConfigured ? '已保存；点击后可替换' : '未保存，请填写', onChanged: (_) => setState(() { requestTest = null; })),
          SizedBox(width: double.infinity, child: FilledButton.tonalIcon(onPressed: testingEndpoint || baseUrl.text.trim().isEmpty ? null : _testEndpoint, icon: testingEndpoint ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.network_check, size: 18), label: const Text('测试接口'))),
          if (endpointTest != null) Padding(padding: const EdgeInsets.only(top: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Text('${endpointTest!.ok ? '✓' : '✕'} ${endpointTest!.stage}：${endpointTest!.message}${endpointTest!.statusCode == null ? '' : '（HTTP ${endpointTest!.statusCode}）'}${endpointTest!.elapsedMs == null ? '' : ' · ${endpointTest!.elapsedMs} ms'}', style: TextStyle(fontSize: 12.5, color: endpointTest!.ok ? AppThemeTokens.of(context).success : AppThemeTokens.of(context).warning))), if (!endpointTest!.ok) TextButton.icon(onPressed: _copyEndpointDiagnostic, icon: const Icon(Icons.copy, size: 14), label: const Text('复制诊断'))])),
          const SizedBox(height: 16),
          Divider(height: 1, color: tokens.outline),
          const SizedBox(height: 16),
          if (modelOptions.isNotEmpty) ...[
            DropdownButtonFormField<String>(key: ValueKey('models-${modelOptions.length}-${model.text}'), initialValue: modelOptions.contains(model.text) ? model.text : null, decoration: const InputDecoration(labelText: '已拉取的模型'), items: modelOptions.map((item) => DropdownMenuItem(value: item, child: Text(item, overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) { if (value != null) setState(() => model.text = value); }),
            const SizedBox(height: 12),
          ],
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _field(model, '模型名称', 'deepseek-chat', onChanged: (_) => setState(() { requestTest = null; }))),
            const SizedBox(width: 10),
            Padding(padding: const EdgeInsets.only(top: 4), child: OutlinedButton(onPressed: loadingModels || baseUrl.text.trim().isEmpty ? null : _fetchModels, child: loadingModels ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('拉取模型'))),
          ]),
          DropdownButtonFormField<String>(key: ValueKey('thinking-$thinkingLevel'), initialValue: const ['off', 'low', 'medium', 'high'].contains(thinkingLevel) ? thinkingLevel : 'medium', decoration: const InputDecoration(labelText: '思考程度'), items: const [DropdownMenuItem(value: 'off', child: Text('关闭')), DropdownMenuItem(value: 'low', child: Text('低')), DropdownMenuItem(value: 'medium', child: Text('中')), DropdownMenuItem(value: 'high', child: Text('高'))], onChanged: (value) { if (value != null) setState(() => thinkingLevel = value); }),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.tonalIcon(onPressed: testingRequest || model.text.trim().isEmpty ? null : _testRequest, icon: testingRequest ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_circle_outline, size: 18), label: const Text('测试请求（发送一条 ping）'))),
          if (requestTest != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${requestTest!.ok ? '✓' : '✕'} ${requestTest!.stage}：${requestTest!.message}${requestTest!.statusCode == null ? '' : '（HTTP ${requestTest!.statusCode}）'}${requestTest!.elapsedMs == null ? '' : ' · ${requestTest!.elapsedMs} ms'}', style: TextStyle(fontSize: 12.5, color: requestTest!.ok ? AppThemeTokens.of(context).success : AppThemeTokens.of(context).warning))),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        child: Row(children: [
          Icon(_connectionReady ? Icons.verified_outlined : Icons.info_outline, size: 16, color: _connectionReady ? AppThemeTokens.of(context).success : tokens.mutedText),
          const SizedBox(width: 8),
          Expanded(child: Text(_connectionReady ? '接口认证和测试请求均已通过' : '尚未通过完整测试，可直接保存', style: TextStyle(fontSize: 12.5, color: tokens.mutedText))),
          if (_hasUnsavedChanges) TextButton(onPressed: loading ? null : _restoreSavedConfig, child: const Text('恢复已保存')),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        title: 'QQ 官方机器人',
        child: Column(children: [
          _field(appId, 'QQ 官方机器人 AppID', '留空表示未配置', onChanged: (_) => setState(() {})),
          _credentialField(secret, 'QQ AppSecret', qqConfigured ? '已保存；点击后可替换' : '未保存，请填写', onChanged: (_) => setState(() {})),
          SizedBox(width: double.infinity, child: FilledButton.tonalIcon(onPressed: loading || testingQq ? null : _testQq, icon: testingQq ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link, size: 18), label: const Text('测试 QQ 连接'))),
          if (qqTest != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${qqTest!['ok'] == true ? '✓' : '✕'} ${qqTest!['stage'] ?? ''}：${qqTest!['message'] ?? ''}${qqTest!['statusCode'] == null ? '' : '（HTTP ${qqTest!['statusCode']}）'}${qqTest!['elapsedMs'] == null ? '' : ' · ${qqTest!['elapsedMs']} ms'}', style: TextStyle(fontSize: 12.5, color: qqTest!['ok'] == true ? AppThemeTokens.of(context).success : AppThemeTokens.of(context).warning))),
        ]),
      ),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: !loading && !saving && !testingEndpoint && !testingRequest && !testingQq ? _save : null, icon: const Icon(Icons.save_outlined, size: 18), label: Text(saving ? '正在保存…' : '保存配置'))),
    ]);
  }

  String _credentialValue(TextEditingController controller) => controller.text == _savedMask ? '' : controller.text;

  Widget _credentialField(TextEditingController controller, String label, String hint, {ValueChanged<String>? onChanged}) => _field(controller, label, hint, obscure: true, onChanged: onChanged, onTap: () { if (controller.text == _savedMask) controller.clear(); });

  String get _connectionFingerprint {
    final key = _credentialValue(apiKey);
    return '${protocol.text.trim()}|${baseUrl.text.trim().replaceAll(RegExp(r'/+$'), '')}|${key.isEmpty && llmConfigured ? '<saved>' : key}';
  }

  bool get _connectionReady => endpointValidated && testedConnection == _connectionFingerprint && requestTest?.ok == true;
  bool get _hasUnsavedChanges => hasUnsavedConfigChanges(
        current: LlmConfigDraft(protocol: protocol.text, model: model.text, baseUrl: baseUrl.text, thinkingLevel: thinkingLevel, appId: appId.text, apiKey: apiKey.text, secret: secret.text),
        saved: LlmConfigDraft(protocol: savedProtocol, model: savedModel, baseUrl: savedBaseUrl, thinkingLevel: savedThinkingLevel, appId: savedAppId),
      );

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('清除历史配置？'), content: const Text('只会删除接口类型、模型和 Base URL 历史，不会删除已保存的密钥。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清除'))])) ?? false;
    if (!confirmed) return;
    await widget.bridge.deleteConfigHistory();
    if (mounted) setState(() { history = const []; selectedHistory = null; });
  }

  Widget _field(TextEditingController c, String label, String hint, {bool obscure = false, ValueChanged<String>? onChanged, VoidCallback? onTap}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: c, obscureText: obscure, onChanged: onChanged, onTap: onTap, decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder())));
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({required this.bridge, this.onThemeChanged});
  final RuntimeBridge bridge;
  final ValueChanged<ThemeSettings>? onThemeChanged;
  @override State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  Map<String, String> info = const {};
  bool installing = false;
  final updateUrl = TextEditingController();
  UpdateManifest? manifest;
  ThemeMode themeMode = ThemeMode.dark;
  Color seedColor = const Color(0xff8290ff);
  double cardRadius = 16;
  double cardOpacity = 1;
  bool tintedBackground = false;
  List<ThemeSettings> recentThemes = const [];
  List<Map<String, Object?>> backups = const [];
  bool checkingUpdate = false;
  ReleaseCheckResult? releaseCheck;
  bool downloading = false;
  double downloadProgress = 0;
  bool downloadPaused = false;
  UpdateDownloadController? downloadController;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { updateUrl.dispose(); super.dispose(); }
  double _snapOpacity(double value) => [0.7, 0.85, 1.0].reduce((a, b) => (value - a).abs() < (value - b).abs() ? a : b);
  Future<void> _load() async { final value = await widget.bridge.appInfo(); final saved = await ThemeBridge.load(); final savedBackups = await widget.bridge.backups(); if (mounted) setState(() { info = value; backups = savedBackups; updateUrl.text = defaultUpdateManifestUrl; themeMode = saved.mode; seedColor = saved.seedColor; cardRadius = saved.cardRadius; cardOpacity = _snapOpacity(saved.cardOpacity); tintedBackground = saved.tintedBackground; }); }
  void _applyTheme() { final settings = ThemeSettings(mode: themeMode, seedColor: seedColor, cardRadius: cardRadius, cardOpacity: cardOpacity, tintedBackground: tintedBackground); widget.onThemeChanged?.call(settings); setState(() { recentThemes = [settings, ...recentThemes.where((item) => item.mode != settings.mode || item.seedColor != settings.seedColor || item.cardRadius != settings.cardRadius).take(4)]; }); }
  void _resetTheme() { setState(() { themeMode = ThemeMode.dark; seedColor = const Color(0xff8290ff); cardRadius = 16; cardOpacity = 1; tintedBackground = false; }); _applyTheme(); }
  Future<void> _install() async {
    setState(() => installing = true);
    final result = await widget.bridge.pickAndInstallApk();
    if (!mounted) return;
    setState(() => installing = false);
    final status = result['status'];
    final reason = result['reason'];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status == 'permission_required' ? '请先允许本应用安装未知来源应用' : status == 'installer_opened' ? '已打开系统安装器' : status == 'cancelled' ? '已取消选择' : status == 'rejected' ? '已拒绝更新：$reason' : '更新操作：$status')));
  }
  /// 直接问 GitHub 的 latest release，并和已安装版本比较；只有确实更新时才给下载入口。
  Future<void> _checkUpdate() async {
    setState(() => checkingUpdate = true);
    try {
      final result = await const ReleaseChecker().run(info['versionName'] ?? '');
      if (!mounted) return;
      setState(() {
        releaseCheck = result;
        manifest = result.manifest;
        downloadController = null;
        downloadPaused = false;
        downloadProgress = 0;
        downloading = false;
      });
    } finally {
      if (mounted) setState(() => checkingUpdate = false);
    }
  }

  /// 已是最新时也要给出可读的结论，而不是把清单当更新展示。
  String _checkSummary(ReleaseCheckResult result) {
    final published = result.publishedAt;
    final when = published == null ? '' : ' · 最新版发布于 ${published.toLocal().toString().substring(0, 10)}';
    if (result.failed) return '${result.error}';
    if (result.hasUpdate) return '当前 ${result.installed} → ${result.latest}$when';
    return '当前 ${result.installed} 已经是最新版本$when';
  }
  Future<void> _downloadAndInstall() async {
    final value = manifest;
    if (value == null) return;
    setState(() { downloading = true; downloadPaused = false; });
    try {
      final path = await widget.bridge.updateCachePath();
      downloadController ??= UpdateDownloadController(value, path, (received, total) { if (mounted) setState(() => downloadProgress = total > 0 ? received / total : 0); });
      await downloadController!.start();
      if (downloadController!.paused) { if (mounted) setState(() { downloading = false; downloadPaused = true; }); return; }
      if (downloadController!.cancelled) { if (mounted) setState(() { downloading = false; downloadPaused = false; }); return; }
      final result = await widget.bridge.verifyAndInstallUpdate(path: path, sha256: value.sha256);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['status'] == 'installer_opened' ? '下载校验成功，已打开系统安装器' : '更新被拒绝：${result['reason'] ?? '未知原因'}')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载更新失败：$error')));
    } finally { if (mounted && !downloadPaused) setState(() => downloading = false); }
  }
  Future<void> _exportBackup() async { final result = await widget.bridge.exportBackup(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['status'] == 'exported' ? '脱敏备份已导出' : '备份操作：${result['status']}'))); }
  Future<void> _importBackup() async { final result = await widget.bridge.importBackup(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['status'] == 'imported' ? '备份已恢复，重启应用后完全生效' : result['status'] == 'rejected' ? '备份被拒绝：${result['reason']}' : '备份操作：${result['status']}'))); }
  Future<void> _restoreBackup(Map<String, Object?> backup) async { final name = '${backup['name'] ?? '备份'}'; final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('恢复自动备份？'), content: Text('将先创建当前状态的安全备份，再恢复 $name。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('恢复'))])) ?? false; if (!ok) return; final result = await widget.bridge.restoreBackupFile('${backup['path'] ?? ''}'); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['status'] == 'restored' ? '备份已恢复，请重启 Runtime' : '恢复失败：${result['reason'] ?? '未知错误'}'))); }
  Future<void> _clearData(String kind, String title, String message) async { final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(title), content: Text(message), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定清除'))])) ?? false; if (!ok) return; await widget.bridge.clearData(kind); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('清理完成'))); }
  void _pauseDownload() { downloadController?.pause(); if (mounted) setState(() { downloading = false; downloadPaused = true; }); }
  void _cancelDownload() { downloadController?.cancel(); if (mounted) setState(() { downloading = false; downloadPaused = false; }); }
  @override
  Widget build(BuildContext context) {
    return _pageBody(context, [
      AppCard(
        title: '外观',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('主色', style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, children: [
            for (final color in _seedColors) _SeedDot(color: color, selected: color == seedColor, onTap: () { setState(() => seedColor = color); _applyTheme(); }),
          ]),
          const SizedBox(height: 16),
          const Text('卡片圆角', style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 8),
          SegmentedButton<double>(showSelectedIcon: false, segments: const [ButtonSegment(value: 10.0, label: Text('小')), ButtonSegment(value: 16.0, label: Text('中')), ButtonSegment(value: 22.0, label: Text('大'))], selected: {cardRadius}, onSelectionChanged: (value) { setState(() => cardRadius = value.first); _applyTheme(); }),
          const SizedBox(height: 16),
          const Text('卡片透明度', style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 8),
          SegmentedButton<double>(showSelectedIcon: false, segments: const [ButtonSegment(value: 0.7, label: Text('高透明')), ButtonSegment(value: 0.85, label: Text('半透明')), ButtonSegment(value: 1.0, label: Text('不透明'))], selected: {cardOpacity}, onSelectionChanged: (value) { setState(() => cardOpacity = value.first); _applyTheme(); }),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('柔和背景', style: TextStyle(fontSize: 13.5)), value: tintedBackground, onChanged: (value) { setState(() => tintedBackground = value); _applyTheme(); }),
          const SizedBox(height: 4),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _resetTheme, icon: const Icon(Icons.restart_alt, size: 18), label: const Text('恢复默认外观'))),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(child: Column(children: [
        _kvRow(context, '应用版本', '${info['versionName'] ?? '读取中'} (${info['versionCode'] ?? '-'})'),
        Divider(height: 18, color: AppSurfaceTokens.of(context).outline),
        _kvRow(context, '运行 ABI', info['abi'] ?? '读取中'),
      ])),
      const SizedBox(height: 12),
      AppCard(
        title: '后台运行',
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () async { try { await widget.bridge.openBatteryOptimizationSettings(); } catch (error) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法打开电池设置：$error'))); } }, icon: const Icon(Icons.battery_saver, size: 18), label: const Text('电池优化'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: () async { try { await widget.bridge.openNotificationSettings(); } catch (error) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法打开通知设置：$error'))); } }, icon: const Icon(Icons.notifications_outlined, size: 18), label: const Text('通知设置'))),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        title: '应用更新',
        trailing: IconButton(tooltip: '检查在线更新', onPressed: checkingUpdate ? null : _checkUpdate, icon: checkingUpdate ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, size: 18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (releaseCheck == null) Text('还没有检查过更新', style: TextStyle(fontSize: 12.5, color: AppSurfaceTokens.of(context).mutedText))
          else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(releaseCheck!.failed ? Icons.cloud_off : releaseCheck!.hasUpdate ? Icons.system_update : Icons.verified_outlined, size: 18, color: releaseCheck!.failed ? AppThemeTokens.of(context).warning : releaseCheck!.hasUpdate ? AppThemeTokens.of(context).warning : AppThemeTokens.of(context).success),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(releaseCheck!.failed ? '检查更新失败' : releaseCheck!.hasUpdate ? '发现新版本 ${releaseCheck!.latest}' : '已是最新版本', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(_checkSummary(releaseCheck!), style: TextStyle(fontSize: 12, color: AppSurfaceTokens.of(context).mutedText)),
            ])),
          ]),
          if (manifest != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: AppSurfaceTokens.of(context).outline),
            const SizedBox(height: 12),
            Text('${manifest!.versionName} · ${manifest!.abi} · ${manifest!.sizeLabel}', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Text(manifest!.releaseNotes, style: TextStyle(fontSize: 12, color: AppSurfaceTokens.of(context).mutedText)),
            const SizedBox(height: 10),
            if (downloading) ...[
              LinearProgressIndicator(value: downloadProgress),
              Row(children: [
                Expanded(child: Text('下载中 ${(downloadProgress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12.5))),
                IconButton(tooltip: '暂停', onPressed: _pauseDownload, icon: const Icon(Icons.pause)),
                IconButton(tooltip: '取消', onPressed: _cancelDownload, icon: const Icon(Icons.close)),
              ]),
            ] else
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: manifest!.apkUrl.isEmpty ? null : _downloadAndInstall, icon: Icon(downloadPaused ? Icons.play_arrow : Icons.download, size: 18), label: Text(downloadPaused ? '继续下载' : '下载并安装更新'))),
          ],
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: installing ? null : _install, icon: installing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.install_mobile, size: 18), label: const Text('从本地 APK 更新'))),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        title: '配置备份',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _exportBackup, icon: const Icon(Icons.upload_file, size: 18), label: const Text('导出备份'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: _importBackup, icon: const Icon(Icons.file_open, size: 18), label: const Text('导入备份'))),
          ]),
          if (backups.isEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('暂无自动备份', style: TextStyle(fontSize: 12.5, color: AppSurfaceTokens.of(context).mutedText)))
          else ...[
            const SizedBox(height: 6),
            for (final backup in backups)
              ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: const Icon(Icons.backup_outlined, size: 18), title: Text('${backup['name'] ?? '自动备份'}', style: const TextStyle(fontSize: 13)), subtitle: Text('${((backup['size'] as num?)?.toInt() ?? 0) ~/ 1024} KB', style: const TextStyle(fontSize: 11.5)), trailing: TextButton(onPressed: () => _restoreBackup(backup), child: const Text('恢复'))),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        title: '数据清理',
        child: Column(children: [
          _dangerRow(context, '清除日志', () => _clearData('logs', '清除 Runtime 日志？', '只删除输出日志，不影响配置和会话。')),
          _dangerRow(context, '清除会话', () => _clearData('sessions', '清除会话？', '会删除 Runtime 会话索引和上下文，不能恢复。')),
          _dangerRow(context, '清除全部配置', () => _clearData('all', '清除全部配置？', '将删除 AI/QQ 凭据、外观设置、默认角色卡和历史配置，操作不可恢复。')),
        ]),
      ),
      const SizedBox(height: 12),
      Material(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(cardRadius),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _TutorialPage())),
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(cardRadius), border: Border.all(color: AppSurfaceTokens.of(context).outline)),
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(children: [
              const Icon(Icons.menu_book_outlined, size: 20),
              const SizedBox(width: 12),
              const Expanded(child: Text('说明与教程', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              Icon(Icons.chevron_right, color: AppSurfaceTokens.of(context).mutedText),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _kvRow(BuildContext context, String label, String value) => Row(children: [
        SizedBox(width: 88, child: Text(label, style: TextStyle(fontSize: 13, color: AppSurfaceTokens.of(context).mutedText))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13.5))),
      ]);

  Widget _dangerRow(BuildContext context, String label, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            Icon(Icons.chevron_right, size: 18, color: AppSurfaceTokens.of(context).mutedText),
          ]),
        ),
      );

  static const List<Color> _seedColors = [Color(0xff0e7490), Color(0xff4f7cff), Color(0xffff8a65), Color(0xffb07cf0)];

}

class _RolePage extends StatefulWidget {
  const _RolePage({required this.bridge});
  final RuntimeBridge bridge;
  @override State<_RolePage> createState() => _RolePageState();
}

class _RolePageState extends State<_RolePage> {
  final roleId = TextEditingController();
  final roleName = TextEditingController();
  final rolePrompt = TextEditingController();
  final importJson = TextEditingController();
  List<RoleCard> roles = const [];
  String defaultId = '';
  String defaultName = '';
  bool loading = true;
  bool editingExisting = false;
  String editingId = '';
  Map<String, String> sessionOverrides = const {};
  @override
  void initState() { super.initState(); _load(); _loadSessionOverrides(); }
  @override
  void dispose() { roleId.dispose(); roleName.dispose(); rolePrompt.dispose(); importJson.dispose(); super.dispose(); }
  Future<void> _load() async {
    final values = await widget.bridge.roles();
    final role = await widget.bridge.defaultRole();
    final id = role['id'] ?? '';
    RoleCard? stored;
    for (final candidate in values) {
      if (candidate.id == id) { stored = candidate; break; }
    }
    if (mounted) {
      setState(() {
        roles = values;
        defaultId = id;
        defaultName = role['name'] ?? '';
        // 编辑框里放的是已保存的角色卡；editingId 必须同步，否则保存会被当成“ID 已存在”。
        editingExisting = stored != null;
        editingId = stored?.id ?? '';
        roleId.text = stored?.id ?? '';
        roleName.text = stored?.displayName ?? '';
        rolePrompt.text = stored?.prompt ?? '';
        loading = false;
      });
    } if (mounted && role['missing'] == 'true') ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('原默认角色已不存在，已回退为空角色；请重新设置默认角色。'))); }
  Widget _field(TextEditingController c, String label, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          enabled: !loading,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
        ),
      );

  Future<void> _loadSessionOverrides() async {
    try {
      final value = await widget.bridge.sessionPresetOverrides();
      if (mounted) setState(() => sessionOverrides = value);
    } catch (_) {
      // 只用于展示。
    }
  }
  Future<void> _clearSessionOverrides() async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('全部恢复默认角色？'), content: const Text('会清除所有会话用 /preset 设置的角色，并重启 Runtime（约十几秒内机器人不响应）。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('恢复并重启'))])) ?? false;
    if (!ok || !mounted) return;
    setState(() => loading = true);
    try {
      await widget.bridge.clearSessionPresetOverrides();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已恢复默认角色，Runtime 正在重启')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复失败：$e')));
    } finally {
      if (mounted) setState(() => loading = false);
      await _loadSessionOverrides();
    }
  }
  void _newRole() { setState(() { editingExisting = false; editingId = ''; roleId.clear(); roleName.clear(); rolePrompt.clear(); }); }
  void _edit(RoleCard role) { setState(() { editingExisting = true; editingId = role.id; roleId.text = role.id; roleName.text = role.displayName; rolePrompt.text = role.prompt; }); }
  RoleCard? _stored(String id) {
    for (final candidate in roles) {
      if (candidate.id == id) return candidate;
    }
    return null;
  }
  Future<bool> _confirmOverwrite(RoleCard role) async {
    final existing = _stored(role.id);
    if (existing == null || (existing.prompt == role.prompt && existing.displayName == role.displayName)) return true;
    return await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('确认覆盖角色？'), content: Text('“${existing.displayName}”（${role.id}）已存在，导入会覆盖它的提示词和显示名称。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('覆盖'))])) ?? false;
  }
  /// 默认角色在设置里另存了一份名称和提示词，保存默认角色时要一起更新。
  Future<void> _syncDefault(RoleCard role) async {
    if (role.id == defaultId) await widget.bridge.saveDefaultRole(id: role.id, name: role.displayName, prompt: role.prompt);
  }
  Future<void> _save() async { await _saveRole(); }
  Future<RoleCard?> _saveRole() async {
    try {
      final enteredId = roleId.text.trim();
      final id = enteredId.isNotEmpty ? enteredId : generateRoleId(roleName.text, roles.map((role) => role.id));
      if (roles.any((role) => role.id == id && role.id != editingId)) throw StateError('角色 ID 已存在，请换一个名称或在高级选项中修改 ID');
      final prompt = rolePrompt.text.trim();
      if (prompt.isEmpty) throw StateError('人格提示词不能为空');
      final name = roleName.text.trim().isEmpty ? id : roleName.text.trim();
      RoleCard? existing;
      for (final candidate in roles) {
        if (candidate.id == id) {
          existing = candidate;
          break;
        }
      }
      if (existing != null && (existing.prompt != prompt || existing.displayName != name)) {
        final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('确认覆盖角色？'), content: Text('“$name”已存在，保存会覆盖它的提示词和显示名称。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('覆盖'))])) ?? false;
        if (!confirmed) return null;
      }
      final role = RoleCard(id: id, displayName: name, prompt: prompt);
      await widget.bridge.saveRoleCard(role);
      await _syncDefault(role);
      await _load();
      _edit(role);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('角色卡已保存：$name（$id），下一条消息生效')));
      return role;
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$error'))); return null; }
  }
  /// 编辑框内容和已保存的不一样时先保存，保证设置里的默认角色和 Runtime 读到的文件一致。
  Future<void> _setDefault() async {
    final id = roleId.text.trim();
    if (id.isEmpty) return;
    var role = _stored(id);
    final name = roleName.text.trim().isEmpty ? id : roleName.text.trim();
    if (role == null || role.prompt != rolePrompt.text.trim() || role.displayName != name) {
      role = await _saveRole();
      if (role == null) return;
    }
    await _setRoleDefault(role);
  }
  Future<void> _setRoleDefault(RoleCard role) async { await widget.bridge.saveDefaultRole(id: role.id, name: role.displayName, prompt: role.prompt); if (mounted) setState(() { defaultId = role.id; defaultName = role.displayName; editingExisting = true; editingId = role.id; roleId.text = role.id; roleName.text = role.displayName; rolePrompt.text = role.prompt; }); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已将“${role.displayName}”设为默认角色'))); }
  Future<void> _delete() async { final id = roleId.text.trim(); if (id.isEmpty) return; final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('确认删除角色？'), content: Text('将删除 $id，且无法恢复。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除'))])) ?? false; if (!ok) return; await widget.bridge.deleteRoleCard(id); _newRole(); await _load(); }
  Future<void> _import() async { try { final decoded = await decodeJsonInBackground(importJson.text); if (decoded is! Map) throw const FormatException('JSON 必须是对象'); final role = RoleCard.fromMap(decoded); if (!await _confirmOverwrite(role)) return; await widget.bridge.saveRoleCard(role); await _syncDefault(role); importJson.clear(); await _load(); _edit(role); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('角色卡已导入'))); } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$error'))); } }
  Future<void> _export() async { final role = RoleCard(id: roleId.text.trim(), displayName: roleName.text.trim(), prompt: rolePrompt.text); final result = await widget.bridge.exportRoleCard(jsonEncode(role.toMap())); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['status'] == 'exported' ? '角色卡已导出' : '导出操作：${result['status']}'))); }
  Future<void> _importFile() async { try { final text = await widget.bridge.importRoleCard(); if (text == null) return; final decoded = await decodeJsonInBackground(text); if (decoded is! Map) throw const FormatException('JSON 必须是对象'); final role = RoleCard.fromMap(decoded); if (!await _confirmOverwrite(role)) return; await widget.bridge.saveRoleCard(role); await _syncDefault(role); await _load(); _edit(role); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('角色卡文件已导入'))); } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$error'))); } }
  @override
  Widget build(BuildContext context) {
    final tokens = AppSurfaceTokens.of(context);
    return _pageBody(context, [
      Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [tokens.heroStart, tokens.heroEnd], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Row(children: [
          const Icon(Icons.star_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('默认角色', style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.85))),
            const SizedBox(height: 2),
            Text(defaultId.isEmpty ? '尚未设置' : (defaultName.isEmpty ? defaultId : defaultName), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            if (defaultId.isNotEmpty) Text(defaultId, style: TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: Colors.white.withValues(alpha: 0.8))),
          ])),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        title: '角色列表',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: '新建角色', onPressed: _newRole, icon: const Icon(Icons.add, size: 20)),
          IconButton(tooltip: '导出当前角色 JSON', onPressed: _export, icon: const Icon(Icons.ios_share, size: 18)),
        ]),
        child: roles.isEmpty
            ? Text('还没有自定义角色，点右上角新建。', style: TextStyle(fontSize: 13, color: tokens.mutedText))
            : Column(children: [
                for (final role in roles)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _edit(role),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(children: [
                        Icon(role.id == defaultId ? Icons.star_rounded : Icons.person_outline, size: 18, color: role.id == defaultId ? const Color(0xFFFFC46B) : tokens.mutedText),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(role.displayName, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                          Text(role.id, style: TextStyle(fontSize: 11.5, color: tokens.mutedText)),
                        ])),
                        if (role.id != defaultId) TextButton(onPressed: loading ? null : () => _setRoleDefault(role), child: const Text('设为默认')),
                        const Icon(Icons.chevron_right, size: 18),
                      ]),
                    ),
                  ),
              ]),
      ),
      if (sessionOverrides.isNotEmpty) ...[
        const SizedBox(height: 12),
        AppCard(
          title: '会话单独角色（/preset）',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('这些会话在 QQ 里用 /preset 切换过角色，不使用上面的默认角色。', style: TextStyle(fontSize: 12.5, color: tokens.mutedText)),
            const SizedBox(height: 6),
            for (final entry in sessionOverrides.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                  const SizedBox(width: 8),
                  Text(_stored(entry.value)?.displayName ?? entry.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            const SizedBox(height: 6),
            OutlinedButton.icon(onPressed: loading ? null : _clearSessionOverrides, icon: const Icon(Icons.restart_alt, size: 18), label: const Text('全部恢复默认角色')),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      AppCard(
        title: editingExisting ? '编辑角色' : '新建角色',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _field(roleName, '显示名称', '例如：七草日花'),
          TextField(controller: rolePrompt, enabled: !loading, minLines: 10, maxLines: 18, decoration: const InputDecoration(labelText: '人格提示词', hintText: '身份、性格、语气、行为规则和边界', alignLabelWithHint: true)),
          const SizedBox(height: 10),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text('高级选项：角色 ID', style: TextStyle(fontSize: 13, color: tokens.mutedText)),
              subtitle: Text(roleId.text.isEmpty ? '保存时自动生成' : roleId.text, style: TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: tokens.mutedText)),
              children: [TextField(controller: roleId, enabled: !loading, decoration: const InputDecoration(labelText: '角色 ID', hintText: 'custom.my-role'))],
            ),
          ),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: loading ? null : _save, icon: const Icon(Icons.save_outlined, size: 18), label: const Text('保存角色卡'))),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: loading ? null : _setDefault, child: const Text('设为默认')),
            IconButton(tooltip: '删除角色', onPressed: loading ? null : _delete, icon: const Icon(Icons.delete_outline, size: 20)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        title: '导入角色卡',
        child: Column(children: [
          TextField(controller: importJson, minLines: 3, maxLines: 6, decoration: const InputDecoration(hintText: '{"id":"custom.example","displayName":"示例","prompt":"你是……"}')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: FilledButton.tonalIcon(onPressed: _importFile, icon: const Icon(Icons.file_open, size: 18), label: const Text('选择 JSON 文件'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.paste, size: 18), label: const Text('粘贴 JSON'))),
          ]),
        ]),
      ),
    ]);
  }
}

class _SeedDot extends StatelessWidget {
  const _SeedDot({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
          ),
          child: selected ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
        ),
      );
}

/// 说明性文字集中到这里，页面本身只留操作。
class _TutorialPage extends StatelessWidget {
  const _TutorialPage();

  static const List<(String, String)> _sections = [
    ('首次配置顺序', '1. 填写 AI 接口类型、Base URL 和 API Key；\n2. 点「测试接口」确认地址可用，再「拉取模型」选择模型；\n3. 点「测试请求」发一条 ping，确认模型能回话；\n4. 填写 QQ 官方机器人的 AppID 与 AppSecret，点「测试 QQ 连接」；\n5. 保存配置，回到总览点「重启」。\n\n测试失败不会覆盖已经保存的凭据；任何时候都可以先保存再慢慢测。'),
    ('公网 IP 白名单', 'QQ 开放平台按 IP 白名单放行。手机用流量或换 Wi-Fi 后地址会变化，需要回到总览复制新的 IPv4 地址，在开放平台更新白名单。'),
    ('角色卡', '角色卡决定模型的说话方式和行为边界。新建角色通常只需要填名称和人格提示词，保存时会自动生成 custom.xxx 的 ID。提示词建议写清身份、语气、行为规则、禁止事项和回复格式；为空时不会保存。切换角色请在 QQ 里用 /preset。'),
    ('后台运行', 'Android 会限制后台活动。若机器人经常掉线，请在系统设置里允许本应用后台运行、取消电池优化，并允许通知。'),
    ('应用更新', '「检查在线更新」会直接读取 GitHub 上最新的 Release 并和当前版本比较：已是最新时只显示版本号，有新版本才出现下载按钮。下载完成后由 Android 系统安装器接管，需要允许本应用安装未知来源应用。debug 包和 release 包签名不同，覆盖安装前要卸载旧包。'),
    ('备份与清理', '导出的备份不包含 API Key、AppSecret 和会话记录，但会包含主动保存的默认角色卡。清除会话会丢上下文，清除全部配置会删除凭据和外观设置，都不能恢复。'),
    ('日志', '运行时日志会同时写入文件，杀掉应用后重新打开仍能看到上一次启动和运行记录。日志页可以按级别和模块筛选、搜索关键词；「复制诊断信息」会带上版本号、ABI 和导出时间。'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('说明与教程')),
        body: _pageBody(context, [
          for (final section in _sections) ...[
            AppCard(title: section.$1, child: Text(section.$2, style: const TextStyle(fontSize: 13.5, height: 1.6))),
            const SizedBox(height: 12),
          ],
        ]),
      );
}
