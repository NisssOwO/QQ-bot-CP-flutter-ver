import 'dart:convert';
import 'dart:isolate';

/// Runs JSON decoding away from Flutter's UI isolate.
Future<Object?> decodeJsonInBackground(String source) {
  return Isolate.run<Object?>(() => jsonDecode(source));
}
