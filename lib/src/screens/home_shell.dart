import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/runtime_log.dart';
import '../models/runtime_state.dart';
import '../services/runtime_bridge.dart';
import '../services/public_ip_service.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _bridge = RuntimeBridge();
  final _logs = <RuntimeLogEntry>[];
  StreamSubscription<RuntimeLogEntry>? _subscription;
  RuntimeState _state = const RuntimeState();
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

  Future<void> _restart() async {
    try {
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
      _OverviewPage(state: _state, publicIp: _publicIp, publicIpv6: _publicIpv6, checkedAt: _ipCheckedAt, loadingIp: _ipLoading, hideIp: _hidePublicIp, onRefreshIp: _refreshPublicIp, onCopyIp: _copyPublicIp, onToggleHideIp: () => setState(() => _hidePublicIp = !_hidePublicIp)),
      _ConfigPage(bridge: _bridge),
      _LogPage(logs: _logs),
      const _PlaceholderPage(title: '设置', message: '更新、后台运行、主题和小组件设置将在后续 P0/P1 阶段接入。'),
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
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({required this.state, required this.publicIp, required this.publicIpv6, required this.checkedAt, required this.loadingIp, required this.hideIp, required this.onRefreshIp, required this.onCopyIp, required this.onToggleHideIp});
  final RuntimeState state;
  final String publicIp;
  final String publicIpv6;
  final String checkedAt;
  final bool loadingIp;
  final bool hideIp;
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
        const Card(child: ListTile(title: Text('QQ 官方机器人'), subtitle: Text('未读取凭据状态'))),
        const Card(child: ListTile(title: Text('AI 接口'), subtitle: Text('默认空配置，等待填写'))),
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

class _LogPage extends StatelessWidget {
  const _LogPage({required this.logs});
  final List<RuntimeLogEntry> logs;
  @override
  Widget build(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: logs.isEmpty ? 1 : logs.length,
        itemBuilder: (_, index) => logs.isEmpty ? const ListTile(title: Text('暂无 Runtime 日志')) : ListTile(title: Text(logs[index].message), subtitle: Text('${logs[index].level.name} · ${logs[index].module}')),
      );
}

class _ConfigPage extends StatefulWidget {
  const _ConfigPage({required this.bridge});
  final RuntimeBridge bridge;
  @override State<_ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<_ConfigPage> {
  final protocol = TextEditingController();
  final model = TextEditingController();
  final baseUrl = TextEditingController();
  final appId = TextEditingController();
  final secret = TextEditingController();
  final apiKey = TextEditingController();
  bool loading = true;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { for (final c in [protocol, model, baseUrl, appId, secret, apiKey]) { c.dispose(); } super.dispose(); }
  Future<void> _load() async {
    try { final c = await widget.bridge.config(); protocol.text = c.protocol; model.text = c.model; baseUrl.text = c.baseUrl; appId.text = c.appId; }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> _save() async {
    await widget.bridge.saveConfig(protocol: protocol.text.trim(), model: model.text.trim(), baseUrl: baseUrl.text.trim(), appId: appId.text.trim(), secret: secret.text, apiKey: apiKey.text);
    secret.clear(); apiKey.clear();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('配置已保存到 Android Keystore')));
  }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('AI 与 QQ 配置', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 16),
    _field(protocol, '接口类型', 'openai-compatible / anthropic-messages'),
    _field(model, '模型名称', '留空，填写后才会调用模型'),
    _field(baseUrl, 'Base URL', '留空，使用中转或官方接口时填写'),
    _field(appId, 'QQ 官方机器人 AppID', '留空表示未配置'),
    _field(secret, 'QQ AppSecret', '已保存时留空表示不修改', obscure: true),
    _field(apiKey, 'AI API Key', '已保存时留空表示不修改', obscure: true),
    const SizedBox(height: 8),
    FilledButton.icon(onPressed: loading ? null : _save, icon: const Icon(Icons.save), label: const Text('保存配置')),
  ]);

  Widget _field(TextEditingController c, String label, String hint, {bool obscure = false}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: c, obscureText: obscure, decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder())));
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('$title\n\n$message', textAlign: TextAlign.center)));
}


