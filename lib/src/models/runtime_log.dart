import 'package:flutter/foundation.dart';

@immutable
class RuntimeLogEntry {
  const RuntimeLogEntry({
    required this.time,
    required this.level,
    required this.module,
    required this.message,
    this.elapsedMs,
    this.runId,
  });

  final DateTime time;
  final LogLevel level;
  final String module;
  final String message;
  final int? elapsedMs;
  final String? runId;
}

enum LogLevel { info, warn, error }
