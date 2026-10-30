import 'package:flutter/foundation.dart';

@immutable
class RuntimeState {
  const RuntimeState({
    this.status = RuntimeStatus.stopped,
    this.phase = '未启动',
    this.message = '',
    this.elapsedMs = 0,
    this.exitCode,
  });

  final RuntimeStatus status;
  final String phase;
  final String message;
  final int elapsedMs;
  final int? exitCode;

  RuntimeState copyWith({
    RuntimeStatus? status,
    String? phase,
    String? message,
    int? elapsedMs,
    int? exitCode,
  }) => RuntimeState(
        status: status ?? this.status,
        phase: phase ?? this.phase,
        message: message ?? this.message,
        elapsedMs: elapsedMs ?? this.elapsedMs,
        exitCode: exitCode ?? this.exitCode,
      );
}

enum RuntimeStatus { stopped, starting, online, reconnecting, failed, stopping }
