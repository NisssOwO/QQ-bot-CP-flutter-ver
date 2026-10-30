import 'package:flutter/foundation.dart';

@immutable
class RuntimeLogEntry {
  const RuntimeLogEntry({
    required this.time,
    required this.level,
    required this.module,
    required this.message,
    this.elapsedMs,
  });

  final DateTime time;
  final LogLevel level;
  final String module;
  final String message;
  final int? elapsedMs;
}

enum LogLevel { info, warn, error }
