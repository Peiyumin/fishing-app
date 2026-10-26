import 'dart:async';
import 'dart:io';

import '../utils/text_safe.dart';
import 'map_tile_source.dart';

/// 一条线路的自检结果
class TileHealthResult {
  final String name;
  final bool ok;
  final int ms;
  final String detail;

  const TileHealthResult({
    required this.name,
    required this.ok,
    required this.ms,
    required this.detail,
  });

  String get label => ok ? '$name ✓ $ms ms' : '$name ✗ $detail';

  @override
  String toString() => label;
}

/// 底图线路自检
///
/// ------------------------------------------------------------
/// 为什么需要它：用户反馈「在 WiFi 下野钓钓点地图不加载，只显示高德底图那个
/// 页面」。底图是**第三方域名**（星图地球 / 高德），某些 WiFi（公司网、酒店网、
/// 带内容过滤的路由器）会把图片域名直接掐掉或者返回一个 HTML 拦截页 ——
/// 表现就是地图一片空白，而调我们自己的接口（同一个 WiFi）却正常。
///
/// 光「配一个兜底」不够：App 事先不知道这条网络能不能出图。所以在建图前
/// 拿一张**固定的 z5 瓦片**试一次（不占配额、命中 CDN 边缘很快），
/// 通了才用它，不通就换下一家。
///
/// 坐标取 z5 / x26 / y12 —— 覆盖中国中部，三家底图在这个级别都有图。
class TileHealth {
  TileHealth._();

  /// 试探用的瓦片坐标（z5 中国中部）
  static const int probeZ = 5;
  static const int probeX = 26;
  static const int probeY = 12;

  /// 默认超时。2.5 秒是权衡：正常 CDN 200~400ms 就回来了，
  /// 超过 2.5 秒基本可以判定这条网络出不去，再等只是让用户多盯灰屏。
  static const Duration defaultTimeout = Duration(milliseconds: 2500);

  /// 把模板展开成一条真实瓦片地址
  ///
  /// 只给**探测**用：把 {s}/{z}/{x}/{y}/{token}/{tk} 全换成具体值，
  /// 不经过后端代理（要测的就是「这台手机直连能不能出图」）。
  static String buildProbeUrl(TileSource src, {String layer = 'img'}) {
    var tpl = layer == 'vector' ? src.vectorTemplate : src.satelliteTemplate;
    tpl = tpl
        .replaceAll('{s}', '1')
        .replaceAll('{z}', '$probeZ')
        .replaceAll('{x}', '$probeX')
        .replaceAll('{y}', '$probeY');
    src.additionalOptions.forEach((k, v) {
      tpl = tpl.replaceAll('{$k}', v);
    });
    return tpl;
  }

  /// 探一家底图
  ///
  /// 判定「通」的条件必须同时满足：HTTP 200、字节数 > 512、且**不是 HTML**。
  /// 最后一个条件很关键：被 WiFi 拦截时经常回 200 + 一个「请先登录」的
  /// 网页，只看状态码会误判成可用。
  static Future<TileHealthResult> probe(
    TileSource src, {
    Duration timeout = defaultTimeout,
  }) async {
    final name = src.shortName;
    if (!src.usable) {
      return TileHealthResult(
          name: name, ok: false, ms: 0, detail: '没有密钥');
    }
    final url = buildProbeUrl(src);
    final sw = Stopwatch()..start();
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = timeout
        ..idleTimeout = timeout;
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      req.headers.set(HttpHeaders.acceptHeader, 'image/webp,image/*,*/*');
      final resp = await req.close().timeout(timeout);
      final code = resp.statusCode;
      final type = (resp.headers.contentType?.mimeType ?? '').toLowerCase();
      var bytes = 0;
      await for (final chunk in resp.timeout(timeout)) {
        bytes += chunk.length;
        if (bytes > 4096) break; // 够判断了，不整张下完
      }
      sw.stop();
      if (code != 200) {
        return TileHealthResult(
            name: name, ok: false, ms: sw.elapsedMilliseconds, detail: 'HTTP $code');
      }
      if (type.contains('html')) {
        return TileHealthResult(
            name: name,
            ok: false,
            ms: sw.elapsedMilliseconds,
            detail: '被拦截（返回网页）');
      }
      if (bytes < 512) {
        return TileHealthResult(
            name: name,
            ok: false,
            ms: sw.elapsedMilliseconds,
            detail: '图片过小 $bytes B');
      }
      return TileHealthResult(
          name: name, ok: true, ms: sw.elapsedMilliseconds, detail: '$type $bytes B');
    } on TimeoutException {
      sw.stop();
      return TileHealthResult(
          name: name, ok: false, ms: sw.elapsedMilliseconds, detail: '超时');
    } catch (e) {
      sw.stop();
      return TileHealthResult(
          name: name,
          ok: false,
          ms: sw.elapsedMilliseconds,
          detail: _short(e));
    } finally {
      client?.close(force: true);
    }
  }

  /// 依次探一批底图（由调用方按优先级排好序，跳过没有密钥的）
  static Future<List<TileHealthResult>> probeAll(
    List<TileSource> sources, {
    Duration timeout = defaultTimeout,
  }) async {
    final list = <TileHealthResult>[];
    for (final src in sources) {
      if (!src.usable) continue;
      list.add(await probe(src, timeout: timeout));
    }
    return list;
  }

  static String _short(Object e) {
    final s = e.toString().replaceAll('\n', ' ');
    return clipGrapheme(s, 46);
  }
}
