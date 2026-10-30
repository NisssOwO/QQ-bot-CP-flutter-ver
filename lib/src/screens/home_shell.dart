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
import '../models/update_manifest.dart';
import '../services/update_service.dart';
import '../theme/theme_controller.dart';
import '../theme/theme_bridge.dart';

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
    _refreshState();
    _refreshConfig();
    _refreshPublicIp();
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
      _OverviewPage(state: _state, publicIp: _publicIp, publicIpv6: _publicIpv6, checkedAt: _ipCheckedAt, loadingIp: _ipLoading, hideIp: _hidePublicIp, qqConfigured: _publicConfig.qqConfigured, llmConfigured: _publicConfig.llmConfigured, onRefreshIp: _refreshPublicIp, onCopyIp: _copyPublicIp, onToggleHideIp: () => setState(() => _hidePublicIp = !_hidePublicIp)),
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
  const _OverviewPage({required this.state, required this.publicIp, required this.publicIpv6, required this.checkedAt, required this.loadingIp, required this.hideIp, required this.qqConfigured, required this.llmConfigured, required this.onRefreshIp, required this.onCopyIp, required this.onToggleHideIp});
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

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(leading: const Icon(Icons.circle, color: Colors.orange), title: Text(_statusLabel(state.status)), subtitle: Text(state.phase), trailing: Text('${state.elapsedMs} ms'))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Expanded(child: Text('设备公网 IP', style: TextStyle(fontWeight: FontWeight.bold))), IconButton(tooltip: hideIp ? '显示 IP' : '隐藏 IP', onPressed: onToggleHideIp, icon: Icon(hideIp ? Icons.visibility_off : Icons.visibility)), loadingIp ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : IconButton(tooltip: '刷新', onPressed: onRefreshIp, icon: const Icon(Icons.refresh))]),
          _IpLine(label: 'IPv4', value: publicIp, hidden: hideIp, onCopy: onCopyIp),
          _IpLine(label: 'IPv6', value: publicIpv6, hidden: hideIp, onCopy: onCopyIp),
          if (checkedAt.isNotEmpty) Text('检测时间：$checkedAt', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('公网 IP 可能变化，不能作为设备永久标识。', style: Theme.of(context).textTheme.bodySmall),
        ]))),
        Card(child: ListTile(title: const Text('QQ 官方机器人'), subtitle: Text(qqConfigured ? 'AppID 与 AppSecret 已配置' : '等待填写 AppID 与 AppSecret'), leading: Icon(qqConfigured ? Icons.check_circle : Icons.info_outline, color: qqConfigured ? Colors.greenAccent : Colors.orangeAccent))),
        Card(child: ListTile(title: const Text('AI 接口'), subtitle: Text(llmConfigured ? 'API Key 已配置' : '等待填写 API Key'), leading: Icon(llmConfigured ? Icons.check_circle : Icons.info_outline, color: llmConfigured ? Colors.greenAccent : Colors.orangeAccent))),
      ]);

  static String _statusLabel(RuntimeStatus status) => switch (status) {
        RuntimeStatus.stopped => '已停止',
        RuntimeStatus.starting => '启动中',
        RuntimeStatus.online => '运行中',
        RuntimeStatus.reconnecting => '重连中',
        RuntimeStatus.failed => '异常',
        RuntimeStatus.stopping => '停止中',
      };
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

class _LogPage extends StatefulWidget {
  const _LogPage({required this.logs});
  final List<RuntimeLogEntry> logs;
  @override State<_LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<_LogPage> {
  LogLevel? level;
  String module = '';
  String _redacted(String value) => value.replaceAll(RegExp(r'(bearer\s+|api[_-]?key\s*[:=]\s*|secret\s*[:=]\s*|token\s*[:=]\s*)[^\s,;]+', caseSensitive: false), r'\1[REDACTED]');
  Future<void> _export() async {
    final content = widget.logs.map((entry) => '${entry.time.toIso8601String()} [${entry.level.name}] ${entry.module} ${entry.errorCode == null ? '' : '[${entry.errorCode}] '}${_redacted(entry.message)}').join('\n');
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制脱敏日志')));
  }
  @override
  Widget build(BuildContext context) {
    final filtered = widget.logs.where((entry) => (level == null || entry.level == level) && (module.trim().isEmpty || entry.module.toLowerCase().contains(module.trim().toLowerCase()))).toList().reversed.toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: Row(children: [
        Expanded(child: DropdownButtonFormField<LogLevel?>(value: level, decoration: const InputDecoration(labelText: '级别', border: OutlineInputBorder()), items: const [DropdownMenuItem<LogLevel?>(value: null, child: Text('全部')), DropdownMenuItem(value: LogLevel.info, child: Text('信息')), DropdownMenuItem(value: LogLevel.warn, child: Text('警告')), DropdownMenuItem(value: LogLevel.error, child: Text('错误'))], onChanged: (value) => setState(() => level = value))),
        const SizedBox(width: 8),
        Expanded(child: TextField(decoration: const InputDecoration(labelText: '模块筛选', border: OutlineInputBorder()), onChanged: (value) => setState(() => module = value))),
        IconButton(tooltip: '复制脱敏日志', onPressed: widget.logs.isEmpty ? null : _export, icon: const Icon(Icons.copy_all)),
      ])),
      Expanded(child: filtered.isEmpty ? const Center(child: Text('暂无匹配的 Runtime 日志')) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: filtered.length, itemBuilder: (_, index) { final entry = filtered[index]; return ListTile(title: Text(entry.message), subtitle: Text('${entry.level.name} · ${entry.module}${entry.errorCode == null ? '' : ' · ${entry.errorCode}'}${entry.elapsedMs == null ? '' : ' · ${entry.elapsedMs} ms'}${entry.runId == null ? '' : ' · run ${entry.runId}'}')); })),
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

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { for (final c in [protocol, model, baseUrl, appId, secret, apiKey]) { c.dispose(); } super.dispose(); }
  Future<void> _load() async {
    try { final c = await widget.bridge.config(); protocol.text = c.protocol; model.text = c.model; baseUrl.text = c.baseUrl; appId.text = c.appId; history = await widget.bridge.configHistory(); }
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
    await widget.bridge.saveConfig(protocol: protocol.text.trim(), model: model.text.trim(), baseUrl: baseUrl.text.trim(), appId: appId.text.trim(), secret: secret.text, apiKey: apiKey.text);
    final nextHistory = await widget.bridge.configHistory();
    secret.clear(); apiKey.clear();
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
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('AI 与 QQ 配置', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 16),
    if (history.isNotEmpty) ...[
      DropdownButtonFormField<int>(value: selectedHistory, decoration: const InputDecoration(labelText: '历史 AI 配置（不含密钥）', border: OutlineInputBorder()), items: [const DropdownMenuItem<int>(value: null, child: Text('不使用历史配置')), ...history.asMap().entries.map((entry) => DropdownMenuItem<int>(value: entry.key, child: Text(entry.value.label, overflow: TextOverflow.ellipsis)))], onChanged: (value) { if (value == null) return; final item = history[value]; setState(() { selectedHistory = value; protocol.text = item.protocol; model.text = item.model; baseUrl.text = item.baseUrl; }); }),
      const SizedBox(height: 12),
    ],
    DropdownButtonFormField<String>(value: protocols.contains(protocol.text) ? protocol.text : '', decoration: const InputDecoration(labelText: '接口类型', border: OutlineInputBorder()), items: protocols.map((item) => DropdownMenuItem<String>(value: item, child: Text(item.isEmpty ? '请选择接口类型' : item))).toList(), onChanged: (value) { if (value != null) setState(() => protocol.text = value); }),
    const SizedBox(height: 12),
    _field(model, '模型名称', '留空，填写后才会调用模型'),
    _field(baseUrl, 'Base URL', '留空，使用中转或官方接口时填写', onChanged: (_) => setState(() {})),
    Row(children: [Expanded(child: FilledButton.tonalIcon(onPressed: testingEndpoint || baseUrl.text.trim().isEmpty ? null : _testEndpoint, icon: testingEndpoint ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.network_check), label: const Text('测试接口')))]),
    if (endpointTest != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${endpointTest!.ok ? '✓' : '✕'} ${endpointTest!.stage}：${endpointTest!.message}${endpointTest!.statusCode == null ? '' : '（HTTP ${endpointTest!.statusCode}）'}${endpointTest!.elapsedMs == null ? '' : ' · ${endpointTest!.elapsedMs} ms'}', style: TextStyle(color: endpointTest!.ok ? Colors.greenAccent : Colors.orangeAccent))),
    const SizedBox(height: 12),
    _field(appId, 'QQ 官方机器人 AppID', '留空表示未配置'),
    _field(secret, 'QQ AppSecret', '已保存时留空表示不修改', obscure: true),
    FilledButton.tonalIcon(onPressed: loading || testingQq ? null : _testQq, icon: testingQq ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link), label: const Text('测试 QQ 连接')),
    if (qqTest != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${qqTest!['configured'] == true ? '✓' : '✕'} ${qqTest!['stage'] ?? ''}：${qqTest!['message'] ?? ''}${qqTest!['statusCode'] == null ? '' : '（HTTP ${qqTest!['statusCode']}）'}${qqTest!['elapsedMs'] == null ? '' : ' · ${qqTest!['elapsedMs']} ms'}', style: TextStyle(color: qqTest!['configured'] == true ? Colors.greenAccent : Colors.orangeAccent))),
    _field(apiKey, 'AI API Key', '已保存时留空表示不修改', obscure: true),
    const SizedBox(height: 8),
    FilledButton.icon(onPressed: loading ? null : _save, icon: const Icon(Icons.save), label: const Text('保存配置')),
    if (history.isNotEmpty) TextButton.icon(onPressed: _clearHistory, icon: const Icon(Icons.delete_outline), label: const Text('清除历史配置')),
  ]);

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('清除历史配置？'), content: const Text('只会删除接口类型、模型和 Base URL 历史，不会删除已保存的密钥。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清除'))])) ?? false;
    if (!confirmed) return;
    await widget.bridge.deleteConfigHistory();
    if (mounted) setState(() { history = const []; selectedHistory = null; });
  }

  Widget _field(TextEditingController c, String label, String hint, {bool obscure = false, ValueChanged<String>? onChanged}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: c, obscureText: obscure, onChanged: onChanged, decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder())));
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('$title\n\n$message', textAlign: TextAlign.center)));
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
  Future<void> _load() async { final value = await widget.bridge.appInfo(); final saved = await ThemeBridge.load(); if (mounted) setState(() { info = value; themeMode = saved.mode; seedColor = saved.seedColor; cardRadius = saved.cardRadius; cardOpacity = _snapOpacity(saved.cardOpacity); tintedBackground = saved.tintedBackground; }); }
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
    TextField(controller: updateUrl, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: '更新清单 URL', hintText: '留空；填写公开 JSON 地址', border: OutlineInputBorder())),
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
  bool loading = true;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { roleId.dispose(); roleName.dispose(); rolePrompt.dispose(); importJson.dispose(); super.dispose(); }
  Future<void> _load() async { final values = await widget.bridge.roles(); final role = await widget.bridge.defaultRole(); if (mounted) setState(() { roles = values; defaultId = role['id'] ?? ''; roleId.text = role['id'] ?? ''; roleName.text = role['name'] ?? ''; rolePrompt.text = role['prompt'] ?? ''; loading = false; }); }
  void _newRole() { setState(() { roleId.text = 'custom.newrole'; roleName.clear(); rolePrompt.clear(); }); }
  void _edit(RoleCard role) { if (role.builtin) return; setState(() { roleId.text = role.id; roleName.text = role.displayName; rolePrompt.text = role.prompt; }); }
  Future<void> _save() async { try { final role = RoleCard(id: roleId.text.trim(), displayName: roleName.text.trim(), prompt: rolePrompt.text); await widget.bridge.saveRoleCard(role); await _load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('角色卡已保存'))); } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$error'))); } }
  Future<void> _setDefault() async { if (roleId.text.trim().isEmpty) return; await widget.bridge.saveDefaultRole(id: roleId.text.trim(), name: roleName.text.trim(), prompt: rolePrompt.text); if (mounted) setState(() => defaultId = roleId.text.trim()); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已设为默认角色'))); }
  Future<void> _delete() async { final id = roleId.text.trim(); if (id.isEmpty) return; final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('确认删除角色？'), content: Text('将删除 $id，且无法恢复。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除'))])) ?? false; if (!ok) return; await widget.bridge.deleteRoleCard(id); _newRole(); await _load(); }
  Future<void> _import() async { try { final decoded = jsonDecode(importJson.text); if (decoded is! Map) throw const FormatException('JSON 必须是对象'); final role = RoleCard.fromMap(decoded); await widget.bridge.saveRoleCard(role); importJson.clear(); await _load(); _edit(role); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('角色卡已导入'))); } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$error'))); } }
  Future<void> _export() async { final role = RoleCard(id: roleId.text.trim(), displayName: roleName.text.trim(), prompt: rolePrompt.text); final result = await widget.bridge.exportRoleCard(jsonEncode(role.toMap())); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['status'] == 'exported' ? '角色卡已导出' : '导出操作：${result['status']}'))); }
  Future<void> _importFile() async { try { final text = await widget.bridge.importRoleCard(); if (text == null) return; final decoded = jsonDecode(text); if (decoded is! Map) throw const FormatException('JSON 必须是对象'); final role = RoleCard.fromMap(decoded); await widget.bridge.saveRoleCard(role); await _load(); _edit(role); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('角色卡文件已导入'))); } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$error'))); } }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('角色管理', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const Text('参考旧项目角色卡格式：custom.xxx、显示名称和人格提示词。内置角色由 Runtime 提供并保持只读。', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 16),
    Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _newRole, icon: const Icon(Icons.add), label: const Text('新建角色'))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.upload_file), label: const Text('导出 JSON')))]),
    const SizedBox(height: 12),
    if (roles.isEmpty) const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('暂无自定义角色'), subtitle: Text('点击“新建角色”创建 custom.xxx 角色卡。'))),
    ...roles.map((role) => Card(child: ListTile(title: Text(role.displayName), subtitle: Text('${role.id}${role.id == defaultId ? ' · 默认角色' : ''}'), trailing: IconButton(onPressed: () => _edit(role), icon: const Icon(Icons.edit))))),
    const SizedBox(height: 16),
    const Text('角色编辑', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    TextField(controller: roleId, enabled: !loading, decoration: const InputDecoration(labelText: '角色 ID', hintText: 'custom.my-role', border: OutlineInputBorder())),
    const SizedBox(height: 8),
    TextField(controller: roleName, enabled: !loading, decoration: const InputDecoration(labelText: '显示名称', hintText: '例如：七草日花', border: OutlineInputBorder())),
    const SizedBox(height: 12),
    TextField(controller: rolePrompt, enabled: !loading, minLines: 10, maxLines: 20, decoration: const InputDecoration(labelText: '人格提示词', hintText: '填写默认角色的人格、语气、行为规则和边界', alignLabelWithHint: true, border: OutlineInputBorder())),
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
