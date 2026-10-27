import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:fishing_app/services/map_tile_source.dart';

/// 底图瓦片源单测
///
/// 守三件事：
///   1. 三家底图 URL 模板 / 子域 / 参数注入正确（改错一处整张地图白屏）
///   2. 只有高德是 GCJ-02，星图地球和天地图都是 WGS-84 原样绘制
///   3. 不能开 tms（开了整图上下颠倒）
const _tk32 = '0123456789abcdef0123456789abcdef';

void main() {
  group('星图地球', () {
    final geo = const TileSource(
      kind: TileSourceKind.geovisearth,
      geoToken: 'abc123def456',
    );

    test('影像 / 注记 / 矢量模板都指向 geovisearth 且墨卡托', () {
      expect(geo.satelliteTemplate,
          'https://tiles{s}.geovisearth.com/base/v1/img/{z}/{x}/{y}'
          '?format=webp&tmsIds=w&token={token}');
      expect(geo.labelTemplate, contains('/base/v1/cia/'));
      expect(geo.vectorTemplate, contains('/base/v1/vec/'));
      expect(geo.labelTemplate, contains('tmsIds=w'));
    });

    test('子域只有 tiles1~tiles3，token 注入到 additionalOptions', () {
      expect(geo.subdomains, ['1', '2', '3']);
      expect(geo.additionalOptions, {'token': 'abc123def456'});
    });

    test('未加偏：WGS-84 原样绘制，不开 tms', () {
      expect(geo.isGcj02, isFalse);
      expect(geo.needsTms, isFalse);
      const p = LatLng(30.2741, 120.1551);
      final q = geo.project(p);
      expect(q.latitude, p.latitude);
      expect(q.longitude, p.longitude);
    });

    test('有 token 才可用', () {
      expect(geo.usable, isTrue);
      expect(const TileSource(kind: TileSourceKind.geovisearth).usable, isFalse);
    });
  });

  group('天地图', () {
    final tdt = const TileSource(kind: TileSourceKind.tianditu, tk: _tk32);

    test('模板走 DataServer 且带 tk 占位符', () {
      expect(tdt.satelliteTemplate, contains('tianditu.gov.cn/DataServer'));
      expect(tdt.satelliteTemplate, contains('T=img_w'));
      expect(tdt.satelliteTemplate, contains('tk={tk}'));
      expect(tdt.labelTemplate, contains('T=cia_w'));
      expect(tdt.additionalOptions, {'tk': _tk32});
      expect(tdt.subdomains, hasLength(8));
    });

    test('不开 tms、不做 GCJ 纠偏', () {
      expect(tdt.needsTms, isFalse);
      expect(tdt.isGcj02, isFalse);
    });
  });

  group('高德兜底', () {
    const gd = TileSource(kind: TileSourceKind.gaode);

    test('免 key 永远可用', () {
      expect(gd.usable, isTrue);
      expect(gd.subdomains, isNull);
      expect(gd.additionalOptions, isEmpty);
    });

    test('GCJ-02：坐标要纠偏', () {
      expect(gd.isGcj02, isTrue);
      const p = LatLng(30.2741, 120.1551);
      final q = gd.project(p);
      // 杭州一带 GCJ-02 偏移量约 0.003~0.006 度
      expect((q.latitude - p.latitude).abs(), greaterThan(0.001));
      expect((q.longitude - p.longitude).abs(), greaterThan(0.001));
    });
  });

  test('三家底图都有版权署名与短名', () {
    for (final k in TileSourceKind.values) {
      final s = TileSource(kind: k, tk: _tk32, geoToken: 'tok');
      expect(s.attribution.trim(), isNotEmpty, reason: '$k 缺版权署名');
      expect(s.shortName.trim(), isNotEmpty, reason: '$k 缺短名');
      expect(s.describe, contains('当前底图'));
      expect(s.maxZoom, greaterThanOrEqualTo(17));
    }
  });

  // 性能回归护栏（v2.1.13）
  //
  // 竞品「钓鱼佬」的底图配置里，卫星影像与路网注记是**互斥的两个选项**，
  // 永远不会同时请求两套瓦片。我们一度默认把两层都挂上，每屏瓦片请求
  // 从 ~20 张变成 ~40 张，拖动发涩主要来自这里。这条测试锁住默认值。
  group('图层默认值：底图只挂一层', () {
    test('默认不开路网注记（避免瓦片翻倍）', () {
      final s = MapLayerState();
      expect(s.satellite, isTrue, reason: '默认应是卫星影像');
      expect(s.roadLabels, isFalse, reason: '注记层默认必须关，否则每屏瓦片翻倍');
    });

    test('需要地名时可显式打开', () {
      final s = MapLayerState(roadLabels: true);
      expect(s.roadLabels, isTrue);
    });
  });
}
