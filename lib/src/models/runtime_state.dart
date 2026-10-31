import 'package:flutter/foundation.dart';

@immutable
class RuntimeState {
  const RuntimeState({
    this.status = RuntimeStatus.stopped,
    this.phase = '未启动',
    this.message = '',
    this.elapsedMs = 0,
    this.exitCode,
    this.qqStatus = '未知',
    this.aiStatus = '未知',
    this.networkStatus = '未知',
    this.reconnectAttempts = 0,
    this.nextRetryMs = 0,
    this.qqFailureCount = 0,
    this.aiFailureCount = 0,
    this.processAlive = false,
    this.userStopped = false,
  });

  final RuntimeStatus status;
  final String phase;
  final String message;
  final int elapsedMs;
  final int? exitCode;
  final String qqStatus;
  final String aiStatus;
  final String networkStatus;
  final int reconnectAttempts;
  final int nextRetryMs;
  final int qqFailureCount;
  final int aiFailureCount;
  final bool processAlive;
  final bool userStopped;

  RuntimeState copyWith({
    RuntimeStatus? status,
    String? phase,
    String? message,
    int? elapsedMs,
    int? exitCode,
    String? qqStatus,
    String? aiStatus,
    String? networkStatus,
    int? reconnectAttempts,
    int? nextRetryMs,
    int? qqFailureCount,
    int? aiFailureCount,
    bool? processAlive,
    bool? userStopped,
  }) => RuntimeState(
        status: status ?? this.status,
        phase: phase ?? this.phase,
        message: message ?? this.message,
        elapsedMs: elapsedMs ?? this.elapsedMs,
        exitCode: exitCode ?? this.exitCode,
        qqStatus: qqStatus ?? this.qqStatus,
        aiStatus: aiStatus ?? this.aiStatus,
        networkStatus: networkStatus ?? this.networkStatus,
        reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
        nextRetryMs: nextRetryMs ?? this.nextRetryMs,
        qqFailureCount: qqFailureCount ?? this.qqFailureCount,
        aiFailureCount: aiFailureCount ?? this.aiFailureCount,
        processAlive: processAlive ?? this.processAlive,
        userStopped: userStopped ?? this.userStopped,
      );
}

enum RuntimeStatus { stopped, starting, online, reconnecting, failed, stopping }
