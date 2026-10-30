import 'dart:async';
import 'package:flutter/services.dart';
import '../models/public_config.dart';
import '../models/runtime_log.dart';
import '../models/runtime_state.dart';

class RuntimeBridge {
  static const _methods = MethodChannel('qq_bot_cp/runtime');
  static const _events = EventChannel('qq_bot_cp/runtime_events');

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

  Future<void> start() => _methods.invokeMethod<void>('startRuntime');
  Future<void> stop() => _methods.invokeMethod<void>('stopRuntime');
  Future<void> restart() => _methods.invokeMethod<void>('restartRuntime');

  Future<RuntimeState> state() async {
    final raw = await _methods.invokeMapMethod<String, Object?>('getRuntimeState') ?? {};
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
    );
  }

  Future<PublicConfig> config() async {
    final raw = await _methods.invokeMapMethod<String, Object?>('getPublicConfig') ?? {};
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
      _methods.invokeMethod<void>('saveConfig', {
        'protocol': protocol, 'model': model, 'baseUrl': baseUrl,
        'appId': appId, 'secret': secret, 'apiKey': apiKey,
      });

  Future<List<AiConfigHistory>> configHistory() async {
    final raw = await _methods.invokeListMethod<dynamic>('getConfigHistory') ?? const [];
    return raw.whereType<Map>().map((item) => AiConfigHistory(
      protocol: '${item['protocol'] ?? ''}',
      model: '${item['model'] ?? ''}',
      baseUrl: '${item['baseUrl'] ?? ''}',
    )).toList();
  }

  Future<void> deleteConfigHistory() => _methods.invokeMethod<void>('deleteConfigHistory');

  Future<Map<String, Object?>> testQqConnection() async => await _methods.invokeMapMethod<String, Object?>('testQqConnection') ?? {};
  Future<Map<String, String>> appInfo() async => (await _methods.invokeMapMethod<String, Object?>('getAppInfo') ?? {}).map((key, value) => MapEntry(key, '$value'));
  Future<Map<String, Object?>> pickAndInstallApk() async => await _methods.invokeMapMethod<String, Object?>('pickAndInstallApk') ?? {};
  Future<String> updateCachePath() async => await _methods.invokeMethod<String>('getUpdateCachePath') ?? '';
  Future<Map<String, Object?>> verifyAndInstallUpdate({required String path, required String sha256}) async => await _methods.invokeMapMethod<String, Object?>('verifyAndInstallUpdate', {'path': path, 'sha256': sha256}) ?? {};
  Future<Map<String, Object?>> exportBackup() async => await _methods.invokeMapMethod<String, Object?>('exportBackup') ?? {};
  Future<Map<String, Object?>> importBackup() async => await _methods.invokeMapMethod<String, Object?>('importBackup') ?? {};
  Future<Map<String, String>> defaultRole() async => (await _methods.invokeMapMethod<String, Object?>('getDefaultRole') ?? {}).map((key, value) => MapEntry(key, '$value'));
  Future<void> saveDefaultRole({required String name, required String prompt}) => _methods.invokeMethod<void>('saveDefaultRole', {'name': name, 'prompt': prompt});
  Future<void> clearData(String kind) => _methods.invokeMethod<void>('clearData', {'kind': kind});
}

