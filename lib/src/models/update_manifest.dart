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
}
