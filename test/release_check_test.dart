import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp/src/services/release_check.dart';

void main() {
  group('compareVersions', () {
    test('新版本号更大', () {
      expect(compareVersions('0.1.7', '0.1.6'), greaterThan(0));
      expect(compareVersions('0.2.0', '0.1.9'), greaterThan(0));
      expect(compareVersions('1.0.0', '0.9.9'), greaterThan(0));
    });

    test('旧版本号更小', () {
      expect(compareVersions('0.1.4', '0.1.6'), lessThan(0));
    });

    test('不同位数按数字而不是字符串比较', () {
      expect(compareVersions('0.1.10', '0.1.9'), greaterThan(0));
      expect(compareVersions('0.10.0', '0.9.0'), greaterThan(0));
    });

    test('相同或缺失的数字视为相等', () {
      expect(compareVersions('0.1.6', '0.1.6'), 0);
      expect(compareVersions('v0.1.6', '0.1.6'), 0);
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('', ''), 0);
    });

    test('前缀 v 与附加后缀不影响判断', () {
      expect(compareVersions('v0.1.6', '0.1.5'), greaterThan(0));
      expect(compareVersions('0.1.6-beta', '0.1.6'), 0);
    });
  });

  group('ReleaseCheckResult', () {
    test('没有清单且没有错误就是已是最新', () {
      const result = ReleaseCheckResult(installed: '0.1.6', latest: '0.1.6');
      expect(result.upToDate, isTrue);
      expect(result.hasUpdate, isFalse);
      expect(result.failed, isFalse);
    });

    test('带清单表示有新版本', () {
      const result = ReleaseCheckResult(installed: '0.1.6', latest: '0.1.7');
      expect(result.hasUpdate, isFalse);
      expect(result.upToDate, isTrue);
    });

    test('有错误时不再是已是最新', () {
      const result = ReleaseCheckResult(installed: '0.1.6', error: '连接不上更新服务');
      expect(result.failed, isTrue);
      expect(result.upToDate, isFalse);
      expect(result.hasUpdate, isFalse);
    });
  });
}