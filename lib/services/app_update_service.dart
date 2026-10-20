import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';
import 'api_config.dart';

/// 当前 App 版本（发新版时与 pubspec.yaml 的 `version: x.y.z+n` 同步修改）
class AppVersion {
  static const String version = '2.0.0';
  static const int build = 2;
}

/// 服务端下发的更新信息
class UpdateInfo {
  final bool needUpdate;
  final String version;
  final int buildNo;
  final bool force;
  final String downloadUrl;
  final String releaseNotes;

  UpdateInfo({
    required this.needUpdate,
    required this.version,
    required this.buildNo,
    required this.force,
    required this.downloadUrl,
    required this.releaseNotes,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> j) => UpdateInfo(
        needUpdate: j['needUpdate'] == true,
        version: (j['version'] ?? '').toString(),
        buildNo: (j['build_no'] as num?)?.toInt() ?? 0,
        force: j['force'] == true,
        downloadUrl: (j['download_url'] ?? '').toString(),
        releaseNotes: (j['release_notes'] ?? '').toString(),
      );
}

/// 热更新服务：版本检查 + 静默下载 + 跳转安装
class AppUpdateService {
  /// 检查更新。后端不可用或无新版 → null（静默失败，不打扰用户）
  static Future<UpdateInfo?> check() async {
    if (!ApiConfig.enabled) return null;
    try {
      final platform = Platform.isAndroid ? 'android' : 'ios';
      final data = await ApiClient.get('/app/version/check', {
        'platform': platform,
        'current': AppVersion.version,
        'build': AppVersion.build.toString(),
      }) as Map;
      final info = UpdateInfo.fromJson(Map<String, dynamic>.from(data));
      return info.needUpdate ? info : null;
    } catch (_) {
      return null;
    }
  }

  /// 下载安装包到本地，[onProgress] 回调 0~1；失败返回 null
  static Future<String?> download(
    String url,
    void Function(double progress) onProgress,
  ) async {
    try {
      // 安卓优先用外部存储（便于调起安装器）；取不到再退回应用目录
      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
      }
      dir ??= await getApplicationDocumentsDirectory();
      final segs = Uri.parse(url).pathSegments;
      final name = segs.isNotEmpty && segs.last.isNotEmpty
          ? segs.last
          : (Platform.isAndroid ? 'update.apk' : 'update.ipa');
      final file = File('${dir.path}/$name');
      if (await file.exists()) await file.delete();

      final client = HttpClient();
      var req = await client.getUrl(Uri.parse(url));
      var res = await req.close();
      // 跟随 302 跳转（CDN 签名链接），最多 5 跳；跳转后不带认证头
      var hops = 0;
      while (res.isRedirect && hops < 5) {
        final loc = res.headers.value('location');
        if (loc == null) break;
        await res.drain();
        req = await client.getUrl(Uri.parse(loc));
        res = await req.close();
        hops++;
      }
      if (res.statusCode != 200) return null;

      final total = res.contentLength; // -1 表示长度未知
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.close();
      client.close(force: true);
      onProgress(1);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 调起系统安装器安装 apk（安卓）
  static Future<void> installApk(String path) =>
      OpenFilex.open(path, type: 'application/vnd.android.package-archive');
}
