import 'dart:convert';

import 'package:fishing_app/models/no_fishing_zone.dart';
import 'package:fishing_app/models/water_body.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// 钓点地图数据 + 禁钓区状态判定测试
/// 数据文件：assets/data/waters.json、assets/data/no_fishing_zones.json
/// （flutter test 会把 pubspec 里声明的 assets 打进测试 bundle，可直接 rootBundle 读取）
Future<Map<String, dynamic>> _loadDoc(String path) async {
  final s = await rootBundle.loadString(path);
  return jsonDecode(s) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('水域图层数据', () {
    test('JSON 结构完整', () async {
      final doc = await _loadDoc('assets/data/waters.json');
      expect(doc['rivers'], isA<List>());
      expect(doc['lakes'], isA<List>());
      expect((doc['rivers'] as List).length, greaterThanOrEqualTo(40));
      expect((doc['lakes'] as List).length, greaterThanOrEqualTo(40));
    });

    test('所有坐标落在中国范围且湖泊环闭合', () async {
      final doc = await _loadDoc('assets/data/waters.json');
      var count = 0;
      for (final r in doc['rivers'] as List) {
        for (final p in r['points'] as List) {
          final lat = (p[0] as num).toDouble();
          final lng = (p[1] as num).toDouble();
          expect(lat, inInclusiveRange(3.0, 54.5), reason: '${r['name']} 纬度 $lat');
          expect(lng, inInclusiveRange(73.0, 135.5), reason: '${r['name']} 经度 $lng');
          count++;
        }
      }
      for (final l in doc['lakes'] as List) {
        final ring = l['ring'] as List;
        expect(ring.first, equals(ring.last), reason: '${l['name']} 环未闭合');
        for (final p in ring) {
          final lat = (p[0] as num).toDouble();
          final lng = (p[1] as num).toDouble();
          expect(lat, inInclusiveRange(3.0, 54.5));
          expect(lng, inInclusiveRange(73.0, 135.5));
          count++;
        }
      }
      expect(count, greaterThan(600));
    });

    test('WaterBody.fromJson 解析河流与湖泊', () async {
      final doc = await _loadDoc('assets/data/waters.json');
      final cj = WaterBody.fromJson(
          (doc['rivers'] as List).first as Map<String, dynamic>,
          river: true);
      expect(cj.name, '长江');
      expect(cj.isRiver, true);
      expect(cj.geometry.length, greaterThan(20));
      expect(cj.strokeWidth, greaterThan(3)); // 一级河流更粗

      final qh = WaterBody.fromJson(
          ((doc['lakes'] as List).firstWhere((e) => e['id'] == 'qinghaihu'))
              as Map<String, dynamic>,
          river: false);
      expect(qh.name, '青海湖');
      expect(qh.isRiver, false);
      expect(qh.center, isA<LatLng>());
    });
  });

  group('禁钓区图层数据', () {
    test('JSON 结构完整', () async {
      final doc = await _loadDoc('assets/data/no_fishing_zones.json');
      final zones = doc['zones'] as List;
      expect(zones.length, greaterThanOrEqualTo(30));
      expect((doc['seasonRules'] as List).length, greaterThanOrEqualTo(15));
      expect((doc['tips'] as List).length, greaterThanOrEqualTo(3));
    });

    test('每个 zone 关键字段齐全且时间段非空', () async {
      final doc = await _loadDoc('assets/data/no_fishing_zones.json');
      for (final z in doc['zones'] as List) {
        final m = z as Map<String, dynamic>;
        expect(m['id'], isNotEmpty);
        expect(m['name'], isNotEmpty);
        expect(m['period'], isNotEmpty, reason: '${m['name']} 缺禁钓时间段');
        expect(m['law'], isNotEmpty, reason: '${m['name']} 缺政策依据');
        expect(m['source'], isNotEmpty, reason: '${m['name']} 缺来源');
        expect(m['fishing'], isNotEmpty, reason: '${m['name']} 缺垂钓规定');
        expect(m['typeLabel'], isNotEmpty);
      }
    });

    test('NoFishingZone.fromJson + rings 闭合', () async {
      final doc = await _loadDoc('assets/data/no_fishing_zones.json');
      for (final z in doc['zones'] as List) {
        final zone = NoFishingZone.fromJson(z as Map<String, dynamic>);
        if (!zone.onMap) continue;
        expect(zone.rings, isNotEmpty, reason: '${zone.name} 上图但无范围');
        for (final ring in zone.rings) {
          expect(ring.length, greaterThanOrEqualTo(4));
          expect(ring.first, equals(ring.last), reason: '${zone.name} 环未闭合');
        }
      }
    });
  });

  group('禁钓状态判定', () {
    Future<NoFishingZone> zoneFrom(String id) async {
      final doc = await _loadDoc('assets/data/no_fishing_zones.json');
      final raw = (doc['zones'] as List).firstWhere((e) => e['id'] == id);
      return NoFishingZone.fromJson(raw as Map<String, dynamic>);
    }

    test('十年禁捕：当前在期限内', () async {
      final z = await zoneFrom('cj-mainstem');
      final st = z.statusNow();
      expect(st.active, true);
      expect(st.label, contains('禁捕'));
    });

    test('巢湖：十年禁钓在期限内', () async {
      final z = await zoneFrom('lake-chaohu');
      expect(z.statusNow().active, true);
      expect(z.isPermanentFishingBan, true);
    });

    test('太湖禁渔期（1.1-9.16）：10 月不在禁渔期，6 月在', () async {
      final z = await zoneFrom('lake-taihu');
      expect(z.statusNow(DateTime(2026, 10, 23)).active, false);
      expect(z.statusNow(DateTime(2026, 6, 15)).active, true);
      expect(z.statusNow(DateTime(2026, 1, 1, 12, 1)).active, true);
    });

    test('抚仙湖禁渔期跨年（12.31-7.1）：1 月和 6 月在内，8 月和 12 月在外', () async {
      final z = await zoneFrom('ws-fuxian');
      expect(z.statusNow(DateTime(2026, 1, 15)).active, true);
      expect(z.statusNow(DateTime(2026, 6, 30)).active, true);
      expect(z.statusNow(DateTime(2026, 8, 1)).active, false);
      expect(z.statusNow(DateTime(2026, 12, 30)).active, false);
    });

    test('密云水库（4.1-9.24）：5 月在内，11 月在外', () async {
      final z = await zoneFrom('ws-miyun');
      expect(z.statusNow(DateTime(2026, 5, 1)).active, true);
      expect(z.statusNow(DateTime(2026, 11, 1)).active, false);
      expect(z.kind, ZoneKind.waterSource);
      expect(z.isPermanentFishingBan, true);
    });

    test('SeasonRule.activeNow 与周期窗口一致', () async {
      final doc = await _loadDoc('assets/data/no_fishing_zones.json');
      final rules = (doc['seasonRules'] as List)
          .map((e) => SeasonRule.fromJson(e as Map<String, dynamic>))
          .toList();
      final huaihe = rules.firstWhere((r) => r.id == 'sr-huaihe');
      expect(huaihe.activeNow, false); // 10 月不在 3-6 月
      expect(huaihe.period, contains('3月1日'));

      final haihe = rules.firstWhere((r) => r.id == 'sr-haihe');
      expect(haihe.activeNow, false); // 10 月不在 5.16-7.31
      expect(haihe.period, contains('5月16日'));
    });
  });
}
