import 'package:flutter/foundation.dart';

@immutable
class UpdateManifest {
  const UpdateManifest({required this.versionName, required this.versionCode, required this.abi, required this.apkUrl, required this.sha256, required this.releaseNotes, required this.sizeBytes});
  final String versionName;
  final int versionCode;
  final String abi;
  final String apkUrl;
  final String sha256;
  final String releaseNotes;
  final int sizeBytes;

  factory UpdateManifest.fromJson(Map<String, dynamic> json) => UpdateManifest(
    versionName: '${json['versionName'] ?? ''}',
    versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
    abi: '${json['abi'] ?? ''}',
    apkUrl: '${json['apkUrl'] ?? ''}',
    sha256: '${json['sha256'] ?? ''}',
    releaseNotes: '${json['releaseNotes'] ?? ''}',
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
  );

  String get sizeLabel => sizeBytes <= 0 ? '未知大小' : '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';

  void validate() {
    if (versionName.trim().isEmpty || versionCode <= 0) {
      throw const FormatException('更新清单版本信息无效');
    }
    if (abi != 'arm64-v8a' && abi != 'armeabi-v7a' && abi != 'x86_64') {
      throw FormatException('不支持的更新 ABI：$abi');
    }
    final uri = Uri.tryParse(apkUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      throw const FormatException('更新 APK 地址无效');
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256)) {
      throw const FormatException('更新清单 SHA-256 无效');
    }
    if (sizeBytes <= 0) throw const FormatException('更新文件大小无效');
  }
}
