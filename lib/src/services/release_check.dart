import 'dart:convert';
import 'dart:io';

import '../models/update_manifest.dart';
import 'background_tasks.dart';
import 'update_service.dart';

/// GitHub 的 latest release 是“最新版本”的唯一来源。
///
/// 之前读的是仓库里手写的 manifest，它停在 0.1.4 而应用已经 0.1.6，界面又没有和
/// 已安装版本比较，于是永远显示“下载并安装更新”，点下去还会把旧包拉回来。
const latestReleaseApiUrl = 'https://api.github.com/repos/NisssOwO/QQ-bot-CP-flutter-ver/releases/latest';

/// 一次检查的结果：要么已是最新，要么给出可下载的清单，要么带一条错误原因。
class ReleaseCheckResult {
  const ReleaseCheckResult({required this.installed, this.latest, this.manifest, this.publishedAt, this.error});

  final String installed;
  final String? latest;
  final UpdateManifest? manifest;
  final DateTime? publishedAt;
  final String? error;

  bool get failed => error != null;
  bool get hasUpdate => manifest != null;
  bool get upToDate => error == null && manifest == null;
}

class ReleaseChecker {
  const ReleaseChecker();

  Future<ReleaseCheckResult> run(String installedVersion) async {
    final installed = installedVersion.trim();
    try {
      final release = await _fetchLatest();
      return _decide(installed, release);
    } catch (error) {
      // 直连 api.github.com 在部分网络下不可用，退回到仓库清单；清单同样要做版本比较，
      // 否则一份落后的清单又会被当成新版本。
      try {
        final release = await _fetchManifest();
        return _decide(installed, release);
      } catch (_) {
        return ReleaseCheckResult(installed: installed, error: _describe(error));
      }
    }
  }

  ReleaseCheckResult _decide(String installed, _Release release) {
    final newer = compareVersions(release.versionName, installed) > 0;
    if (!newer) {
      return ReleaseCheckResult(installed: installed, latest: release.versionName, publishedAt: release.publishedAt);
    }
    return ReleaseCheckResult(
      installed: installed,
      latest: release.versionName,
      publishedAt: release.publishedAt,
      manifest: UpdateManifest(
        versionName: release.versionName,
        versionCode: release.versionCode,
        abi: 'arm64-v8a',
        apkUrl: release.apkUrl,
        sha256: release.sha256,
        releaseNotes: release.notes,
        sizeBytes: release.sizeBytes,
      ),
    );
  }

  Future<_Release> _fetchLatest() async {
    final json = await _getJson(latestReleaseApiUrl) as Map<String, dynamic>;
    final tag = '${json['tag_name'] ?? ''}'.trim();
    if (tag.isEmpty) throw const FormatException('发布信息缺少版本号');
    final versionName = tag.startsWith('v') || tag.startsWith('V') ? tag.substring(1) : tag;
    Map<String, dynamic>? apk;
    for (final asset in (json['assets'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
      if ('${asset['name'] ?? ''}'.endsWith('.apk')) {
        apk = asset;
        break;
      }
    }
    if (apk == null) throw const FormatException('这次发布没有附带 APK');
    final digest = '${apk['digest'] ?? ''}'.trim().toLowerCase();
    if (!digest.startsWith('sha256:')) throw const FormatException('这次发布没有提供 SHA-256');
    final url = '${apk['browser_download_url'] ?? ''}';
    if (url.isEmpty) throw const FormatException('发布里的 APK 地址为空');
    return _Release(
      versionName: versionName,
      versionCode: _versionCode(versionName),
      apkUrl: url,
      sha256: digest.substring('sha256:'.length),
      sizeBytes: (apk['size'] as num?)?.toInt() ?? 0,
      notes: _notes('${json['body'] ?? ''}'),
      publishedAt: DateTime.tryParse('${json['published_at'] ?? ''}'),
    );
  }

  Future<_Release> _fetchManifest() async {
    final json = await _getJson(defaultUpdateManifestUrl) as Map<String, dynamic>;
    final manifest = UpdateManifest.fromJson(json)..validate();
    return _Release(
      versionName: manifest.versionName,
      versionCode: manifest.versionCode,
      apkUrl: manifest.apkUrl,
      sha256: manifest.sha256,
      sizeBytes: manifest.sizeBytes,
      notes: manifest.releaseNotes,
      publishedAt: null,
    );
  }

  Future<Object?> _getJson(String endpoint) async {
    final uri = Uri.tryParse(endpoint);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) throw const FormatException('更新地址无效');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'QQ-bot-CP');
      final response = await request.close().timeout(const Duration(seconds: 10));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) throw HttpException('更新检查返回 HTTP ${response.statusCode}');
      return await decodeJsonInBackground(body);
    } finally {
      client.close(force: true);
    }
  }

  /// 只取正文里能看的几行，发布说明常带安装须知，整段塞进卡片会撑爆布局。
  String _notes(String body) {
    final lines = body.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty && !line.startsWith('#') && !line.startsWith('|') && !line.startsWith('>'));
    return lines.take(4).join(' · ');
  }

  int _versionCode(String version) {
    final parts = version.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts[0] * 10000 + parts[1] * 100 + parts[2];
  }

  String _describe(Object error) => switch (error) {
        FormatException(:final message) => message,
        HttpException(:final message) => message,
        SocketException() => '连接不上更新服务，请检查网络',
        _ => '$error',
      };
}

/// 比较 `0.1.6` 这类版本号：返回正数表示 [a] 更新。
int compareVersions(String a, String b) {
  List<int> parse(String value) => value
      .split(RegExp(r'[^0-9]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => int.tryParse(part) ?? 0)
      .toList();
  final left = parse(a);
  final right = parse(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < length; index++) {
    final diff = (index < left.length ? left[index] : 0) - (index < right.length ? right[index] : 0);
    if (diff != 0) return diff;
  }
  return 0;
}

class _Release {
  const _Release({required this.versionName, required this.versionCode, required this.apkUrl, required this.sha256, required this.sizeBytes, required this.notes, this.publishedAt});
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String sha256;
  final int sizeBytes;
  final String notes;
  final DateTime? publishedAt;
}