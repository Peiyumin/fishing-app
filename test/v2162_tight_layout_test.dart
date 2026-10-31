// v2.1.62：首页 / 发现页「再收紧一档」+ 垂钓指数配色统一
//
// 用户这一轮提了两件事，分别钉住：
//
// ① 卡片更紧、更矮（数值型护栏，最容易被后来的「顺手美化」改回去）
//    · 页边距 10 → 8、卡间距 8 → 6、瀑布流缝 8 → 6
//    · 瀑布流卡片宽高比 .52 → .57（宽固定，比值变大 = 变矮）
//    · 两列之间那道缝必须 == gridGap，且不能宽于两侧的页边距
//
// ② 首页「实时天气」卡里的垂钓指数数字，颜色要和天气页完全一致
//    · 判档只有一个来源 AppTheme.biteScore（≥90 / ≥80 / ≥45 / 其余）
//    · WeatherCard.scoreColor 必须转调它，不许再自带一套阈值
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/post.dart';
import 'package:fishing_app/services/weather_service.dart';
import 'package:fishing_app/widgets/waterfall_post_card.dart';
import 'package:fishing_app/widgets/weather_card.dart';

Post _post(int i) => Post(
      id: 'p$i',
      userId: 'u$i',
      username: '老王爱钓鱼',
      title: '今日鱼获',
      body: '颗粒打窝，3.6 米溪流竿，下午三点开口。',
      imageUrls: const [],
      category: 'post',
      price: '',
      city: '许昌市',
      createdAt: DateTime.now(),
      likeCount: 12,
      commentCount: 3,
      viewCount: 120,
      userLevel: 3,
      fish: const [
        {'name': '鲤鱼', 'count': 2},
      ],
    );

FishingWeather _weather({int score = 86}) => FishingWeather(
      temperature: 20.1,
      humidity: 79,
      windSpeed: 18,
      windDir: 135,
      pressure: 1012,
      weatherCode: 2,
      description: '多云',
      fishIndex: '有口',
      fishAdvice: '多云天光照平稳，鱼不惊慌、愿意靠边，可以出钓',
      score: score,
      atLabel: '19:00',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('间距再收紧一档（v2.1.62）', () {
    test('页边距 8 / 缝 6 / 卡间距 6', () {
      expect(AppTheme.pagePad, 8);
      expect(AppTheme.gridGap, 6);
      expect(AppTheme.cardGap, 6);
    });

    testWidgets('两列之间那道缝 == gridGap，且窄于两侧页边距', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: WaterfallGrid(
            posts: [_post(0), _post(1)],
            shrinkWrap: true,
            onTap: (_) {},
          ),
        ),
      ));

      final r0 = tester.getRect(find.byType(WaterfallPostCard).at(0));
      final r1 = tester.getRect(find.byType(WaterfallPostCard).at(1));

      expect(r1.left - r0.right, closeTo(AppTheme.gridGap, .6),
          reason: '两列之间的缝要正好是一档 gridGap');
      expect(r0.left, closeTo(AppTheme.pagePad, .6),
          reason: '左侧留白要等于 pagePad');
      expect(390 - r1.right, closeTo(AppTheme.pagePad, .6),
          reason: '右侧留白要等于 pagePad');
      expect(r0.width - (r1.left - r0.right), greaterThan(0),
          reason: '卡片本身要比缝宽得多，否则是布局算错了');
    });

    testWidgets('卡片高度比 v2.1.61（比 .52）矮，但仍比 1:1 竖', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: WaterfallGrid(
            posts: [_post(0), _post(1)],
            shrinkWrap: true,
            onTap: (_) {},
          ),
        ),
      ));
      final r = tester.getRect(find.byType(WaterfallPostCard).first);

      // 390 宽：卡宽 184，.57 → 高 ≈ 323（上一版 .52 是 354）
      expect(r.width, closeTo(184, 1));
      expect(r.height, closeTo(r.width / .57, 2));
      expect(r.height, lessThan(340), reason: '比上一版矮一截');
      expect(r.height, greaterThan(300), reason: '别压成横条，图区还要能看清鱼');
    });
  });

  group('垂钓指数配色（首页 == 天气页）', () {
    test('四档阈值与色值：≥90 近黑 / ≥80 黄绿 / ≥45 暖金 / 其余灰', () {
      expect(AppTheme.biteScore(95), AppTheme.primary);
      expect(AppTheme.biteScore(90), AppTheme.primary);
      expect(AppTheme.biteScore(89), AppTheme.accentDark);
      expect(AppTheme.biteScore(80), AppTheme.accentDark);
      expect(AppTheme.biteScore(79), AppTheme.starDark);
      expect(AppTheme.biteScore(45), AppTheme.starDark);
      expect(AppTheme.biteScore(44), AppTheme.textTertiary);
    });

    test('首页天气卡的 scoreColor 转调同一函数（不再自带一套阈值）', () {
      for (final s in [95, 88, 85, 72, 60, 50, 44, 20]) {
        expect(WeatherCard.scoreColor(s), AppTheme.biteScore(s),
            reason: '$s 分在首页与天气页必须同色');
      }
    });

    testWidgets('86 分：首页卡里的数字用黄绿深阶，不是白字压黑胶囊', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: WeatherCard(weather: _weather(score: 86), placeLabel: '禹州'),
        ),
      ));

      final score = tester.widget<Text>(find.text('86'));
      expect(score.style?.color, AppTheme.accentDark,
          reason: '86 分在天气页是 accentDark，首页也必须一样');
      expect(find.text('垂钓指数'), findsOneWidget);
    });

    testWidgets('窄屏 320dp + 长地名：指数胶囊不把标题行挤爆', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: WeatherCard(
            weather: _weather(score: 95),
            placeLabel: '黔东南苗族侗族自治州',
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
