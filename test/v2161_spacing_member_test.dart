// v2.1.61：间距收紧 + 两个新会员闸门的回归
//
// 用户这一轮要的是两件事，分两组钉：
//
// ① 间距（纯数值，最容易在未来某次「顺手美化」里被改回去）
//    · 页边距 10、卡间距 8、瀑布流缝 8
//    · 分区标题默认内边距跟着页边距走
//    · 「我的」页封面 248 → 200（用户嫌半屏都是图）
//
// ② 会员闸门
//    · 发现页导航栏多了「钓友」：非会员看解锁页，会员看附近钓友列表
//    · 天气只放行 2 天，第 3 天起挂小锁，点了弹「解锁 7 天预报」；会员不挂锁
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/screens/discover_screen.dart';
import 'package:fishing_app/screens/nearby_anglers_screen.dart';
import 'package:fishing_app/screens/weather_screen.dart';
import 'package:fishing_app/services/session_provider.dart';
import 'package:fishing_app/services/weather_service.dart';
import 'package:fishing_app/models/weather_forecast.dart';
import 'package:fishing_app/widgets/section_header.dart';

/// 7 天 × 24 小时的假天气包（只求结构完整，数值不重要）
WeatherBundle _sevenDayBundle() {
  final now = DateTime.now();
  final base = DateTime(now.year, now.month, now.day);
  final days = <DaySummary>[];
  final hours = <HourPoint>[];
  for (var d = 0; d < 7; d++) {
    final date = base.add(Duration(days: d));
    days.add(DaySummary(
      date: date,
      weatherCode: 0,
      tempMax: 30,
      tempMin: 18,
      precipSum: 0,
      precipProbMax: 10,
      windSpeedMax: 12,
      windDirDom: 90,
    ));
    for (var h = 0; h < 24; h++) {
      hours.add(HourPoint(
        time: date.add(Duration(hours: h)),
        temp: 22 + (h % 6),
        humidity: 60,
        pressure: 1012,
        precipProb: 10,
        precip: 0,
        windSpeed: 8,
        windDir: 90,
        weatherCode: 0,
      ));
    }
  }
  return WeatherBundle(
    lat: 30.24,
    lng: 120.12,
    curTemp: 24,
    curHumidity: 60,
    curPressure: 1012,
    curWindSpeed: 8,
    curWindDir: 90,
    curPrecip: 0,
    curCode: 0,
    curPrecipProb: 10,
    curHour: DateTime(now.year, now.month, now.day, now.hour),
    hours: hours,
    days: days,
  );
}

Future<void> _pumpWeather(WidgetTester tester, {required bool member}) async {
  // 只塞「上次坐标」：页面拿到坐标就立刻拉预报（testForecastOverride 直接给包），
  // 不必等 GPS —— 测试环境里定位通道不会回，光等定位会一直转圈。
  SharedPreferences.setMockInitialValues({
    'wx_forecast_v1':
        jsonEncode({'lat': 30.24, 'lng': 120.12, 'ts': 0}),
  });
  final sp = SessionProvider();
  await sp.restore();
  if (member) {
    await sp.markMember(level: 1, expire: '2099-12-31');
  }

  WeatherService.testForecastOverride = (lat, lng) async => _sevenDayBundle();
  addTearDown(() => WeatherService.testForecastOverride = null);

  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: sp,
    child: MaterialApp(theme: AppTheme.light, home: const WeatherScreen()),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  group('间距 token', () {
    test('页边距 10 / 卡间距 8 / 瀑布流缝 8', () {
      expect(AppTheme.pagePad, 10);
      expect(AppTheme.cardGap, 8);
      expect(AppTheme.gridGap, 8);
    });

    testWidgets('分区标题默认内边距跟页边距一致（左右）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: SectionHeader(title: '钓友动态', subtitle: '实时更新'),
          ),
        ),
      ));
      final title = tester.getRect(find.text('钓友动态'));
      expect(title.left, closeTo(AppTheme.pagePad + 4 + 8, 1),
          reason: '第一个字要在 pagePad + 竖条 4 + 缝隙 8 之后');
    });
  });

  group('发现页「钓友」Tab', () {
    testWidgets('导航栏有 5 个 tab，含「钓友」', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MaterialApp(home: DiscoverScreen()));
      await tester.pump(const Duration(milliseconds: 200));
      for (final t in ['推荐', '最新', '同城', '关注', '钓友']) {
        expect(find.text(t), findsOneWidget, reason: '缺少 tab：$t');
      }
      await tester.pump(const Duration(seconds: 2)); // 走完加载失败的 toast 计时器
    });

    testWidgets('非会员点「钓友」看到解锁页，不是钓友列表', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MaterialApp(home: DiscoverScreen()));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('钓友'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('会员专享'), findsOneWidget);
      expect(find.text('开通会员查看'), findsOneWidget);
      expect(find.byType(NearbyAnglersScreen), findsNothing,
          reason: '非会员不给看名单');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('会员点「钓友」直接进附近钓友列表', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
          const MaterialApp(home: DiscoverScreen(debugMember: true)));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('钓友'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(NearbyAnglersScreen), findsOneWidget);
      expect(find.text('会员专享'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('天气会员闸门', () {
    testWidgets('非会员：第 3 天起挂小锁', (tester) async {
      await _pumpWeather(tester, member: false);
      expect(tester.takeException(), isNull);
      // 日期胶囊是横向 ListView，屏幕外的不构建，所以只数可见的几颗锁
      expect(find.byIcon(Icons.lock_outline), findsAtLeastNWidgets(3),
          reason: '第 3 天起都应挂锁');
      // 「只放行 2 天」这条规则用源码护栏钉死（见下方 group）
    });

    testWidgets('会员：一把锁都没有', (tester) async {
      await _pumpWeather(tester, member: true);
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.lock_outline), findsNothing,
          reason: '会员应看到完整 7 天');
    });

    testWidgets('点锁弹「解锁 7 天预报」，不是直接切到那天', (tester) async {
      await _pumpWeather(tester, member: false);
      await tester.tap(find.byIcon(Icons.lock_outline).first);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.text('解锁 7 天预报'), findsOneWidget);
      expect(find.text('开通会员'), findsOneWidget);
    });
  });

  group('天气放行天数规则', () {
    test('非会员 2 天，会员全部', () {
      final src = File('lib/screens/weather_screen.dart').readAsStringSync();
      expect(
          src.contains('final unlockedDays = isMember ? b.days.length : 2;'),
          isTrue,
          reason: '免费只给 2 天，会员给满');
      expect(src.contains('i >= unlockedDays'), isTrue,
          reason: '超出放行天数的胶囊必须走「锁」分支');
    });
  });

  group('「我的」页封面高度', () {
    test('封面 200（用户嫌 248 时半屏都是图）', () {
      // 静态护栏：读源码，避免为了一个数字去搭整页 provider
      final src = File('lib/screens/profile_screen.dart').readAsStringSync();
      final m = RegExp(r'const coverH = ([\d.]+);').firstMatch(src);
      expect(m, isNotNull);
      expect(double.parse(m!.group(1)!), 200);
    });
  });
}
