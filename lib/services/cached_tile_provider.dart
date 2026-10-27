import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 带「内置离线包 → 磁盘缓存 → 网络」三级优先级的瓦片提供器
///
/// ------------------------------------------------------------
/// 为什么需要它：
///   flutter_map 默认的 NetworkTileProvider 只用 Flutter 的 ImageCache
///   （纯内存，App 一退出就没了）。于是每次冷启动、每次拖到新区域，
///   所有瓦片都要重新走一遍网络 —— 这就是「别人秒开、我们卡死」的根因。
///
/// 三级读取顺序（命中越靠前越快）：
///   1. assets/tiles/...   内置离线包（打进安装包，零网络、零延迟）
///   2. 磁盘缓存          第一次联网后落盘，之后冷启动也秒开
///   3. 网络              只在前两级都没有时才请求，成功后立即落盘
///
/// 另外两件保命的事：
///   - 并发闸门：同时最多 6 个请求，避免一屏几十个瓦片把连接池打满
///   - 失败兜底：连续失败达到阈值就回调给页面，由页面降级到高德底图
class CachedTileProvider extends TileProvider {
  CachedTileProvider({
    required this.layer,
    super.headers,
    this.onNetworkFail,
    this.onTileOk,
  });

  /// 图层名（img / cia / vec），决定磁盘子目录与内置包路径
  final String layer;

  /// 网络连续失败时的回调（由页面决定是否降级到高德）
  final VoidCallback? onNetworkFail;

  /// 任意一块瓦片成功拿到数据时的回调（用于「看门狗」判断地图是否活了）
  final VoidCallback? onTileOk;

  /// 同时最多几个瓦片请求
  static const int maxConcurrent = 6;

  /// 磁盘缓存上限（字节），超了按最久未使用清理
  static const int maxCacheBytes = 220 * 1024 * 1024;

  static final http.Client _client = http.Client();
  static final _Gate _gate = _Gate(maxConcurrent);

  static Directory? _root;
  static bool _bundled = false;
  static Future<void>? _ready;
  static int _failStreak = 0;

  /// 是否随包内置了离线瓦片（assets/tiles/manifest.json 存在即为 true）
  static bool get hasBundledTiles => _bundled;

  // ---- 运行统计（图层面板里显示，用来判断缓存到底有没有生效）----
  static int statDisk = 0;   // 磁盘命中
  static int statNet = 0;    // 网络下载
  static int statFail = 0;   // 失败

  /// 一行可读的统计，例：缓存 82 · 网络 14 · 失败 0
  static String get statLine => '缓存 $statDisk · 网络 $statNet · 失败 $statFail';

  /// 初始化：准备缓存目录、探测内置包、后台清理超量缓存
  static Future<void> init() {
    return _ready ??= _init();
  }

  static Future<void> _init() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/map_tiles');
      if (!await dir.exists()) await dir.create(recursive: true);
      _root = dir;
    } catch (_) {
      // 拿不到目录就退化成「纯网络」，地图照样能看
    }
    try {
      await rootBundle.load('assets/tiles/manifest.json');
      _bundled = true;
    } catch (_) {
      _bundled = false;
    }
    // 清理延后 8 秒再做，且全程异步 I/O，绝不占 UI 线程
    Timer(const Duration(seconds: 8), () => unawaited(_prune()));
  }

  /// 命中一次网络成功
  static void _markOk() => _failStreak = 0;

  /// 记录一次失败，返回累计连续失败次数
  static int _markFail() {
    _failStreak++;
    return _failStreak;
  }

  /// 缓存文件路径：map_tiles/{layer}/{z}/{x}_{y}.bin
  static String? _filePath(String layer, int z, int x, int y) {
    final root = _root;
    if (root == null) return null;
    return '${root.path}/$layer/$z/${x}_$y.bin';
  }

  /// 内置包资源路径：assets/tiles/{layer}/{z}/{x}_{y}.webp
  static String? _assetPath(String layer, int z, int x, int y) {
    if (!_bundled) return null;
    final ext = layer == 'img' ? 'webp' : 'png';
    return 'assets/tiles/$layer/$z/${x}_$y.$ext';
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return _TileImage(
      url: url,
      layer: layer,
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
      headers: headers,
      onFail: onNetworkFail,
      onOk: onTileOk,
    );
  }

  /// 当前地图瓦片缓存占用字节数（设置页「清除地图缓存」显示用）
  static Future<int> cacheBytes() async {
    final root = _root;
    if (root == null) return 0;
    try {
      if (!await root.exists()) return 0;
      var total = 0;
      await for (final e in root.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// 清空地图瓦片缓存（只删 map_tiles 目录里的文件，不动任何用户数据）
  static Future<void> clearCache() async {
    final root = _root;
    if (root == null) return;
    try {
      if (!await root.exists()) return;
      await for (final e in root.list(followLinks: false)) {
        try {
          await e.delete(recursive: true);
        } catch (_) {}
      }
      // 清完顺手把内存里的瓦片解码缓存也丢了，否则还会显示旧图
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      statDisk = 0;
    } catch (_) {
      // 删不掉就算了，不影响使用
    }
  }

  /// 字节数 → 人类可读（3.5 MB / 812 KB）
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    final mb = bytes / (1024 * 1024);
    return mb >= 10 ? '${mb.toStringAsFixed(0)} MB' : '${mb.toStringAsFixed(1)} MB';
  }

  /// 清理：超过上限就按最后修改时间删掉最旧的一批，降到 60%
  static Future<void> _prune() async {
    final root = _root;
    if (root == null) return;
    try {
      if (!await root.exists()) return;
      final files = <File>[];
      // 上限 20000 个，防止异常目录把清理本身变成负担
      await for (final e in root.list(recursive: true, followLinks: false)) {
        if (e is File) files.add(e);
        if (files.length >= 20000) break;
      }
      // 文件不多就不折腾（避免每次启动都扫盘）
      if (files.length < 2000) return;

      var total = 0;
      final entries = <MapEntry<File, int>>[];
      for (final f in files) {
        try {
          final len = await f.length();
          final mt = (await f.lastModified()).millisecondsSinceEpoch;
          total += len;
          entries.add(MapEntry(f, mt));
        } catch (_) {}
      }
      if (total <= maxCacheBytes) return;

      entries.sort((a, b) => a.value.compareTo(b.value)); // 最旧在前
      final target = (maxCacheBytes * 0.6).toInt();
      for (final e in entries) {
        if (total <= target) break;
        try {
          final len = await e.key.length();
          await e.key.delete();
          total -= len;
        } catch (_) {}
      }
    } catch (_) {
      // 清理失败不影响使用
    }
  }
}

/// 单个瓦片的图片加载：磁盘 → 内置包 → 网络
class _TileImage extends ImageProvider<_TileImage> {
  _TileImage({
    required this.url,
    required this.layer,
    required this.z,
    required this.x,
    required this.y,
    required this.headers,
    this.onFail,
    this.onOk,
  });

  final String url;
  final String layer;
  final int z;
  final int x;
  final int y;
  final Map<String, String> headers;
  final VoidCallback? onFail;
  final VoidCallback? onOk;

  @override
  Future<_TileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_TileImage>(this);

  @override
  ImageStreamCompleter loadImage(_TileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(),
      scale: 1,
      debugLabel: url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<_TileImage>('瓦片', this),
      ],
    );
  }

  Future<ui.Codec> _loadAsync() async {
    Uint8List? bytes;

    // ① 磁盘缓存
    String? path;
    try {
      await CachedTileProvider.init();
      path = CachedTileProvider._filePath(layer, z, x, y);
      if (path != null) {
        final f = File(path);
        if (await f.exists()) {
          final b = await f.readAsBytes();
          if (b.isNotEmpty) {
            bytes = b;
            CachedTileProvider.statDisk++;
          }
        }
      }
    } catch (_) {}

    // ② 内置离线包
    if (bytes == null) {
      final asset = CachedTileProvider._assetPath(layer, z, x, y);
      if (asset != null) {
        try {
          final data = await rootBundle.load(asset);
          if (data.lengthInBytes > 0) {
            bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          }
        } catch (_) {}
      }
    }

    // ③ 网络
    if (bytes == null) {
      bytes = await _fetch();
    }

    if (bytes == null) {
      // 三级全失败：返回 1x1 透明图，让底图背景透出来，
      // 而不是抛异常把整层瓦片打成错误块
      return ui.instantiateImageCodec(TileProvider.transparentImage);
    }
    onOk?.call();
    return ui.instantiateImageCodec(bytes);
  }

  Future<Uint8List?> _fetch() async {
    try {
      final resp = await CachedTileProvider._gate.run(() => CachedTileProvider._client
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10)));
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
        _hitFail();
        return null;
      }
      CachedTileProvider._markOk();
      CachedTileProvider.statNet++;
      final data = resp.bodyBytes;
      // 落盘（不等待，失败也无所谓）
      final path = CachedTileProvider._filePath(layer, z, x, y);
      if (path != null) unawaited(_save(path, data));
      return data;
    } catch (_) {
      _hitFail();
      return null;
    }
  }

  void _hitFail() {
    CachedTileProvider.statFail++;
    final n = CachedTileProvider._markFail();
    // 连续 12 个瓦片失败 = 不是偶发抖动，通知页面降级
    if (n >= 12) {
      CachedTileProvider._failStreak = 0;
      onFail?.call();
    }
  }

  Future<void> _save(String path, Uint8List data) async {
    try {
      final f = File(path);
      if (!await f.parent.exists()) await f.parent.create(recursive: true);
      final tmp = File('$path.tmp');
      await tmp.writeAsBytes(data, flush: false);
      await tmp.rename(path);
    } catch (_) {}
  }

  @override
  bool operator ==(Object other) =>
      other is _TileImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// 简单并发闸门（同时最多 N 个异步任务）
class _Gate {
  _Gate(this.max);

  final int max;
  int _active = 0;
  final Queue<Completer<void>> _queue = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= max) {
      final c = Completer<void>();
      _queue.add(c);
      await c.future;
    }
    _active++;
    try {
      return await task();
    } finally {
      _active--;
      if (_queue.isNotEmpty) _queue.removeFirst().complete();
    }
  }
}
