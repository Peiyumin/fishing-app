import 'dart:io';
import 'dart:math' show cos, pi;

import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/services/geo_bounds.dart';

/// 地图分级加载 + 缩放上限回归（v2.1.22）
///
/// 用户提了两件事：
///   1. 第一次打开地图只加载定位点周围 50km 的高清图，更远用概览（模糊）；
///      拖动或放大时在范围内自动加载对应级别的高清瓦片。
///   2. 地图放大后不加载、一片模糊。
///
/// 第 2 点的根因是相机没设上限：原生默认允许到 22 级，而瓦片只到 18 级，
/// 超过 18 之后 MapLibre 不再请求新瓦片，只把 18 级图放大 16 倍。
///
/// 这里把「50km 圈算得对不对」和「上限有没有写」都钉成断言。
void main() {
  group('boundsAroundKm 数学正确', () {
    test('阜阳附近 50km：南北跨度约 100km，东西按纬度收缩', () {
      const lat = 32.89, lng = 115.81, km = 50.0;
      final b = boundsAroundKm(lat, lng, km);

      expect(b.length, 4);
      final west = b[0], south = b[1], east = b[2], north = b[3];

      // 中心对称
      expect((west + east) / 2, closeTo(lng, 1e-9));
      expect((south + north) / 2, closeTo(lat, 1e-9));

      // 南北：50km ≈ 0.449 度，全跨度 ≈ 100km
      final dLat = north - lat;
      expect(dLat, closeTo(50 / 111.32, 1e-6));
      expect(dLat * 2 * 111.32, closeTo(100, 0.01));

      // 东西：必须比南北宽（cos 32.89° ≈ 0.84 → 约 1.19 倍）
      final dLng = east - lng;
      expect(dLng, greaterThan(dLat),
          reason: '同一纬度下，1 度经度的地面距离比 1 度纬度短，所以经度半径必须更大');

      // 用球面距离反算：东西两端到中心的实际距离也该是 50km
      final kmPerDegLng = 111.32 * cos(lat * pi / 180);
      expect(dLng * kmPerDegLng, closeTo(50, 0.05));
    });

    test('高纬度经度半径自动放大（否则 50km 圈会被拉成窄长条）', () {
      final low = boundsAroundKm(10, 100, 50);
      final high = boundsAroundKm(60, 100, 50);
      final dLngLow = low[2] - 100;
      final dLngHigh = high[2] - 100;
      // cos10°≈0.985、cos60°=0.5 → 比值约 1.97
      expect(dLngHigh, greaterThan(dLngLow * 1.8),
          reason: '60°N 的 cos 只有 0.5，经度半径应该接近赤道附近的 2 倍');
    });

    test('经度跨 180 度时被夹回合法范围', () {
      final b = boundsAroundKm(0, 179.9, 50);
      expect(b[0], greaterThanOrEqualTo(-180.0));
      expect(b[2], lessThanOrEqualTo(180.0));
    });

    test('极地附近不会因为 cos→0 炸成无穷大', () {
      final b = boundsAroundKm(89.9, 0, 50);
      for (final v in b) {
        expect(v.isFinite, isTrue);
      }
      expect(b[1], greaterThanOrEqualTo(-85.0));
      expect(b[3], lessThanOrEqualTo(85.0));
    });
  });

  group('底图样式：分级加载', () {
    late String src;

    setUpAll(() {
      final f = File('lib/screens/spot_map_gl.dart');
      expect(f.existsSync(), isTrue);
      src = f.readAsStringSync();
    });

    test('必须有低清概览层 sat-low，且最高级别压得很低', () {
      expect(src.contains("'sat-low'"), isTrue,
          reason: '没有低清层，50km 外就是空白而不是"模糊概览"');
      // 取 sat-low 定义段（到下一个 source 名为止）
      final i = src.indexOf("'sat-low': {");
      expect(i, greaterThan(0));
      final block = src.substring(i, i + 400);
      final m = RegExp(r"'maxzoom':\s*(\d+)").firstMatch(block);
      expect(m, isNotNull, reason: 'sat-low 必须显式限级别');
      expect(int.parse(m!.group(1)!), lessThanOrEqualTo(9),
          reason: '低清层级别太高的话，缩小到 100km 视野时圈内外一样清楚，分级就看不出来了');
    });

    test('高清层 sat 必须带 bounds（范围外不请求瓦片）', () {
      final i = src.indexOf("'sat': {");
      expect(i, greaterThan(0));
      final block = src.substring(i, i + 400);
      expect(block.contains("'bounds'"), isTrue,
          reason: "MapLibre 只认 source 的 bounds，没有它就会全图拉高清，50km 限制形同虚设");
      expect(block.contains('minzoom'), isTrue);
    });

    test('高清层 maxzoom 必须等于瓦片源真实最大级别', () {
      final i = src.indexOf("'sat': {");
      final block = src.substring(i, i + 400);
      expect(block.contains('maxNativeZoom'), isTrue,
          reason: '写死数字容易和底图源脱节，必须引用 maxNativeZoom');
    });
  });

  group('相机缩放上限', () {
    late String src;

    setUpAll(() {
      final f = File('lib/screens/spot_map_gl.dart');
      src = f.readAsStringSync();
    });

    test('必须设置 minMaxZoomPreference，上限跟瓦片源一致', () {
      expect(src.contains('minMaxZoomPreference'), isTrue,
          reason: '不设上限的话相机会放到 22 级，超过 18 级后不再请求瓦片、'
              '只是把 18 级图放大 16 倍 —— 就是用户说的「放大后一片模糊」');
      // ★ 用 lastIndexOf：这个词在注释里先出现过一次，
      //   indexOf 会截到注释段，看不到真正的构造参数
      final i = src.lastIndexOf('minMaxZoomPreference');
      final block = src.substring(i, i + 200);
      expect(block.contains('maxNativeZoom'), isTrue,
          reason: '上限必须绑定瓦片源的最大级别，不能写死');
    });
  });
}
