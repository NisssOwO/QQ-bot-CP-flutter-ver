import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/runtime_log.dart';
import '../models/public_config.dart';
import '../models/endpoint_test_result.dart';
import '../models/runtime_state.dart';
import '../models/role_card.dart';
import '../services/runtime_bridge.dart';
import '../services/public_ip_service.dart';
import '../services/endpoint_test_service.dart';
import '../services/background_tasks.dart';
import '../models/update_manifest.dart';
import '../services/update_service.dart';
import '../theme/theme_controller.dart';
import '../theme/theme_bridge.dart';
import '../theme/app_theme_tokens.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.onThemeChanged});
  final ValueChanged<ThemeSettings>? onThemeChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _bridge = RuntimeBridge();
  final _logs = <RuntimeLogEntry>[];
  StreamSubscription<RuntimeLogEntry>? _subscription;
  RuntimeState _state = const RuntimeState();
  PublicConfig _publicConfig = const PublicConfig();
  int _index = 0;
  String _publicIp = '未检测';
  String _publicIpv6 = '未检测';
  String _ipCheckedAt = '';
  bool _ipLoading = false;
  bool _hidePublicIp = false;

  @override
  void initState() {
    super.initState();
    _subscription = _bridge.logs.listen((entry) {
      if (!mounted) return;
      setState(() {
        _logs.add(entry);
        if (_logs.length > 500) _logs.removeAt(0);
      });
    });
    _loadRecentLogs();
    _refreshState();
    _refreshConfig();
    _refreshPublicIp();
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

  Future<void> _restart() async {
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
      await _bridge.restart();
      await _refreshState();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重启请求失败：$error')));
    }
  }

  Future<void> _refreshPublicIp() async {
    if (_ipLoading) return;
    final timer = Stopwatch()..start();
    setState(() => _ipLoading = true);
    final result = await const PublicIpService().lookup();
    timer.stop();
    if (!mounted) return;
    setState(() {
      _ipLoading = false;
      _publicIp = result.ipv4 ?? '无法获取';
      _publicIpv6 = result.ipv6 ?? '无法获取';
      _ipCheckedAt = '${result.checkedAt.hour.toString().padLeft(2, '0')}:${result.checkedAt.minute.toString().padLeft(2, '0')}';
      _logs.add(RuntimeLogEntry(
        time: result.checkedAt,
        level: result.error == null ? LogLevel.info : LogLevel.warn,
        module: 'public-ip',
        message: result.error == null ? '公网 IP 查询完成（${timer.elapsedMilliseconds} ms）' : '公网 IP 查询失败（${timer.elapsedMilliseconds} ms）：${result.error}',
      ));
    });
  }

  void _copyPublicIp(String value) {
    if (value == '未检测' || value == '无法获取') return;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('公网 IP 已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _OverviewPage(state: _state, publicIp: _publicIp, publicIpv6: _publicIpv6, checkedAt: _ipCheckedAt, loadingIp: _ipLoading, hideIp: _hidePublicIp, qqConfigured: _publicConfig.qqConfigured, llmConfigured: _publicConfig.llmConfigured, onRefreshIp: _refreshPublicIp, onCopyIp: _copyPublicIp, onToggleHideIp: () => setState(() => _hidePublicIp = !_hidePublicIp), onOpenAi: () => setState(() => _index = 1), onRestart: () => _restart()),
      _ConfigPage(bridge: _bridge),
      _LogPage(logs: _logs),
      _RolePage(bridge: _bridge),
      _SettingsPage(bridge: _bridge, onThemeChanged: widget.onThemeChanged),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('QQ-bot-CP'), actions: [IconButton(onPressed: _refreshState, icon: const Icon(Icons.refresh))]),
      body: pages[_index],
      floatingActionButton: _index == 0 ? FloatingActionButton.extended(onPressed: _restart, icon: const Icon(Icons.restart_alt), label: const Text('重启 Runtime')) : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: '总览'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'AI'),
          NavigationDestination(icon: Icon(Icons.article_outlined), selectedIcon: Icon(Icons.article), label: '日志'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '角色'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({required this.state, required this.publicIp, required this.publicIpv6, required this.checkedAt, required this.loadingIp, required this.hideIp, required this.qqConfigured, required this.llmConfigured, required this.onRefreshIp, required this.onCopyIp, required this.onToggleHideIp, required this.onOpenAi, required this.onRestart});
  final RuntimeState state;
  final String publicIp;
  final String publicIpv6;
  final String checkedAt;
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
  Widget build(BuildContext context) => ListView(cacheExtent: 1200, padding: const EdgeInsets.fromLTRB(16, 16, 16, 144), children: [
        Card(child: ListTile(leading: Icon(Icons.circle, color: _statusColor(context, state.status)), title: Text(_statusLabel(state.status)), subtitle: Text(_phaseDescription(state)), trailing: Text('${state.elapsedMs} ms'))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Wrap(spacing: 8, runSpacing: 8, children: [
          Chip(avatar: const Icon(Icons.chat, size: 16), label: Text('QQ：${state.qqStatus}')),
          Chip(avatar: const Icon(Icons.auto_awesome, size: 16), label: Text('AI：${state.aiStatus}')),
          Chip(avatar: const Icon(Icons.wifi, size: 16), label: Text('网络：${state.networkStatus}')),
          if (state.reconnectAttempts > 0) Chip(label: Text('第 ${state.reconnectAttempts} 次重连 · ${state.nextRetryMs ~/ 1000}s')),
          if (state.qqFailureCount > 0) Chip(label: Text('QQ 失败 ${state.qqFailureCount} 次')),
          if (state.aiFailureCount > 0) Chip(label: Text('AI 失败 ${state.aiFailureCount} 次')),
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Expanded(child: Text('设备公网 IP', style: TextStyle(fontWeight: FontWeight.bold))), IconButton(tooltip: hideIp ? '显示 IP' : '隐藏 IP', onPressed: onToggleHideIp, icon: Icon(hideIp ? Icons.visibility_off : Icons.visibility)), loadingIp ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : IconButton(tooltip: '刷新', onPressed: onRefreshIp, icon: const Icon(Icons.refresh))]),
          _IpLine(label: 'IPv4', value: publicIp, hidden: hideIp, onCopy: onCopyIp),
          _IpLine(label: 'IPv6', value: publicIpv6, hidden: hideIp, onCopy: onCopyIp),
          if (checkedAt.isNotEmpty) Text('检测时间：$checkedAt', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('公网 IP 可能变化，不能作为设备永久标识。', style: Theme.of(context).textTheme.bodySmall),
        ]))),
        Card(child: ListTile(title: const Text('QQ 官方机器人'), subtitle: Text(qqConfigured ? 'AppID 与 AppSecret 已配置' : '等待填写 AppID 与 AppSecret'), leading: Icon(qqConfigured ? Icons.check_circle : Icons.info_outline, color: qqConfigured ? AppThemeTokens.of(context).success : AppThemeTokens.of(context).warning))),
        Card(child: ListTile(title: const Text('AI 接口'), subtitle: Text(llmConfigured ? 'API Key 已配置' : '等待填写 API Key'), leading: Icon(llmConfigured ? Icons.check_circle : Icons.info_outline, color: llmConfigured ? AppThemeTokens.of(context).success : AppThemeTokens.of(context).warning))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('首次启动说明', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(qqConfigured && llmConfigured ? '配置已齐全：点击“启动 Runtime”后，应用会依次加载配置、启动服务、连接 QQ，再进入运行状态。' : '首次使用请按顺序完成：1. 填写 AI 接口、模型、Base URL 和 AI 密钥；2. 填写 QQ AppID 与 AppSecret；3. 保存配置；4. 返回这里启动 Runtime。'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (!qqConfigured || !llmConfigured) OutlinedButton.icon(onPressed: onOpenAi, icon: const Icon(Icons.settings), label: const Text('去填写配置')),
            FilledButton.icon(onPressed: onRestart, icon: const Icon(Icons.play_arrow), label: Text(state.status == RuntimeStatus.online ? '重新启动 Runtime' : '启动 Runtime')),
          ]),
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('聊天指令', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('点击右侧按钮可逐条复制到 QQ。'),
          for (final command in const ['/preset <角色ID>', '/presets', '/new']) _CommandCopyRow(command: command),
        ]))),
      ]);

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

  static String _phaseDescription(RuntimeState state) {
    if (state.status == RuntimeStatus.stopped && state.message.isEmpty) return '还没有启动 Runtime';
    final estimate = switch (state.phase) {
      'restart.begin' || 'process.stop' => '约 1 秒',
      'runtime.prepare' || 'config.load' => '约 1–3 秒',
      'plugin.load' || 'runtime.spawn' => '约 3–10 秒',
      'network.check' || 'qq.connect' => '约 2–15 秒（取决于网络）',
      'session.restore' || 'ready' || 'restart.complete' => '约 1 秒',
      _ => null,
    };
    final current = state.message.isEmpty ? state.phase : '${state.phase}：${state.message}';
    return estimate == null || state.status != RuntimeStatus.starting ? current : '$current · 预计 $estimate';
  }
}

class _IpLine extends StatelessWidget {
  const _IpLine({required this.label, required this.value, required this.hidden, required this.onCopy});
  final String label;
  final String value;
  final bool hidden;
  final ValueChanged<String> onCopy;
  @override
  Widget build(BuildContext context) {
    final shown = hidden && value != '未检测' && value != '无法获取' ? '••••••••' : value;
    return Row(children: [SizedBox(width: 48, child: Text('$label：')), Expanded(child: Text(shown)), if (!hidden && value != '未检测' && value != '无法获取') IconButton(tooltip: '复制 $label', onPressed: () => onCopy(value), icon: const Icon(Icons.copy, size: 18))]);
  }
}

class _CommandCopyRow extends StatelessWidget {
  const _CommandCopyRow({required this.command});
  final String command;
  @override
  Widget build(BuildContext context) => Row(children: [Expanded(child: Text(command, style: const TextStyle(fontFamily: 'monospace'))), IconButton(tooltip: '复制 $command', onPressed: () async { await Clipboard.setData(ClipboardData(text: command)); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制 $command'))); }, icon: const Icon(Icons.copy, size: 18))]);
}

class _LogPage extends StatefulWidget {
  const _LogPage({required this.logs});
  final List<RuntimeLogEntry> logs;
  @override State<_LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<_LogPage> {
  LogLevel? level;
  String module = '';
  List<RuntimeLogEntry> filtered = const [];
  bool filtering = false;
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
    final indexes = await filterLogIndexesInBackground(snapshot.map((entry) => <String, Object?>{
      'level': entry.level.name,
      'module': entry.module,
    }).toList(), level?.name, module);
    if (!mounted) return;
    setState(() {
      filtered = indexes.map((index) => snapshot[index]).toList().reversed.toList();
      filtering = false;
    });
  }
  String _redacted(String value) => value
      .replaceAll(RegExp(r'(bearer\s+|api[_-]?key\s*[:=]\s*|app[_-]?secret\s*[:=]\s*|authorization\s*[:=]\s*|secret\s*[:=]\s*|token\s*[:=]\s*)[^\s,;]+', caseSensitive: false), r'\1[REDACTED]')
      .replaceAll(RegExp(r'("(?:api[_-]?key|app[_-]?secret|token|authorization|bearer)"\s*:\s*")[^"]*(")', caseSensitive: false), r'\1[REDACTED]\2');
  Future<void> _export() async {
    final content = widget.logs.map((entry) => '${entry.time.toIso8601String()} [${entry.level.name}] ${entry.module} ${entry.errorCode == null ? '' : '[${entry.errorCode}] '}${_redacted(entry.message)}').join('\n');
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制脱敏日志')));
  }
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: Row(children: [
        Expanded(child: DropdownButtonFormField<LogLevel?>(value: level, decoration: const InputDecoration(labelText: '级别', border: OutlineInputBorder()), items: const [DropdownMenuItem<LogLevel?>(value: null, child: Text('全部')), DropdownMenuItem(value: LogLevel.info, child: Text('信息')), DropdownMenuItem(value: LogLevel.warn, child: Text('警告')), DropdownMenuItem(value: LogLevel.error, child: Text('错误'))], onChanged: (value) { setState(() => level = value); _applyFilter(); })),
        const SizedBox(width: 8),
        Expanded(child: TextField(decoration: const InputDecoration(labelText: '模块筛选', border: OutlineInputBorder()), onChanged: (value) { module = value; _applyFilter(); })),
        IconButton(tooltip: '复制脱敏日志', onPressed: widget.logs.isEmpty ? null : _export, icon: const Icon(Icons.copy_all)),
      ])),
      Expanded(child: filtering ? const Center(child: CircularProgressIndicator()) : filtered.isEmpty ? const Center(child: Text('暂无匹配的 Runtime 日志')) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: filtered.length, itemBuilder: (_, index) { final entry = filtered[index]; return ListTile(title: Text(entry.message), subtitle: Text('${entry.level.name} · ${entry.module}${entry.errorCode == null ? '' : ' · ${entry.errorCode}'}${entry.elapsedMs == null ? '' : ' · ${entry.elapsedMs} ms'}${entry.runId == null ? '' : ' · run ${entry.runId}'}')); })),
    ]);
  }
}

class _ConfigPage extends StatefulWidget {
  const _ConfigPage({required this.bridge});
  final RuntimeBridge bridge;
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
  List<AiConfigHistory> history = const [];
  int? selectedHistory;
  EndpointTestResult? endpointTest;
  bool testingEndpoint = false;
  Map<String, Object?>? qqTest;
  bool testingQq = false;
  bool qqConfigured = false;
  bool llmConfigured = false;
  String thinkingLevel = 'medium';
  List<String> modelOptions = const [];
  bool loadingModels = false;
  static const _savedMask = '••••••••';

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { for (final c in [protocol, model, baseUrl, appId, secret, apiKey]) { c.dispose(); } super.dispose(); }
  Future<void> _load() async {
    try { final c = await widget.bridge.config(); protocol.text = c.protocol; model.text = c.model; baseUrl.text = c.baseUrl; appId.text = c.appId; thinkingLevel = c.thinkingLevel; qqConfigured = c.qqConfigured; llmConfigured = c.llmConfigured; if (qqConfigured) secret.text = _savedMask; if (llmConfigured) apiKey.text = _savedMask; history = await widget.bridge.configHistory(); }
    finally { if (mounted) setState(() => loading = false); }
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
    final enteredSecret = _credentialValue(secret);
    final enteredApiKey = _credentialValue(apiKey);
    await widget.bridge.saveConfig(protocol: protocol.text.trim(), model: model.text.trim(), baseUrl: baseUrl.text.trim(), thinkingLevel: thinkingLevel, appId: appId.text.trim(), secret: enteredSecret, apiKey: enteredApiKey);
    final nextHistory = await widget.bridge.configHistory();
    if (secret.text.isNotEmpty) secret.text = _savedMask;
    if (apiKey.text.isNotEmpty) apiKey.text = _savedMask;
    qqConfigured = qqConfigured || enteredSecret.isNotEmpty;
    llmConfigured = llmConfigured || enteredApiKey.isNotEmpty;
    if (mounted) setState(() { history = nextHistory; selectedHistory = nextHistory.isEmpty ? null : 0; });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('配置已保存到 Android Keystore')));
  }

  Future<void> _testEndpoint() async {
    setState(() => testingEndpoint = true);
    final result = await const EndpointTestService().test(baseUrl.text);
    if (mounted) setState(() { testingEndpoint = false; endpointTest = result; });
  }

  Future<void> _testQq() async {
    setState(() => testingQq = true);
    final result = await widget.bridge.testQqConnection();
    if (mounted) setState(() { testingQq = false; qqTest = result; });
  }
  Future<void> _fetchModels() async {
    if (baseUrl.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先填写 Base URL'))); return; }
    setState(() => loadingModels = true);
    try {
      final models = await widget.bridge.fetchModels(baseUrl.text.trim());
      if (mounted) setState(() { modelOptions = models; if (models.contains(model.text.trim())) model.text = model.text.trim(); });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(models.isEmpty ? '接口没有返回可用模型' : '已拉取 ${models.length} 个模型')));
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('拉取模型失败：$error'))); }
    finally { if (mounted) setState(() => loadingModels = false); }
  }
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
    children: [
      const Text('AI 与 QQ 配置', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text('先填写接口与模型，再保存凭据；每个区块之间留有明确间距。', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 20),
      if (history.isNotEmpty) ...[
        _sectionTitle('快速选择', '选择历史配置会填入接口、模型和地址，不会覆盖密钥。'),
        DropdownButtonFormField<int>(value: selectedHistory, decoration: const InputDecoration(labelText: '历史 AI 配置', border: OutlineInputBorder()), items: [const DropdownMenuItem<int>(value: null, child: Text('不使用历史配置')), ...history.asMap().entries.map((entry) => DropdownMenuItem<int>(value: entry.key, child: Text(entry.value.label, overflow: TextOverflow.ellipsis)))], onChanged: (value) { if (value == null) return; final item = history[value]; setState(() { selectedHistory = value; protocol.text = item.protocol; model.text = item.model; baseUrl.text = item.baseUrl; }); }),
        const SizedBox(height: 20),
      ],
      _sectionTitle('AI 接口', '接口类型、模型和 Base URL 会用于发送模型请求。'),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(value: protocols.contains(protocol.text) ? protocol.text : '', decoration: const InputDecoration(labelText: '接口类型', border: OutlineInputBorder()), items: protocols.map((item) => DropdownMenuItem<String>(value: item, child: Text(item.isEmpty ? '请选择接口类型' : item))).toList(), onChanged: (value) { if (value != null) setState(() => protocol.text = value); }),
      const SizedBox(height: 14),
      if (modelOptions.isNotEmpty) ...[
        DropdownButtonFormField<String>(value: modelOptions.contains(model.text) ? model.text : null, decoration: const InputDecoration(labelText: '已拉取的模型', border: OutlineInputBorder()), items: modelOptions.map((item) => DropdownMenuItem(value: item, child: Text(item, overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) { if (value != null) setState(() => model.text = value); }),
        const SizedBox(height: 14),
      ],
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _field(model, '模型名称', '可手动输入，或先拉取模型列表')), const SizedBox(width: 12), Padding(padding: const EdgeInsets.only(top: 4), child: FilledButton.tonalIcon(onPressed: loadingModels ? null : _fetchModels, icon: loadingModels ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh), label: const Text('拉取模型')))]),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(value: const ['off', 'low', 'medium', 'high'].contains(thinkingLevel) ? thinkingLevel : 'medium', decoration: const InputDecoration(labelText: '思考程度', helperText: '仅对支持该参数的模型生效；不支持时由接口忽略', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'off', child: Text('关闭')), DropdownMenuItem(value: 'low', child: Text('低')), DropdownMenuItem(value: 'medium', child: Text('中')), DropdownMenuItem(value: 'high', child: Text('高'))], onChanged: (value) { if (value != null) setState(() => thinkingLevel = value); }),
      const SizedBox(height: 14),
      _field(baseUrl, 'Base URL', '留空，使用中转或官方接口时填写', onChanged: (_) => setState(() {})),
      FilledButton.tonalIcon(onPressed: testingEndpoint || baseUrl.text.trim().isEmpty ? null : _testEndpoint, icon: testingEndpoint ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.network_check), label: const Text('测试接口')),
      if (endpointTest != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${endpointTest!.ok ? '✓' : '✕'} ${endpointTest!.stage}：${endpointTest!.message}${endpointTest!.statusCode == null ? '' : '（HTTP ${endpointTest!.statusCode}）'}${endpointTest!.elapsedMs == null ? '' : ' · ${endpointTest!.elapsedMs} ms'}', style: TextStyle(color: endpointTest!.ok ? AppThemeTokens.of(context).success : AppThemeTokens.of(context).warning))),
      const SizedBox(height: 24),
      _sectionTitle('QQ 官方机器人', 'AppID 与 AppSecret 用于连接 QQ 官方机器人服务。'),
      const SizedBox(height: 10),
      _field(appId, 'QQ 官方机器人 AppID', '留空表示未配置'),
      _credentialField(secret, 'QQ AppSecret', qqConfigured ? '已保存；点击后可替换' : '未保存，请填写'),
      FilledButton.tonalIcon(onPressed: loading || testingQq ? null : _testQq, icon: testingQq ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link), label: const Text('测试 QQ 连接')),
      if (qqTest != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${qqTest!['configured'] == true ? '✓' : '✕'} ${qqTest!['stage'] ?? ''}：${qqTest!['message'] ?? ''}${qqTest!['statusCode'] == null ? '' : '（HTTP ${qqTest!['statusCode']}）'}${qqTest!['elapsedMs'] == null ? '' : ' · ${qqTest!['elapsedMs']} ms'}', style: TextStyle(color: qqTest!['configured'] == true ? AppThemeTokens.of(context).success : AppThemeTokens.of(context).warning))),
      const SizedBox(height: 24),
      _sectionTitle('AI 接口凭据', '密钥只保存到 Android Keystore；输入框留空表示保持原值。'),
      const SizedBox(height: 10),
      _credentialField(apiKey, 'AI API Key', llmConfigured ? '已保存；点击后可替换' : '未保存，请填写'),
      const SizedBox(height: 4),
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: loading ? null : _save, icon: const Icon(Icons.save), label: const Text('保存配置'))),
      if (history.isNotEmpty) Center(child: TextButton.icon(onPressed: _clearHistory, icon: const Icon(Icons.delete_outline), label: const Text('清除历史配置'))),
    ],
  );

  Widget _sectionTitle(String title, String description) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(description, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))]);

  String _credentialValue(TextEditingController controller) => controller.text == _savedMask ? '' : controller.text;

  Widget _credentialField(TextEditingController controller, String label, String hint) => _field(controller, label, hint, obscure: true, onTap: () { if (controller.text == _savedMask) controller.clear(); });

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
  bool downloading = false;
  double downloadProgress = 0;
  bool downloadPaused = false;
  UpdateDownloadController? downloadController;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { updateUrl.dispose(); super.dispose(); }
  double _snapOpacity(double value) => [0.7, 0.85, 1.0].reduce((a, b) => (value - a).abs() < (value - b).abs() ? a : b);
  Future<void> _load() async { final value = await widget.bridge.appInfo(); final saved = await ThemeBridge.load(); final savedBackups = await widget.bridge.backups(); final savedUpdateUrl = await widget.bridge.updateEndpoint(); if (mounted) setState(() { info = value; backups = savedBackups; updateUrl.text = savedUpdateUrl; themeMode = saved.mode; seedColor = saved.seedColor; cardRadius = saved.cardRadius; cardOpacity = _snapOpacity(saved.cardOpacity); tintedBackground = saved.tintedBackground; }); }
  void _applyTheme() { final settings = ThemeSettings(mode: themeMode, seedColor: seedColor, cardRadius: cardRadius, cardOpacity: cardOpacity, tintedBackground: tintedBackground); widget.onThemeChanged?.call(settings); setState(() { recentThemes = [settings, ...recentThemes.where((item) => item.mode != settings.mode || item.seedColor != settings.seedColor || item.cardRadius != settings.cardRadius).take(4)]; }); }
  void _resetTheme() { setState(() { themeMode = ThemeMode.dark; seedColor = const Color(0xff8290ff); cardRadius = 16; cardOpacity = 1; tintedBackground = false; }); _applyTheme(); }
  Future<void> _saveUpdateEndpoint(String value) async { try { await widget.bridge.saveUpdateEndpoint(value); } catch (_) {} }
  Future<void> _install() async {
    setState(() => installing = true);
    final result = await widget.bridge.pickAndInstallApk();
    if (!mounted) return;
    setState(() => installing = false);
    final status = result['status'];
    final reason = result['reason'];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status == 'permission_required' ? '请先允许本应用安装未知来源应用' : status == 'installer_opened' ? '已打开系统安装器' : status == 'cancelled' ? '已取消选择' : status == 'rejected' ? '已拒绝更新：$reason' : '更新操作：$status')));
  }
  Future<void> _checkUpdate() async {
    setState(() => checkingUpdate = true);
    try {
      final value = await const UpdateService().check(updateUrl.text);
      if (mounted) setState(() => manifest = value);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('检查更新失败：$error')));
    } finally { if (mounted) setState(() => checkingUpdate = false); }
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
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('设置', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    DropdownButtonFormField<ThemeMode>(value: themeMode, decoration: const InputDecoration(labelText: '主题', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')), DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')), DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统'))], onChanged: (value) { if (value != null) { setState(() => themeMode = value); _applyTheme(); } }),
    const SizedBox(height: 8),
    DropdownButtonFormField<Color>(value: seedColor, decoration: const InputDecoration(labelText: '主色', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: Color(0xff8290ff), child: Text('靛蓝')), DropdownMenuItem(value: Color(0xff4dd0e1), child: Text('青色')), DropdownMenuItem(value: Color(0xffff8a65), child: Text('珊瑚橙')), DropdownMenuItem(value: Color(0xffce93d8), child: Text('紫色'))], onChanged: (value) { if (value != null) { setState(() => seedColor = value); _applyTheme(); } }),
    const SizedBox(height: 8),
    DropdownButtonFormField<double>(value: cardRadius, decoration: const InputDecoration(labelText: '卡片圆角', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 8, child: Text('小')), DropdownMenuItem(value: 16, child: Text('中')), DropdownMenuItem(value: 24, child: Text('大'))], onChanged: (value) { if (value != null) { setState(() => cardRadius = value); _applyTheme(); } }),
    const SizedBox(height: 8),
    DropdownButtonFormField<double>(value: cardOpacity, decoration: const InputDecoration(labelText: '卡片透明度', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 0.7, child: Text('高透明')), DropdownMenuItem(value: 0.85, child: Text('半透明')), DropdownMenuItem(value: 1.0, child: Text('不透明'))], onChanged: (value) { if (value != null) { setState(() => cardOpacity = value); _applyTheme(); } }),
    SwitchListTile(title: const Text('柔和背景'), subtitle: const Text('使用轻微着色背景'), value: tintedBackground, onChanged: (value) { setState(() => tintedBackground = value); _applyTheme(); }),
    Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _resetTheme, icon: const Icon(Icons.restart_alt), label: const Text('恢复默认主题'))), if (recentThemes.isNotEmpty) IconButton(tooltip: '恢复最近主题', onPressed: () { final recent = recentThemes.first; setState(() { themeMode = recent.mode; seedColor = recent.seedColor; cardRadius = recent.cardRadius; cardOpacity = recent.cardOpacity; tintedBackground = recent.tintedBackground; }); _applyTheme(); }, icon: const Icon(Icons.history))]),
    const SizedBox(height: 16),
    Card(child: ListTile(title: const Text('应用版本'), subtitle: Text('${info['versionName'] ?? '读取中'} (${info['versionCode'] ?? '-'})'))),
    Card(child: ListTile(title: const Text('运行 ABI'), subtitle: Text(info['abi'] ?? '读取中'))),
    const SizedBox(height: 12),
    const Text('后台运行', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: OutlinedButton.icon(onPressed: () async { try { await widget.bridge.openBatteryOptimizationSettings(); } catch (error) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法打开电池设置：$error'))); } }, icon: const Icon(Icons.battery_saver), label: const Text('电池优化设置'))),
      const SizedBox(width: 8),
      Expanded(child: OutlinedButton.icon(onPressed: () async { try { await widget.bridge.openNotificationSettings(); } catch (error) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法打开通知设置：$error'))); } }, icon: const Icon(Icons.notifications_outlined), label: const Text('通知设置'))),
    ]),
    const Text('系统可能限制后台活动；请按需允许本应用后台运行和通知。', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 12),
    TextField(controller: updateUrl, onChanged: (value) { _saveUpdateEndpoint(value); setState(() {}); }, decoration: const InputDecoration(labelText: '更新清单 URL', hintText: '留空；填写公开 JSON 地址', border: OutlineInputBorder())),
    const SizedBox(height: 8),
    FilledButton.tonalIcon(onPressed: checkingUpdate || updateUrl.text.trim().isEmpty ? null : _checkUpdate, icon: checkingUpdate ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.update), label: const Text('检查在线更新')),
    if (manifest != null) ...[
      Card(child: ListTile(title: Text('最新版本 ${manifest!.versionName} · ${manifest!.abi}'), subtitle: Text('${manifest!.releaseNotes}\n大小：${manifest!.sizeLabel}\nSHA-256：${manifest!.sha256}'), isThreeLine: true)),
      if (downloading) ...[LinearProgressIndicator(value: downloadProgress), Row(children: [Expanded(child: Text('下载中 ${(downloadProgress * 100).toStringAsFixed(0)}%')), IconButton(tooltip: '暂停', onPressed: _pauseDownload, icon: const Icon(Icons.pause)), IconButton(tooltip: '取消', onPressed: _cancelDownload, icon: const Icon(Icons.close))])],
      if (!downloading) FilledButton.icon(onPressed: manifest!.apkUrl.isEmpty ? null : _downloadAndInstall, icon: Icon(downloadPaused ? Icons.play_arrow : Icons.download), label: Text(downloadPaused ? '继续下载' : '下载并安装更新')),
    ],
    const SizedBox(height: 8),
    FilledButton.icon(onPressed: installing ? null : _install, icon: installing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.install_mobile), label: const Text('从本地 APK 更新')),
    const SizedBox(height: 8),
    const Text('更新会交给 Android 系统安装器处理，应用不会绕过系统确认。', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 16),
    const Text('配置备份', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _exportBackup, icon: const Icon(Icons.upload_file), label: const Text('导出脱敏备份'))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: _importBackup, icon: const Icon(Icons.file_open), label: const Text('导入备份')))]),
    const Text('备份不包含 API Key、AppSecret 和会话记录；会包含你主动保存的默认角色卡。', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 8),
    if (backups.isEmpty) const Text('暂无自动备份', style: TextStyle(color: Colors.white60)),
    ...backups.map((backup) => Card(child: ListTile(leading: const Icon(Icons.backup), title: Text('${backup['name'] ?? '自动备份'}'), subtitle: Text('${((backup['size'] as num?)?.toInt() ?? 0) ~/ 1024} KB'), trailing: TextButton(onPressed: () => _restoreBackup(backup), child: const Text('恢复'))))),
    const SizedBox(height: 16),
    const Text('数据清理', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    OutlinedButton.icon(onPressed: () => _clearData('logs', '清除 Runtime 日志？', '只删除输出日志，不影响配置和会话。'), icon: const Icon(Icons.article_outlined), label: const Text('清除日志')),
    OutlinedButton.icon(onPressed: () => _clearData('sessions', '清除会话？', '会删除 Runtime 会话索引和上下文，不能恢复。'), icon: const Icon(Icons.history), label: const Text('清除会话')),
    OutlinedButton.icon(onPressed: () => _clearData('all', '清除全部配置？', '将删除 AI/QQ 凭据、主题、默认角色卡和历史配置，操作不可恢复。'), icon: const Icon(Icons.delete_forever), label: const Text('清除全部配置')),
  ]);
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
  bool get currentBuiltin => roles.any((role) => role.id == roleId.text.trim() && role.builtin);
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { roleId.dispose(); roleName.dispose(); rolePrompt.dispose(); importJson.dispose(); super.dispose(); }
  Future<void> _load() async { final values = await widget.bridge.roles(); final role = await widget.bridge.defaultRole(); if (mounted) setState(() { roles = values; defaultId = role['id'] ?? ''; defaultName = role['name'] ?? ''; roleId.text = role['id'] ?? ''; roleName.text = role['name'] ?? ''; rolePrompt.text = role['prompt'] ?? ''; loading = false; }); }
  void _newRole() { setState(() { roleId.text = 'custom.newrole'; roleName.clear(); rolePrompt.clear(); }); }
  void _edit(RoleCard role) { setState(() { roleId.text = role.id; roleName.text = role.displayName; rolePrompt.text = role.prompt; }); }
  Future<void> _save() async { try { final role = RoleCard(id: roleId.text.trim(), displayName: roleName.text.trim(), prompt: rolePrompt.text); await widget.bridge.saveRoleCard(role); await _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('角色卡已保存'))); } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$error'))); } }
  Future<void> _setDefault() async { if (roleId.text.trim().isEmpty) return; await widget.bridge.saveDefaultRole(id: roleId.text.trim(), name: roleName.text.trim(), prompt: rolePrompt.text); if (mounted) setState(() { defaultId = roleId.text.trim(); defaultName = roleName.text.trim(); }); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已设为默认角色'))); }
  Future<void> _delete() async { final id = roleId.text.trim(); if (id.isEmpty) return; final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('确认删除角色？'), content: Text('将删除 $id，且无法恢复。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除'))])) ?? false; if (!ok) return; await widget.bridge.deleteRoleCard(id); _newRole(); await _load(); }
  Future<void> _import() async { try { final decoded = await decodeJsonInBackground(importJson.text); if (decoded is! Map) throw const FormatException('JSON 必须是对象'); final role = RoleCard.fromMap(decoded); await widget.bridge.saveRoleCard(role); importJson.clear(); await _load(); _edit(role); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('角色卡已导入'))); } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$error'))); } }
  Future<void> _export() async { final role = RoleCard(id: roleId.text.trim(), displayName: roleName.text.trim(), prompt: rolePrompt.text); final result = await widget.bridge.exportRoleCard(jsonEncode(role.toMap())); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['status'] == 'exported' ? '角色卡已导出' : '导出操作：${result['status']}'))); }
  Future<void> _importFile() async { try { final text = await widget.bridge.importRoleCard(); if (text == null) return; final decoded = await decodeJsonInBackground(text); if (decoded is! Map) throw const FormatException('JSON 必须是对象'); final role = RoleCard.fromMap(decoded); await widget.bridge.saveRoleCard(role); await _load(); _edit(role); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('角色卡文件已导入'))); } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$error'))); } }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('角色管理', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const Text('角色卡决定模型的说话方式和行为边界。先新建或选择角色，编辑完成后必须点击“保存角色卡”；切换角色请在 QQ 对话中使用 /preset。', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 8),
    const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('填写建议：角色 ID 只能使用 custom.xxx 或已有内置 ID；显示名称用于列表展示；人格提示词建议写清身份、语气、行为规则、禁止事项和回复格式。提示词为空时不会保存。', style: TextStyle(color: Colors.white70)))),
    const SizedBox(height: 16),
    Card(child: ListTile(leading: Icon(defaultId.isEmpty ? Icons.star_border : Icons.star, color: defaultId.isEmpty ? Colors.white54 : Colors.amber), title: Text(defaultId.isEmpty ? '尚未设置默认角色' : '默认角色：${defaultName.isEmpty ? '已选择角色' : defaultName}'), subtitle: const Text('新会话和未指定角色的消息会使用这里的角色；选择角色后点击“设为默认角色”。'))),
    const SizedBox(height: 8),
    Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _newRole, icon: const Icon(Icons.add), label: const Text('新建角色'))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.upload_file), label: const Text('导出 JSON')))]),
    const SizedBox(height: 12),
    if (roles.isEmpty) const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('暂无自定义角色'), subtitle: Text('点击“新建角色”创建 custom.xxx 角色卡。'))),
    ...roles.map((role) => Card(child: ListTile(title: Text(role.displayName), subtitle: Text('${role.id}${role.id == defaultId ? ' · 默认角色' : ''}${role.builtin ? ' · 内置' : ' · 自定义'}'), trailing: IconButton(onPressed: () => _edit(role), icon: const Icon(Icons.edit))))),
    const SizedBox(height: 16),
    const Text('角色编辑', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    TextField(controller: roleId, enabled: !loading, decoration: const InputDecoration(labelText: '角色 ID', helperText: '自定义角色用 custom.xxx；内置角色直接编辑原 ID', hintText: 'custom.my-role', border: OutlineInputBorder())),
    const SizedBox(height: 8),
    TextField(controller: roleName, enabled: !loading, decoration: const InputDecoration(labelText: '显示名称', helperText: '用户在角色列表和提示中看到的名称', hintText: '例如：七草日花', border: OutlineInputBorder())),
    const SizedBox(height: 12),
    TextField(controller: rolePrompt, enabled: !loading, minLines: 12, maxLines: 24, decoration: const InputDecoration(labelText: '人格提示词', helperText: '可滚动编辑；建议包含身份、性格、语气、行为规则、边界和示例回复', hintText: '你是谁？如何说话？哪些内容必须拒绝？', alignLabelWithHint: true, border: OutlineInputBorder())),
    const SizedBox(height: 12),
    Row(children: [Expanded(child: FilledButton.icon(onPressed: loading ? null : _save, icon: const Icon(Icons.save), label: const Text('保存角色卡'))), const SizedBox(width: 8), IconButton(tooltip: '设为默认角色', onPressed: loading ? null : _setDefault, icon: Icon(defaultId == roleId.text ? Icons.star : Icons.star_border)), IconButton(tooltip: '删除角色', onPressed: loading ? null : _delete, icon: const Icon(Icons.delete_outline))]),
    const SizedBox(height: 16),
    const Text('导入角色卡 JSON', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    TextField(controller: importJson, minLines: 4, maxLines: 8, decoration: const InputDecoration(hintText: '{"id":"custom.example","displayName":"示例","prompt":"你是……"}', border: OutlineInputBorder())),
    const SizedBox(height: 8),
    Row(children: [Expanded(child: FilledButton.icon(onPressed: _importFile, icon: const Icon(Icons.file_open), label: const Text('选择 JSON 文件'))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.paste), label: const Text('粘贴 JSON')))]),
  ]);
}
