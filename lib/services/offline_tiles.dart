import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// 随包内置的「低清底图」（v2.1.89）
///
/// ------------------------------------------------------------
/// 用户要求：**把底图压进安装包，打开地图秒出图，放大后再联网拉清晰图层**。
///
/// 做法：
///   · `assets/tiles/img/{z}/{x}_{y}.webp` 里随包带一份 z0~z8、覆盖中国范围的
///     卫星瓦片（与在线底图同源：星图地球 img/webp，球面墨卡托、未加偏），
///     整个包约 20MB，`assets/tiles/manifest.json` 记着版本与全部瓦片清单；
///   · MapLibre 原生内核读不了 Flutter 资源，所以首次使用时把这份瓦片
///     **解到应用支持目录**（一次性的，之后直接用文件）；
///   · 样式里低清层指向 `file://<dir>/{z}/{x}/{y}.webp`，z9 以上仍走网络，
///     网络瓦片没回来之前，下面那层「放大后的低清图」先顶着 —— 这就是
///     用户要的「秒加载 → 放大后二次联网变清晰」。
///
/// 为什么不用 zip：Flutter 资源本来就是一个「按需读取」的包，zip 还得再
/// 引一个解压依赖；这里瓦片本身就是 webp（已压缩），再套 zip 也压不下去。
class OfflineTiles {
  OfflineTiles._();

  /// 清单（版本 + 全部瓦片路径）
  static const String manifestAsset = 'assets/tiles/manifest.json';

  /// 随包瓦片的最大层级（超过它的图一律走网络）
  static const int maxZoom = 8;

  static String? _dir;
  static bool _bundled = false;
  static int _count = 0;
  static Future<void>? _task;

  /// 解压目录（null = 没有随包瓦片 / 还没解完 / 解压失败）
  static String? get dir => _dir;

  /// 是否已经可以直接用本地瓦片
  static bool get ready => _dir != null;

  /// 随包瓦片张数（诊断用）
  static int get tileCount => _count;

  /// 包里到底有没有带瓦片
  static bool get bundled => _bundled;

  /// 给 MapLibre 样式用的瓦片地址模板（未就绪时返回 null）
  static String? get tileTemplate =>
      _dir == null ? null : 'file://$_dir/{z}/{x}/{y}.webp';

  /// 本地瓦片文件路径（未就绪 / 超出随包层级时返回 null）
  ///
  /// 供 Dart 版内核（flutter_map）直接按文件读，两条内核用同一份离线包。
  static String? tileFile(int z, int x, int y) {
    final d = _dir;
    if (d == null || z > maxZoom) return null;
    return '$d/$z/$x/$y.webp';
  }

  /// 解压随包瓦片（幂等，重复调用共享同一个 Future）
  ///
  /// ★ 只在「首次使用 / 换版本」时真的写盘：目录里的 `.ok` 记着上次写完的
  ///   张数，张数对得上就直接复用，不重复搬 2000 个文件。
  static Future<void> ensureReady() => _task ??= _prepare();

  static Future<void> _prepare() async {
    try {
      final raw = await rootBundle.loadString(manifestAsset);
      final m = jsonDecode(raw);
      if (m is! Map) return;
      final list =
          ((m['tiles'] as List?) ?? const []).map((e) => '$e').toList();
      if (list.isEmpty) return;
      _bundled = true;

      final ver = '${m['version'] ?? 'v1'}';
      final base = await getApplicationSupportDirectory();
      final target = Directory('${base.path}/map_offline/$ver');
      final stamp = File('${target.path}/.ok');

      // 已经解过 → 直接复用
      if (await stamp.exists()) {
        final n = int.tryParse((await stamp.readAsString()).trim()) ?? 0;
        if (n >= list.length) {
          _dir = target.path;
          _count = n;
          return;
        }
      }

      await target.create(recursive: true);
      var done = 0;
      // 分批发：一次读 16 个资源再统一落盘，既不太占内存也不至于串行慢
      const batch = 16;
      for (var i = 0; i < list.length; i += batch) {
        final slice = list.skip(i).take(batch).toList();
        await Future.wait(slice.map((key) async {
          // key 形如 "8/208_104"
          final slash = key.indexOf('/');
          if (slash <= 0) return;
          final z = key.substring(0, slash);
          final xy = key.substring(slash + 1);
          final us = xy.indexOf('_');
          if (us <= 0) return;
          final x = xy.substring(0, us);
          final y = xy.substring(us + 1);
          final out = File('${target.path}/$z/$x/$y.webp');
          if (await out.exists()) {
            done++;
            return;
          }
          try {
            final data =
                await rootBundle.load('assets/tiles/img/$z/${x}_$y.webp');
            await out.parent.create(recursive: true);
            await out.writeAsBytes(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
                flush: false);
            done++;
          } catch (_) {
            // 单张缺失不影响整包：其余瓦片照常可用
          }
        }));
      }
      await stamp.writeAsString('$done', flush: true);
      if (done > 0) {
        _dir = target.path;
        _count = done;
      }
      debugPrint('[OfflineTiles] 随包底图就绪：$done 张 → ${target.path}');
    } catch (e) {
      // 解不出来就当作没有随包瓦片：地图退回「低清层走网络」，不影响使用
      debugPrint('[OfflineTiles] 解压失败（退回在线低清层）：$e');
    }
  }

  /// 测试 / 诊断用：清掉解压结果
  @visibleForTesting
  static void resetForTest() {
    _dir = null;
    _bundled = false;
    _count = 0;
    _task = null;
  }

  /// 测试用：直接把「已解压目录」指过去（跳过真正的落盘）
  @visibleForTesting
  static void debugSetDir(String? path, {int count = 0}) {
    _dir = path;
    _count = count;
  }
}
