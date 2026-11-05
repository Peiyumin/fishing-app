// 坐标系一致性护栏（v42 后端配套）
//
// 背景：后台批量导入的钓点有的是从高德爬的（GCJ-02），有的来自 GPS（WGS-84）。
// 项目约定 **入库一律 WGS-84**，显示时按底图决定要不要纠偏：
//   · 星图地球 / 天地图 = WGS-84 → 原样画
//   · 高德 = GCJ-02 → 画之前转
// 这个约定只要有一处实现走偏，用户看到的就是「钓点偏了 400 米」。
//
// 本文件钉三件事：
//   ① Dart 与 PHP（后端 lib/coord.php）算出来的坐标必须是同一个数
//      —— 两边各写一遍公式，最容易在「迭代次数 / 常量」上打架；
//   ② 地图页不许再手写 wgs84ToGcj02 去 move 视野（必须走底图投影），
//      否则换成星图地球底图后，点列表跳过去会偏 400 米；
//   ③ 往返精度：GCJ→WGS→GCJ 残差 < 0.5 米。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/utils/coord_transform.dart';

void main() {
  group('① Dart 与 PHP 的转换结果一致', () {
    // 下面这些期望值是 PHP 端 lib/coord.php 实际算出来的（v42_coord_test.php 同源）
    const cases = <List<double>>[
      // [wgsLat, wgsLng, gcjLat, gcjLng]
      [39.90923, 116.397428, 39.910633506386, 116.40367162596], // 北京天安门
    ];

    test('同一组坐标，Dart 与 PHP 结果相同（误差 < 1e-9 度 ≈ 0.1 毫米）', () {
      for (final c in cases) {
        final g = CoordTransform.wgs84ToGcj02(c[0], c[1]);
        expect((g[0] - c[2]).abs(), lessThan(1e-9),
            reason: '纬度不一致：Dart ${g[0]} / PHP ${c[2]}');
        expect((g[1] - c[3]).abs(), lessThan(1e-9),
            reason: '经度不一致：Dart ${g[1]} / PHP ${c[3]}');
      }
    });
  });

  group('② 往返精度', () {
    const pts = <List<double>>[
      [39.90923, 116.397428], // 北京
      [30.2741, 120.1551], // 杭州
      [23.1291, 113.2644], // 广州
      [34.1466, 113.4857], // 河南禹州（真实批量导入的数据在这一带）
    ];

    test('WGS→GCJ→WGS 残差 < 0.5 米', () {
      for (final p in pts) {
        final g = CoordTransform.wgs84ToGcj02(p[0], p[1]);
        final back = CoordTransform.gcj02ToWgs84(g[0], g[1]);
        final miss = CoordTransform.distanceMeters(p[0], p[1], back[0], back[1]);
        expect(miss, lessThan(0.5), reason: '(${p[0]}, ${p[1]}) 残差 ${miss}m');
      }
    });

    test('偏移量级 100~800 米（量级不对说明常量写错了）', () {
      for (final p in pts) {
        final g = CoordTransform.wgs84ToGcj02(p[0], p[1]);
        final d = CoordTransform.distanceMeters(p[0], p[1], g[0], g[1]);
        expect(d, greaterThan(100), reason: '(${p[0]}, ${p[1]}) 只偏了 ${d}m');
        expect(d, lessThan(800), reason: '(${p[0]}, ${p[1]}) 偏了 ${d}m');
      }
    });

    test('境外不转（东京原样返回）', () {
      final g = CoordTransform.wgs84ToGcj02(35.6812, 139.7671);
      expect(g[0], 35.6812);
      expect(g[1], 139.7671);
    });
  });

  group('③ 地图页必须走底图投影，不许手写纠偏', () {
    test('spot_map_screen 里不出现 wgs84ToGcj02', () {
      final src = File('lib/screens/spot_map_screen.dart').readAsStringSync();
      expect(src.contains('CoordTransform.wgs84ToGcj02'), isFalse,
          reason: '视野跳转必须用 _tile.project()：高德底图才转 GCJ-02，'
              '星图地球/天地图是 WGS-84 直接画。写死转换会让视角偏 400 米');
      // 确认仍然通过底图投影
      expect(src.contains('_tile.project('), isTrue);
    });

    test('TileSource.project 只在高德底图纠偏', () {
      final src = File('lib/services/map_tile_source.dart').readAsStringSync();
      expect(src.contains('bool get isGcj02 => kind == TileSourceKind.gaode'),
          isTrue);
      expect(src.contains('if (!isGcj02) return wgs84;'), isTrue);
    });
  });
}
