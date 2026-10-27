import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/screens/spot_map_screen.dart';

/// 地图控制器 / 图层开关的纯逻辑测试
///
/// 重点锁住「打开野钓钓点后地图不显示当前位置」这个回归：
/// 宿主页定位比地图创建更早完成时，坐标必须被缓存并在挂载时补发，
/// 不能被静默丢掉（丢掉的表现就是地图永远停在全国视角）。
void main() {
  group('SpotMapController 定位缓存', () {
    test('地图已挂载：直接执行', () {
      final c = SpotMapController();
      double? lat;
      double? lng;
      c.bind((a, b) {
        lat = a;
        lng = b;
      });
      c.moveToLocation(30.25, 120.15);
      expect(lat, 30.25);
      expect(lng, 120.15);
    });

    test('地图未挂载：坐标缓存，挂载后立刻补发', () {
      final c = SpotMapController();
      // 宿主页定位先完成（此时野钓 Tab 还没渲染，地图不存在）
      c.moveToLocation(30.25, 120.15);

      double? lat;
      double? lng;
      // 用户切到野钓 Tab，地图创建并挂载
      c.bind((a, b) {
        lat = a;
        lng = b;
      });
      expect(lat, 30.25, reason: '挂载时必须补发挂载前的定位，否则地图停在全国视角');
      expect(lng, 120.15);
    });

    test('补发只做一次：重复挂载不会反复跳动镜头', () {
      final c = SpotMapController();
      c.moveToLocation(30.25, 120.15);
      var calls = 0;
      void move(double a, double b) => calls++;
      c.bind(move);
      expect(calls, 1);
      c.unbind();
      c.bind(move);
      expect(calls, 1, reason: 'pending 已消费，第二次挂载不应再移动');
    });

    test('最新一次定位覆盖旧值', () {
      final c = SpotMapController();
      c.moveToLocation(30.0, 120.0);
      c.moveToLocation(31.0, 121.0);
      double? lat;
      c.bind((a, b) => lat = a);
      expect(lat, 31.0);
    });

    test('解绑后再定位会重新缓存（切 Tab 回来仍能补）', () {
      final c = SpotMapController();
      c.bind((a, b) {});
      c.unbind();
      c.moveToLocation(29.5, 119.5);
      double? lat;
      c.bind((a, b) => lat = a);
      expect(lat, 29.5);
    });
  });
}
