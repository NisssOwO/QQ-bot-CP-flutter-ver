import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp/src/models/update_manifest.dart';

UpdateManifest validManifest() => UpdateManifest(
      versionName: '0.2.0',
      versionCode: 2,
      abi: 'arm64-v8a',
      apkUrl: 'https://example.com/app.apk',
      sha256: 'a' * 64,
      releaseNotes: 'test',
      sizeBytes: 1024,
    );

void main() {
  test('accepts a complete signed update manifest', () {
    expect(validManifest().validate, returnsNormally);
  });

  test('rejects an incomplete or unsafe manifest', () {
    const invalid = UpdateManifest(
      versionName: '',
      versionCode: 0,
      abi: 'mips',
      apkUrl: 'file:///tmp/app.apk',
      sha256: 'bad',
      releaseNotes: '',
      sizeBytes: 0,
    );
    expect(invalid.validate, throwsA(isA<FormatException>()));
  });
}
