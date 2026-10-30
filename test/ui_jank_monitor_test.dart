import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp/src/services/ui_jank_monitor.dart';

void main() {
  test('uses a 32ms warning threshold by default', () {
    expect(UiJankMonitor().warningThreshold, const Duration(milliseconds: 32));
  });
}
