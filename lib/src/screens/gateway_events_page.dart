import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gateway_event.dart';
import '../services/runtime_bridge.dart';

/// 网关事件流水页。
///
/// 和「日志」页的区别：日志页是给人看的运行时输出，可能被上限裁剪；这里读的是
/// Node 侧只追加写入的 `gateway-events.jsonl`，每次断开都留一行，用来回答
/// 「到底是什么把连接打挂的」——尤其是区分 SDK 本地判定超时和服务端真的发了关闭帧。
class GatewayEventsPage extends StatefulWidget {
  const GatewayEventsPage({super.key, required this.bridge});

  final RuntimeBridge bridge;

  @override
  State<GatewayEventsPage> createState() => _GatewayEventsPageState();
}

class _GatewayEventsPageState extends State<GatewayEventsPage> {
  GatewayEventLog _log = const GatewayEventLog.empty();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final log = await widget.bridge.gatewayEvents();
      if (!mounted) return;
      setState(() {
        _log = log;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _copyAll() async {
    if (_log.isEmpty) return;
    // 按原样拼回 JSONL，方便直接贴到 issue 或存成文件后分析。
    final text = _log.events.map((entry) => jsonEncode(entry.raw)).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ${_log.events.length} 条网关事件到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _summary(theme),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _errorCard(theme)
          else if (_log.isEmpty)
            _emptyCard(theme)
          else
            for (final entry in _log.events.reversed) _eventCard(theme, entry),
        ],
      ),
    );
  }

  Widget _summary(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('网关事件流水', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  onPressed: _loading ? null : _load,
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh, size: 20),
                ),
                IconButton(
                  onPressed: _log.isEmpty ? null : _copyAll,
                  tooltip: '复制全部（JSONL）',
                  icon: const Icon(Icons.copy_all_outlined, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '只追加、不覆盖：每次断开都留一行，因此能看到「最初」是为什么断的，'
              '而不是只剩最后一次失败。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (_log.path.isEmpty)
              Text('还没有产生任何网关事件', style: theme.textTheme.bodySmall)
            else ...[
              Text('文件：${_log.path}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                _log.lines > _log.events.length
                    ? '共 ${_log.lines} 行，显示最近 ${_log.events.length} 条'
                    : '共 ${_log.lines} 行',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('读取失败', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(_error ?? '', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 36, color: theme.colorScheme.outline),
            const SizedBox(height: 10),
            Text('暂无网关事件', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'Runtime 启动并连上 QQ 网关后，这里会出现 start / online 记录；'
              '断开时会出现原因、关闭码来源和连接存活时长。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventCard(ThemeData theme, GatewayEventEntry entry) {
    final (label, icon) = _label(entry);
    final color = entry.isFailure
        ? theme.colorScheme.error
        : entry.isRecovering
            ? theme.colorScheme.tertiary
            : entry.isHealthy
                ? theme.colorScheme.primary
                : theme.colorScheme.outline;
    final detail = _detail(entry);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _formatTime(entry.time),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(color: color),
                      ),
                      if (entry.fromServer) ...[
                        const SizedBox(width: 6),
                        _badge(theme, '服务端关闭帧', theme.colorScheme.secondaryContainer),
                      ] else if (entry.codeSource == 'local') ...[
                        const SizedBox(width: 6),
                        _badge(theme, '本地判定', theme.colorScheme.surfaceContainerHighest),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_headline(entry), style: theme.textTheme.bodyMedium),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(ThemeData theme, String text, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: theme.textTheme.labelSmall),
    );
  }

  String _headline(GatewayEventEntry entry) {
    final name = entry.codeName ?? '';
    switch (entry.event) {
      case 'reconnecting':
      case 'offline':
        if (entry.codeSource == 'local') return '本地判定：${_localReasonName(name)}';
        if (entry.code != null) return 'code=${entry.code} ${entry.codeText ?? name}'.trim();
        return entry.reason ?? '连接断开';
      case 'failed':
        return entry.message ?? '网关启动失败';
      case 'start':
      case 'stop':
        return entry.message ?? (entry.event == 'start' ? '开始启动网关' : '主动关闭网关');
      case 'unparsed':
        return '无法解析的记录：${entry.reason ?? ''}';
      default:
        return entry.message ?? entry.reason ?? entry.event;
    }
  }

  String _detail(GatewayEventEntry entry) {
    final parts = <String>[];
    if (entry.attempt != null && entry.attempt! > 0) parts.add('第 ${entry.attempt} 次重连');
    if (entry.uptimeMs != null) parts.add('连接存活 ${_formatDuration(entry.uptimeMs)}');
    if (entry.sinceLastReadyMs != null) parts.add('距上次 READY ${_formatDuration(entry.sinceLastReadyMs)}');
    if (entry.event == 'unparsed' && entry.reason != null) parts.add(entry.reason!);
    return parts.join(' · ');
  }

  /// 把 SDK 的本地判定 key 翻成人话，避免只看到 `ready_timeout` 还要查代码。
  String _localReasonName(String key) {
    switch (key) {
      case 'connect_timeout':
        return '连接阶段超时（45 秒内没建立连接）';
      case 'hello_timeout':
        return '握手超时（20 秒内没收到 HELLO）';
      case 'ready_timeout':
        return '鉴权后无响应（18 秒内没收到 READY）';
      case 'heartbeat_timeout':
        return '心跳无回应（连续 3 次没收到 ACK，连接已是半开）';
      case 'socket_error_no_close':
        return '套接字报错且没有关闭帧';
      case 'op7_reconnect':
        return '服务端要求重连（op 7）';
      case 'op9_invalid_session':
        return '会话无效（op 9）';
      default:
        return key.isEmpty ? '未知原因' : key;
    }
  }

  String _formatTime(DateTime time) =>
      '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';

  String _two(int value) => value.toString().padLeft(2, '0');

  String _formatDuration(int? ms) {
    if (ms == null) return '未知';
    if (ms < 0) return '未知';
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)} 秒';
    return '${(ms / 60000).toStringAsFixed(1)} 分';
  }

  (String, IconData) _label(GatewayEventEntry entry) {
    switch (entry.event) {
      case 'online':
        return ('已连上', Icons.check_circle_outline);
      case 'reconnecting':
        return ('正在重连', Icons.sync_problem);
      case 'offline':
        return ('连接断开', Icons.link_off);
      case 'failed':
        return ('启动失败', Icons.error_outline);
      case 'start':
        return ('开始启动', Icons.play_circle_outline);
      case 'stop':
        return ('主动关闭', Icons.stop_circle_outlined);
      case 'unparsed':
        return ('无法解析', Icons.help_outline);
      default:
        return (entry.event, Icons.circle_outlined);
    }
  }
}
