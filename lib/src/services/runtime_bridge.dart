import 'dart:async';
import 'package:flutter/services.dart';
import '../models/public_config.dart';
import '../models/runtime_log.dart';
import '../models/runtime_state.dart';
import '../models/role_card.dart';

class RuntimeBridge {
  static const _methods = MethodChannel('qq_bot_cp/runtime');
  static const _events = EventChannel('qq_bot_cp/runtime_events');

  Future<T?> _call<T>(String method, [Object? arguments, Duration timeout = const Duration(seconds: 12), int retries = 0]) async {
    RuntimeBridgeException? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        return await _methods.invokeMethod<T>(method, arguments).timeout(timeout);
      } on TimeoutException {
        lastError = RuntimeBridgeException('bridge_timeout', '操作“$method”超时，请查看日志后重试');
      } on PlatformException catch (error) {
        lastError = RuntimeBridgeException(error.code, error.message ?? '操作“$method”失败');
      }
      if (attempt < retries) await Future<void>.delayed(Duration(milliseconds: 200 * (1 << attempt)));
    }
    throw lastError ?? RuntimeBridgeException('bridge_error', '操作“$method”失败');
  }

  Stream<RuntimeLogEntry> get logs => _events.receiveBroadcastStream().where((event) => event is Map).cast<Map>().map((raw) {
        final level = LogLevel.values.firstWhere(
          (value) => value.name == raw['level'],
          orElse: () => LogLevel.info,
        );
        return RuntimeLogEntry(
          time: DateTime.tryParse('${raw['time']}') ?? DateTime.now(),
          level: level,
          module: '${raw['module'] ?? 'runtime'}',
          message: '${raw['message'] ?? ''}',
          elapsedMs: raw['elapsedMs'] as int?,
          runId: raw['runId'] as String?,
          errorCode: raw['errorCode'] as String?,
        );
      });

  Future<void> start() async { await _call<void>('startRuntime'); }
  Future<void> stop() async { await _call<void>('stopRuntime'); }
  Future<void> restart() async { await _call<void>('restartRuntime', null, const Duration(seconds: 20)); }

  Future<RuntimeState> state() async {
    final raw = (await _call<Map<dynamic, dynamic>>('getRuntimeState', null, const Duration(seconds: 12), 2))?.map((key, value) => MapEntry('$key', value)) ?? <String, dynamic>{};
    final status = RuntimeStatus.values.firstWhere(
      (value) => value.name == raw['status'],
      orElse: () => RuntimeStatus.stopped,
    );
    return RuntimeState(
      status: status,
      phase: '${raw['phase'] ?? '未知'}',
      message: '${raw['message'] ?? ''}',
      elapsedMs: (raw['elapsedMs'] as num?)?.toInt() ?? 0,
      exitCode: (raw['exitCode'] as num?)?.toInt(),
      qqStatus: '${raw['qqStatus'] ?? '未知'}',
      aiStatus: '${raw['aiStatus'] ?? '未知'}',
      networkStatus: '${raw['networkStatus'] ?? '未知'}',
      reconnectAttempts: (raw['reconnectAttempts'] as num?)?.toInt() ?? 0,
      nextRetryMs: (raw['nextRetryMs'] as num?)?.toInt() ?? 0,
      qqFailureCount: (raw['qqFailureCount'] as num?)?.toInt() ?? 0,
      aiFailureCount: (raw['aiFailureCount'] as num?)?.toInt() ?? 0,
    );
  }

  Future<PublicConfig> config() async {
    final raw = (await _call<Map<dynamic, dynamic>>('getPublicConfig', null, const Duration(seconds: 12), 2))?.map((key, value) => MapEntry('$key', value)) ?? <String, dynamic>{};
    return PublicConfig(
      protocol: '${raw['protocol'] ?? ''}',
      model: '${raw['model'] ?? ''}',
      baseUrl: '${raw['baseUrl'] ?? ''}',
      appId: '${raw['appId'] ?? ''}',
      qqConfigured: raw['qqConfigured'] == true,
      llmConfigured: raw['llmConfigured'] == true,
    );
  }

  Future<void> saveConfig({required String protocol, required String model, required String baseUrl, required String appId, required String secret, required String apiKey}) =>
      _call<void>('saveConfig', {
        'protocol': protocol, 'model': model, 'baseUrl': baseUrl,
        'appId': appId, 'secret': secret, 'apiKey': apiKey,
      });

  Future<List<AiConfigHistory>> configHistory() async {
    final raw = await _call<List<dynamic>>('getConfigHistory', null, const Duration(seconds: 12), 2) ?? const [];
    return raw.whereType<Map>().map((item) => AiConfigHistory(
      protocol: '${item['protocol'] ?? ''}',
      model: '${item['model'] ?? ''}',
      baseUrl: '${item['baseUrl'] ?? ''}',
    )).toList();
  }

  Future<void> deleteConfigHistory() async { await _call<void>('deleteConfigHistory'); }

  Future<Map<String, Object?>> testQqConnection() async => ((await _call<Map<dynamic, dynamic>>('testQqConnection', null, const Duration(seconds: 12), 1)) ?? {}).map((key, value) => MapEntry('$key', value));
  Future<Map<String, String>> appInfo() async => ((await _call<Map<dynamic, dynamic>>('getAppInfo', null, const Duration(seconds: 12), 2)) ?? {}).map((key, value) => MapEntry('$key', '$value'));
  Future<Map<String, Object?>> pickAndInstallApk() async => ((await _call<Map<dynamic, dynamic>>('pickAndInstallApk')) ?? {}).map((key, value) => MapEntry('$key', value));
  Future<String> updateCachePath() async => await _call<String>('getUpdateCachePath') ?? '';
  Future<Map<String, Object?>> verifyAndInstallUpdate({required String path, required String sha256}) async => ((await _call<Map<dynamic, dynamic>>('verifyAndInstallUpdate', {'path': path, 'sha256': sha256}, const Duration(minutes: 2))) ?? {}).map((key, value) => MapEntry('$key', value));
  Future<Map<String, Object?>> exportBackup() async => ((await _call<Map<dynamic, dynamic>>('exportBackup')) ?? {}).map((key, value) => MapEntry('$key', value));
  Future<Map<String, Object?>> importBackup() async => ((await _call<Map<dynamic, dynamic>>('importBackup', null, const Duration(seconds: 30))) ?? {}).map((key, value) => MapEntry('$key', value));
  Future<List<Map<String, Object?>>> backups() async => (await _call<List<dynamic>>('getBackups', null, const Duration(seconds: 12), 2) ?? const []).whereType<Map>().map((item) => item.map((key, value) => MapEntry('$key', value))).toList();
  Future<Map<String, Object?>> restoreBackupFile(String path) async => ((await _call<Map<dynamic, dynamic>>('restoreBackupFile', {'path': path}, const Duration(seconds: 30))) ?? {}).map((key, value) => MapEntry('$key', value));
  Future<Map<String, String>> defaultRole() async => ((await _call<Map<dynamic, dynamic>>('getDefaultRole')) ?? {}).map((key, value) => MapEntry('$key', '$value'));
  Future<void> saveDefaultRole({String id = '', required String name, required String prompt}) async { await _call<void>('saveDefaultRole', {'id': id, 'name': name, 'prompt': prompt}); }
  Future<List<RoleCard>> roles() async => (await _call<List<dynamic>>('getRoles', null, const Duration(seconds: 12), 2) ?? const []).whereType<Map>().map(RoleCard.fromMap).toList();
  Future<void> saveRoleCard(RoleCard role) async { await _call<void>('saveRoleCard', role.toMap()); }
  Future<void> deleteRoleCard(String id) async { await _call<void>('deleteRoleCard', {'id': id}); }
  Future<Map<String, Object?>> exportRoleCard(String json) async => ((await _call<Map<dynamic, dynamic>>('exportRoleCard', {'json': json})) ?? {}).map((key, value) => MapEntry('$key', value));
  Future<String?> importRoleCard() async => await _call<String>('importRoleCard', null, const Duration(seconds: 30));
  Future<void> clearData(String kind) async { await _call<void>('clearData', {'kind': kind}); }
  Future<void> openBatteryOptimizationSettings() async { await _call<void>('openBatteryOptimizationSettings'); }
  Future<void> openNotificationSettings() async { await _call<void>('openNotificationSettings'); }
}

class RuntimeBridgeException implements Exception {
  const RuntimeBridgeException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

