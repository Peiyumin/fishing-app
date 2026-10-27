import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/models/fish.dart';
import 'package:fishing_app/widgets/app_refresh.dart';
import 'package:fishing_app/widgets/fish_dex_card.dart';

/// 统一下拉刷新 + 钓鱼档案卡回归
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('下拉刷新提示条', () {
    final hint = find.text('渔报 为您玩命加载…');

    Future<void> pumpRefresh(
      WidgetTester tester,
      Future<void> Function() onRefresh,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppRefresh(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 20; i++)
                  SizedBox(height: 60, child: Text('item$i')),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('平时提示条不在树上，不挡内容', (tester) async {
      await pumpRefresh(tester, () async {});
      expect(hint, findsNothing, reason: '未刷新时提示条应完全收起');
    });

    testWidgets('下拉触发后滑出提示条，文案含「最后更新」', (tester) async {
      var called = 0;
      await pumpRefresh(tester, () async {
        called++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      // 从列表顶部往下拖，触发 RefreshIndicator
      await tester.fling(find.byType(ListView), const Offset(0, 320), 1200);
      // 逐帧推进（真实手势回弹需要好多帧，一次大跳会跳过动画）
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(called, greaterThan(0), reason: '下拉必须真的触发刷新回调');
      expect(hint, findsOneWidget, reason: '刷新中提示条要滑出来');
      expect(tester.getTopLeft(hint).dy, greaterThanOrEqualTo(0),
          reason: '提示条要完整落在屏幕内，不能停在屏幕外');
      expect(find.textContaining('最后更新：'), findsOneWidget);

      // 收尾：让 700ms 停留 + 收回动画跑完，避免 pending timer
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();
    });

    testWidgets('刷新结束后提示条收回，并记下本次更新时间', (tester) async {
      await pumpRefresh(tester, () async {});

      await tester.fling(find.byType(ListView), const Offset(0, 320), 1200);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();

      expect(hint, findsNothing, reason: '刷新完成后提示条应收回');

      final sp = await SharedPreferences.getInstance();
      final saved = sp.getString('refresh_last_at_global');
      expect(saved, isNotNull, reason: '「最后更新」要落盘，下次进页面才显示得出来');
      expect(DateTime.tryParse(saved!), isNotNull);
    });

    testWidgets('刷新失败不篡改「最后更新」（避免显示假的新时间）', (tester) async {
      await pumpRefresh(tester, () async {
        throw Exception('boom');
      });

      await tester.fling(find.byType(ListView), const Offset(0, 320), 1200);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();

      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('refresh_last_at_global'), isNull);
      expect(tester.takeException(), isNull, reason: '刷新异常不应冒到界面');
    });

    testWidgets('下拉时不会有灰圆圈露出来（指示器被推到视口外）', (tester) async {
      await pumpRefresh(tester, () async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });

      // 停在「拉到一半」——如果指示器还在屏幕上，这一刻正是它最显眼的时候
      final g = await tester
          .startGesture(tester.getCenter(find.byType(ListView)));
      await g.moveBy(const Offset(0, 100));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      final ind = find.byType(RefreshProgressIndicator);
      if (ind.evaluate().isNotEmpty) {
        final top = tester.getTopLeft(ind.first).dy;
        expect(top, lessThan(-500),
            reason: 'RefreshProgressIndicator 必须被推到视口外，'
                '否则它的 Material 阴影会显示成用户截图里那个灰圆圈');
      }

      await g.up();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();
    });
  });

  group('钓鱼档案卡', () {
    FishSpecies sp(String id, String name,
            {bool unlocked = false, String rarity = 'common'}) =>
        FishSpecies(
          id: id,
          name: name,
          unlocked: unlocked,
          rarity: rarity,
          count: unlocked ? 1 : 0,
        );

    Future<void> pumpCard(WidgetTester tester, FishGuide g,
        {int catches = 0, int trips = 0}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FishDexCard(
              guide: g,
              totalCatches: catches,
              monthTrips: trips,
              onOpenDex: () {},
              onSnap: () {},
              onOpenTank: () {},
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    const level = FishLevel(
        level: 1, name: '新手', nextName: '入门', nextNeed: 3);

    testWidgets('一条鱼都没点亮时：5 个「未点亮」+ 引导拍第一条', (tester) async {
      final g = FishGuide(
        level: level,
        unlockedCount: 0,
        totalCount: 100,
        fresh: [for (var i = 0; i < 8; i++) sp('f$i', '鱼$i')],
      );
      await pumpCard(tester, g);

      expect(find.text('钓鱼档案'), findsOneWidget);
      expect(find.text('未点亮'), findsNWidgets(5),
          reason: '网格前 5 格都应是未点亮位');
      expect(find.text('+100'), findsOneWidget, reason: '第 6 格显示剩余数量');
      expect(find.textContaining('点亮第 1 种'), findsOneWidget);
    });

    testWidgets('点亮 2 条时：显示鱼名、进度、距下一级还差几种', (tester) async {
      final g = FishGuide(
        level: level,
        unlockedCount: 2,
        totalCount: 100,
        fresh: [
          sp('f1', '鲫鱼', unlocked: true),
          sp('f2', '鲤鱼', unlocked: true),
          sp('f3', '草鱼'),
        ],
      );
      await pumpCard(tester, g, catches: 12, trips: 3);

      expect(find.text('鲫鱼'), findsWidgets);
      expect(find.text('鲤鱼'), findsWidgets);
      expect(find.text('未点亮'), findsNWidgets(3),
          reason: '共 5 格，点亮 2 格后剩 3 格未点亮');
      // 进度：再点亮 1 种 → Lv.2（nextNeed 3 - 已点亮 2）
      expect(find.textContaining('再点亮 1 种'), findsOneWidget);
      expect(find.textContaining('点亮第 3 种'), findsOneWidget);
      // 三个统计
      expect(find.text('累计渔获'), findsOneWidget);
      expect(find.text('本月出钓'), findsOneWidget);
      expect(find.text('图鉴收藏'), findsOneWidget);
      // 统计数字是 Text.rich（数字 + 单位两段样式），要用 findRichText 才找得到
      expect(find.textContaining('12', findRichText: true), findsWidgets,
          reason: '累计渔获 12 尾');
    });


    testWidgets('带鱼这类特别细长的真实鱼图不会把格子顶破（320dp 也放得下）', (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final g = FishGuide(
        level: level,
        unlockedCount: 2,
        totalCount: 100,
        fresh: [
          sp('f1', '带鱼', unlocked: true),
          sp('f2', '鳊鱼', unlocked: true),
        ],
      );
      await pumpCard(tester, g);
      expect(tester.takeException(), isNull,
          reason: '真实鱼图按宽高比定宽，不该出现 RenderFlex overflow');
      expect(find.text('带鱼'), findsOneWidget);
    });
    testWidgets('LV 徽章与图鉴入口都在', (tester) async {
      final g = FishGuide(level: level, totalCount: 10, fresh: []);
      await pumpCard(tester, g);
      expect(find.text('LV.1'), findsOneWidget);
      expect(find.text('FISH DEX'), findsOneWidget);
      expect(find.text('图鉴'), findsWidgets);
      expect(find.text('池塘'), findsOneWidget);
    });
  });
}
