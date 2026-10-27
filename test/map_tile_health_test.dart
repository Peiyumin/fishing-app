import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/services/map_config_service.dart';
import 'package:fishing_app/services/map_tile_source.dart';
import 'package:fishing_app/services/tile_health.dart';

/// 底图线路自检（用户报障：「WiFi 下野钓钓点地图不加载，只显示高德底图」）
///
/// 这里锁两件事：
///   1. 探测用的瓦片地址拼得对（占位符全替换、不带 `{s}`、带上密钥）
///   2. 无论探测结果如何，最后给出的底图**一定是可用的**（不能白屏）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('探测地址', () {
    const geo = TileSource(
        kind: TileSourceKind.geovisearth, geoToken: 'TOKEN123');
    const tdt = TileSource(kind: TileSourceKind.tianditu, tk: 'TK456');
    const gd = TileSource(kind: TileSourceKind.gaode);

    test('星图：子域/z/x/y/token 全部替换，不留占位符', () {
      final u = TileHealth.buildProbeUrl(geo);
      expect(u, contains('tiles1.geovisearth.com'));
      expect(u, contains('/${TileHealth.probeZ}/'));
      expect(u, contains('/${TileHealth.probeX}/${TileHealth.probeY}'));
      expect(u, contains('token=TOKEN123'));
      expect(u.contains('{'), isFalse);
    });

    test('天地图：tk 进 query', () {
      final u = TileHealth.buildProbeUrl(tdt);
      expect(u, contains('tianditu.gov.cn'));
      expect(u, contains('tk=TK456'));
      expect(u.contains('{'), isFalse);
    });

    test('高德：免 key，style=8 卫星图', () {
      final u = TileHealth.buildProbeUrl(gd);
      expect(u, contains('style=8'));
      expect(u.contains('{'), isFalse);
    });
  });

  group('候选顺序', () {
    test('没有任何密钥时只剩高德（保证地图永远能开）', () {
      final c = MapConfigService.candidates;
      expect(c, isNotEmpty);
      expect(c.map((s) => s.kind), contains(TileSourceKind.gaode));
    });

    test('每一条候选都是 usable 的', () {
      for (final s in MapConfigService.candidates) {
        expect(s.usable, isTrue, reason: '${s.kind} 没有密钥却进了候选表');
      }
    });
  });

  group('自检后仍然有可用底图', () {
    test('探测全部失败（测试环境无网络）也不会把底图弄丢', () async {
      await MapConfigService.checkReachable(force: true);
      final src = MapConfigService.source;
      expect(src.usable, isTrue);
      expect(src.attribution, isNotEmpty);
      // 失败必须留下可读的结论，界面才有话可说
      expect(MapConfigService.healthChecked, isTrue);
    });

    test('resetHealth 之后可以重新判断（换网络场景）', () {
      MapConfigService.resetHealth();
      expect(MapConfigService.healthChecked, isFalse);
      expect(MapConfigService.healthNote, isEmpty);
      expect(MapConfigService.lastProbe, isEmpty);
    });
  });
}
