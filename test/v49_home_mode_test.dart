// v2.1.86 首页钓法分类 + 天气分叉
//
// 用户需求（原话）：
//   「标题下面要加上台钓 路亚 钓场 海钓这几个分类，点击分类后显示的天气
//     要有区分，海钓显示的潮汐，台钓 钓场 路亚 显示 水氧」
//
// 拆成可验证的三件事：
//   ① 分类本身：4 个、顺序对、点了会回调、默认台钓、认不出的存值回落台钓
//   ② 第三格分叉：海钓 → 潮汐；台钓/路亚/钓场 → 水氧（没数据一律「--」）
//   ③ 指数真的跟着钓法变（只换标签不换数是假切换）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/fishing_species.dart';
import 'package:fishing_app/models/home_mode.dart';
import 'package:fishing_app/models/weather_forecast.dart';
import 'package:fishing_app/services/tide_service.dart';
import 'package:fishing_app/services/weather_service.dart';
import 'package:fishing_app/widgets/home_weather_hero.dart';
import 'package:fishing_app/widgets/mode_tabs.dart';

/// 造一组「现在这一小时」前后的逐时数据（台风前：气压下跌 + 有风 + 小雨）
WeatherBundle demoBundle() {
  final now = DateTime.now();
  final base = DateTime(now.year, now.month, now.day, now.hour);
  final hours = <HourPoint>[];
  for (var i = -12; i <= 36; i++) {
    final t = base.add(Duration(hours: i));
    hours.add(HourPoint(
      time: t,
      temp: 22 - (i % 7) * 0.6,
      humidity: 78,
      pressure: 1006 + (i % 5).toDouble(),
      precipProb: 40,
      precip: 0.3,
      windSpeed: 16,
      windDir: 90,
      weatherCode: 61,
    ));
  }
  return WeatherBundle(
    lat: 30.27,
    lng: 120.15,
    curTemp: 22,
    curHumidity: 78,
    curPressure: 1008,
    curWindSpeed: 16,
    curWindDir: 90,
    curPrecip: 0.3,
    curCode: 61,
    curPrecipProb: 40,
    curHour: base,
    hours: hours,
    days: const [],
  );
}

Widget wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  group('① 分类：四个、顺序、默认值', () {
    test('四个分类的名字与顺序就是用户要的', () {
      expect(HomeMode.values.map((m) => m.label).toList(),
          ['台钓', '路亚', '钓场', '海钓']);
    });

    test('钓场沿用台钓的权重（收费塘就是台钓场景），但标签必须是「钓场」', () {
      expect(HomeMode.chang.label, '钓场');
      expect(HomeMode.chang.scoreMode, '台钓');
      expect(HomeMode.chang.wantsTide, isFalse);
      // 其余三种
      expect(HomeMode.taiDiao.scoreMode, '台钓');
      expect(HomeMode.luYa.scoreMode, '路亚');
      expect(HomeMode.haiDiao.scoreMode, '海钓');
    });

    test('只有海钓要潮汐，另外三个要水氧', () {
      expect(HomeMode.haiDiao.wantsTide, isTrue);
      for (final m in [HomeMode.taiDiao, HomeMode.luYa, HomeMode.chang]) {
        expect(m.wantsTide, isFalse, reason: '${m.label} 应该显示水氧而不是潮汐');
      }
    });

    test('本地偏好能存能还；脏数据回落台钓而不是崩', () {
      for (final m in HomeMode.values) {
        expect(HomeMode.fromKey(m.key), m);
      }
      expect(HomeMode.fromKey(null), HomeMode.taiDiao);
      expect(HomeMode.fromKey(''), HomeMode.taiDiao);
      expect(HomeMode.fromKey('黑坑'), HomeMode.taiDiao);
    });
  });

  group('② 第三格：海钓看潮汐，其余看水氧', () {
    const weather = FishingWeather(
      temperature: 18,
      humidity: 70,
      pressure: 1010,
      windSpeed: 12,
      windDir: 90,
      weatherCode: 3,
      description: '阴',
      fishIndex: '良好',
      fishAdvice: '可以出钓',
      score: 72,
      oxygen: 7.4,
    );

    test('台钓/路亚/钓场 → 水氧 mg/L，数值是模型给的 7.4', () {
      for (final m in [HomeMode.taiDiao, HomeMode.luYa, HomeMode.chang]) {
        final c = homeThirdMetric(mode: m, weather: weather);
        expect(c.value, '7.4', reason: '${m.label} 的第三格是水氧');
        expect(c.label, '水氧 mg/L');
      }
    });

    test('海钓 → 潮汐，潮高与潮态分开摆', () {
      const tide = TideInfo(heightM: 1.23, state: '涨潮', rising: true, amp: 1.6);
      final c = homeThirdMetric(mode: HomeMode.haiDiao, weather: weather, tide: tide);
      expect(c.value, '+1.2m');
      expect(c.label, '潮汐 涨潮');
    });

    test('海钓没坐标 → 「--」，不是 0.0m', () {
      final c = homeThirdMetric(mode: HomeMode.haiDiao, weather: weather);
      expect(c.value, '--');
      expect(c.label, '潮汐');
    });

    test('天气还没回来 / 老缓存没有水氧 → 「--」，绝不写 0', () {
      expect(homeThirdMetric(mode: HomeMode.taiDiao, weather: null).value, '--');
      const noOx = FishingWeather(
        temperature: 18,
        humidity: 70,
        pressure: 1010,
        windSpeed: 12,
        weatherCode: 3,
        description: '阴',
        fishIndex: '一般',
        fishAdvice: '',
      );
      expect(homeThirdMetric(mode: HomeMode.luYa, weather: noOx).value, '--');
      expect(homeThirdMetric(mode: HomeMode.luYa, weather: noOx).label, '水氧 mg/L');
    });

    test('水氧的人话解读分档（读屏与提示文案共用）', () {
      expect(oxygenFeel(8.2), contains('充足'));
      expect(oxygenFeel(6.0), contains('正常'));
      expect(oxygenFeel(4.5), contains('偏低'));
      expect(oxygenFeel(3.0), contains('不足'));
      expect(oxygenFeel(null), contains('暂无'));
    });
  });

  group('③ 指数跟着钓法变（只换标签不换数是假切换）', () {
    test('同一小时，四种钓法不是同一个分数', () {
      final b = demoBundle();
      final scores = <String, int>{};
      for (final m in HomeMode.values) {
        scores[m.label] =
            FishingWeather.fromIndex(b, 12, mode: m.fishingMode).score;
      }
      // 不必每种都不同（钓场=台钓本来就该一样），但海钓必须和台钓分开
      expect(scores['钓场'], scores['台钓'],
          reason: '钓场用的是台钓权重，分数应当一致');
      expect(scores['海钓'], isNot(scores['台钓']),
          reason: '海钓把潮汐当主因子，台钓不算潮汐 —— 分数不该一样');
    });

    test('不传 mode 等于台钓（老调用方行为不变）', () {
      final b = demoBundle();
      expect(FishingWeather.fromIndex(b, 12).score,
          FishingWeather.fromIndex(b, 12, mode: const FishingMode('台钓')).score);
    });

    test('水氧随逐时数据一起算出来，落在 2~14mg/L 的物理区间', () {
      final b = demoBundle();
      final w = FishingWeather.fromIndex(b, 12);
      expect(w.oxygen, isNotNull);
      expect(w.oxygen!, inInclusiveRange(2.0, 14.0));
    });

    test('水氧能跟着缓存写进 JSON 再读回来（否则首页永远「--」）', () {
      final b = demoBundle();
      final w = FishingWeather.fromIndex(b, 12);
      final back = FishingWeather.fromJson(w.toJson());
      expect(back.oxygen, closeTo(w.oxygen!, 1e-6));
    });
  });

  group('④ 界面：分类条与天气通栏', () {
    testWidgets('分类条画出四个字，默认台钓带选中条，点海钓会回调', (t) async {
      HomeMode? picked;
      await t.pumpWidget(wrap(ModeTabs(
        mode: HomeMode.taiDiao,
        onChanged: (m) => picked = m,
      )));
      for (final m in HomeMode.values) {
        expect(find.text(m.label), findsOneWidget);
      }
      await t.tap(find.text('海钓'));
      expect(picked, HomeMode.haiDiao);

      // 选中态除了颜色还多一条荧光绿短线：色弱用户也分得清
      await t.pumpWidget(wrap(ModeTabs(
        mode: HomeMode.haiDiao,
        onChanged: (_) {},
      )));
      await t.pump(const Duration(milliseconds: 200));
      final bars = t.widgetList<AnimatedContainer>(
          find.descendant(of: find.byType(ModeTabs), matching: find.byType(AnimatedContainer)));
      final widths = bars
          .map((c) => (c.constraints?.maxWidth) ?? 0)
          .where((w) => w > 0)
          .toList();
      // 只有当前选中的那条有宽度（20）
      expect(widths.length, 1);
      expect(widths.first, 20);
    });

    testWidgets('天气通栏：海钓出「潮汐」，台钓出水氧，气压不再占格', (t) async {
      const w = FishingWeather(
        temperature: 18,
        humidity: 70,
        pressure: 1010,
        windSpeed: 12,
        weatherCode: 3,
        description: '阴',
        fishIndex: '良好',
        fishAdvice: '可以出钓',
        score: 72,
        oxygen: 7.4,
      );
      const tide = TideInfo(heightM: -0.8, state: '退潮', rising: false, amp: 1.2);

      await t.pumpWidget(wrap(HomeWeatherHero(
        weather: w,
        onTap: () {},
        mode: HomeMode.haiDiao,
        tide: tide,
        waterTemp: 16,
      )));
      expect(find.textContaining('潮汐'), findsOneWidget);
      expect(find.textContaining('水氧'), findsNothing);
      expect(find.text('-0.8m'), findsOneWidget);

      await t.pumpWidget(wrap(HomeWeatherHero(
        weather: w,
        onTap: () {},
        mode: HomeMode.luYa,
        waterTemp: 16,
      )));
      expect(find.textContaining('水氧'), findsOneWidget);
      expect(find.textContaining('潮汐'), findsNothing);
      expect(find.text('7.4'), findsOneWidget);
      // 四格：气压让位给第三格（气压在上面那句建议里）
      expect(find.textContaining('气压 hPa'), findsNothing);
    });
  });
}
