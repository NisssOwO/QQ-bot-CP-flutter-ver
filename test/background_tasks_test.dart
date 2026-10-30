import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp/src/services/background_tasks.dart';

void main() {
  test('decodes role JSON in a background isolate', () async {
    final value =
        await decodeJsonInBackground('{"id":"custom.demo","prompt":"hello"}');
    expect(value, isA<Map>());
    expect((value as Map)['id'], 'custom.demo');
  });

  test('filters log indexes in a background isolate', () async {
    final indexes = await filterLogIndexesInBackground([
      {'level': 'info', 'module': 'network'},
      {'level': 'error', 'module': 'qq'},
      {'level': 'error', 'module': 'network'},
    ], 'error', 'network');
    expect(indexes, [2]);
  });
}
