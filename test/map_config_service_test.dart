import 'package:fishing_app/services/map_config_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 地图底图配置（v2.1.27）
///
/// 这里锁的是「建图前必须先拿到配置」这个时序约定，它直接决定三件用户可见的事：
/// 底图是不是星图、地图多久能出来、会不会中途降级换一套 UI。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('并发调用 load 返回同一个 Future（不会拿到尚未就绪的配置）', () {
    // 钓点页 initState 调一次、地图页 initState 又调一次，两者必须等同一份结果。
    // 旧实现里第二个调用会立刻拿到已完成的 Future，读到的底图源还是兜底高德。
    final a = MapConfigService.load();
    final b = MapConfigService.load();
    expect(identical(a, b), isTrue);
  });

  test('配置未就绪时也能给出可用底图（兜底不是空）', () {
    final src = MapConfigService.source;
    expect(src.attribution, isNotEmpty);
    expect(src.maxNativeZoom, greaterThan(0));
  });

  test('渲染内核取值只有 gl / dart 两种', () {
    expect(['gl', 'dart'], contains(MapConfigService.engine));
  });

  test('星图 token 有值即认定星图可用', () {
    expect(MapConfigService.hasGeovisearth,
        MapConfigService.geovisearthToken.isNotEmpty);
  });
}
