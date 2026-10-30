import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/runtime_log.dart';
import '../models/runtime_state.dart';
import '../services/runtime_bridge.dart';

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

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _OverviewPage(state: _state, publicIp: _publicIp, onRefreshIp: () => setState(() => _publicIp = '查询接口待接入')),
      const _PlaceholderPage(title: 'AI 配置', message: '协议、模型、Base URL 和 API Key 将保持空白，接入配置模块后填写。'),
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
  const _OverviewPage({required this.state, required this.publicIp, required this.onRefreshIp});
  final RuntimeState state;
  final String publicIp;
  final VoidCallback onRefreshIp;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(leading: const Icon(Icons.circle, color: Colors.orange), title: Text(_statusLabel(state.status)), subtitle: Text(state.phase), trailing: Text('${state.elapsedMs} ms'))),
        Card(child: ListTile(title: const Text('设备公网 IP'), subtitle: Text(publicIp), trailing: IconButton(onPressed: onRefreshIp, icon: const Icon(Icons.refresh)))),
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

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('$title\n\n$message', textAlign: TextAlign.center)));
}

