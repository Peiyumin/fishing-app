// v2.1.91 两条用户反馈的回归护栏
//
// 原话：
//   ①「鱼获详情页的天气卡片顶部边距留的太大的要和整体布局边距一样」
//   ②「钓点页面显示的钓场列表要以当前定位显示，以定位点显示距离由近到远的显示」
//
// ① 的真因：`_gearCard` 的 margin 是 `(16, 0, 16, 12)`，底部 12 跟下面
//    `_waterCard`（水温/水氧/天气三连，就是用户说的「天气卡片」）自己的
//    顶部 10 叠成 22；而页面其它卡片之间只有 10。左右 16 也和别处的 12
//    不一致，卡片会窄一截。改成一个和 `_card()` 相同的 `(12, 10, 12, 0)`。
//
// ② 的真因：排序本身是对的（`sortSpotsByDistance`），但坐标只有一个来源
//    —— 打开页面那一刻的实时定位。GPS 没回来 / 用户拒了权限的那几秒，
//    列表是后端 `created_at DESC` 的顺序、距离也不显示，看起来就是
//    「没按远近排」。加了 `LastPos`（复用首页那个 `home_last_pos`），
//    首屏先按上次的坐标排，实时定位回来再重排。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/models/fishing_spot.dart';
import 'package:fishing_app/services/last_pos.dart';
import 'package:fishing_app/utils/spot_sort.dart';

FishingSpot spot(String id, String name, double lat, double lng) => FishingSpot(
      id: id,
      name: name,
      type: '黑坑',
      kind: 'venue',
      lat: lat,
      lng: lng,
      rating: 0,
      description: '简介$name',
    );

void main() {
  group('① 详情页「天气卡片」上方间距和其它卡一致', () {
    late String src;

    setUpAll(() {
      src = File('lib/screens/post_detail_screen.dart').readAsStringSync();
    });

    /// 取某个方法的源码片段（从声明处到下一个分隔注释）
    String body(String sig) {
      final i = src.indexOf(sig);
      expect(i, greaterThan(0), reason: '找不到 $sig，结构变了就得重看这段护栏');
      final rest = src.substring(i);
      final end = rest.indexOf('// ══════════════════════', 10);
      return end > 0 ? rest.substring(0, end) : rest;
    }

    test('`_gearCard` 的 margin 与 `_card` 完全相同', () {
      final card = body('Widget _card(');
      final gear = body('Widget _gearCard(');

      expect(card.contains('EdgeInsets.fromLTRB(12, 10, 12, 0)'), isTrue,
          reason: '页面所有卡的统一边距就是这一串，`_card` 是基准');
      expect(gear.contains('EdgeInsets.fromLTRB(12, 10, 12, 0)'), isTrue,
          reason: '饵料卡要和其它卡同边距：左右 12（原来 16 会窄一截）、'
              '底部 0（不能和自己的 12 跟下一张卡的 10 叠成 22）');
      expect(gear.contains('fromLTRB(16, 0, 16, 12)'), isFalse,
          reason: '旧写法会让下面那张「天气卡片」上方多出一倍的空隙');
    });

    test('页面里没有第二处「底部留白 + 下卡顶部留白」叠加的写法', () {
      // _card 之后所有卡都靠「自己 top 10 + 上卡 bottom 0」形成 10 的间距，
      // 一旦有人写出 bottom>0 又紧跟着 top>0，间距就会翻倍
      final bad = RegExp(r'fromLTRB\(12,\s*10,\s*12,\s*([1-9]\d*)\)')
          .allMatches(src)
          .map((m) => m.group(0))
          .toList();
      expect(bad, isEmpty, reason: '这两处叠起来会让卡片间距翻倍：$bad');
    });
  });

  group('② 钓点首屏就用上次的定位排序', () {
    setUp(() {
      LastPos.resetForTest();
      SharedPreferences.setMockInitialValues({});
    });

    test('没存过位置时 load 返回 false，不会拿 (0,0) 去算距离', () async {
      expect(await LastPos.load(), isFalse);
      expect(LastPos.hasValue, isFalse);
    });

    test('首页写下的坐标，钓点页能直接读到（同一个 key）', () async {
      // 模拟首页定位成功后写盘
      SharedPreferences.setMockInitialValues({'home_last_pos': '28.19,112.93'});
      expect(await LastPos.load(), isTrue);
      expect(LastPos.lat, closeTo(28.19, 1e-9));
      expect(LastPos.lng, closeTo(112.93, 1e-9));
    });

    test('save 之后能读回，且写进的是和首页同一个 key', () async {
      await LastPos.save(30.27, 120.08);
      expect(LastPos.hasValue, isTrue);

      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('home_last_pos'), '30.27,120.08',
          reason: 'key 必须和首页 `_posKey` 一致，否则两边各存一份、互相读不到');

      // 清掉内存，模拟下次冷启动
      LastPos.resetForTest();
      expect(await LastPos.load(), isTrue);
      expect(LastPos.lat, closeTo(30.27, 1e-9));
    });

    test('脏值一律不认：(0,0) / 越界 / 非数字', () async {
      for (final raw in ['0,0', '91,120', '30,181', 'abc,def', '28.19', '']) {
        LastPos.resetForTest();
        SharedPreferences.setMockInitialValues({'home_last_pos': raw});
        expect(await LastPos.load(), isFalse, reason: '「$raw」不该被当成有效位置');
      }
    });

    test('source 护栏：首页与 LastPos 用的是同一个 key', () {
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      final lp = File('lib/services/last_pos.dart').readAsStringSync();
      expect(home.contains("_posKey = 'home_last_pos'"), isTrue,
          reason: '首页存位置的 key 改了，LastPos 就永远读不到');
      expect(lp.contains("key = 'home_last_pos'"), isTrue);
    });

    test('拿到缓存坐标后，列表按由近到远排', () async {
      SharedPreferences.setMockInitialValues({'home_last_pos': '28.19,112.93'});
      await LastPos.load();

      final list = [
        spot('a', '远处', 40.33, 117.12), // 承德附近，约 1500km
        spot('b', '近处', 28.21, 112.95), // 长沙附近，几百米
        spot('c', '中距', 30.27, 120.08), // 杭州方向，约 700km
      ];
      final sorted = sortSpotsByDistance(list, LastPos.lat, LastPos.lng);
      expect(sorted.map((s) => s.name).toList(), ['近处', '中距', '远处'],
          reason: '这就是用户要的「以定位点显示距离由近到远」');
    });

    test('source 护栏：钓点页先 restore 再实时定位，且定位成功后存盘', () {
      final src = File('lib/screens/spots_screen.dart').readAsStringSync();
      expect(src.contains('_restoreLastPos()'), isTrue,
          reason: '首屏不先读上次坐标，进页面那几秒就是乱序且没有距离');
      expect(src.contains('LastPos.save('), isTrue,
          reason: '实时定位成功后要写下来，下次首屏才能立刻排好');
      expect(src.contains('_locateHint()'), isTrue,
          reason: '定位失败要明说一句，别让用户以为排序坏了');
    });
  });
}
