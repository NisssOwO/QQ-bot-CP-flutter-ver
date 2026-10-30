import 'package:flutter/foundation.dart';

@immutable
class EndpointTestResult {
  const EndpointTestResult({required this.ok, required this.stage, required this.message, this.statusCode, this.elapsedMs});
  final bool ok;
  final String stage;
  final String message;
  final int? statusCode;
  final int? elapsedMs;
}
