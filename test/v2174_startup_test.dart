// v2.1.74 启动体验护栏
//
// 用户的两条要求，各自钉一个测试：
//   ① 「打开 App 要秒加载，最长不超过 2 秒」→ 见 splash_screen_test.dart 的
//      「④ 启动预算」（Dart 层 1.2 秒内必须放行）；
//   ② 「实时天气直接写进 App，打开后只是联网获取，卡片不用加载直接显示」
//      → 本文件：启动预热把磁盘缓存读进内存后，首页**首帧**就画真实天气卡，
//        不出现「--℃ / 正在获取天气…」的占位态。
//
// 这两条都不是「感觉快了」，是可断言的：占位卡有专属文案，真实卡有温度值。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/screens/home_screen.dart';
import 'package:fishing_app/services/session_provider.dart';
import 'package:fishing_app/services/weather_service.dart';

/// 与 WeatherService._curCacheKey 同值（私有常量，测试只能对齐字符串）
const _kCurKey = 'wx_current_v1';

/// 一份「本机上次成功拿到的天气」缓存
///
/// ★ 键名必须是 `toJson()` 里那套短键（t/h/ws/wd/p/c/d/fi/fa/sc/al），
///   不是模型字段名 —— `fromJson` 只认短键，写成 `temperature` 会静默变 0℃。
Map<String, dynamic> _cache(int temp) => {
      'lat': 34.15,
      'lng': 113.48,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'w': {
        't': temp.toDouble(),
        'h': 62,
        'ws': 9.0,
        'wd': 135,
        'p': 1008.0,
        'c': 1,
        'd': '多云',
        'fi': '有口',
        'fa': '午后浅滩有口，注意防晒',
        'sc': 78,
        'al': '14:00',
      },
    };

Widget _wrap(Widget page) => ChangeNotifierProvider<SessionProvider>(
      create: (_) => SessionProvider(),
      child: MaterialApp(theme: AppTheme.light, home: page),
    );

void main() {
  setUp(WeatherService.clearMemory);

  test('启动预热：磁盘缓存能被同步读出来', () async {
    SharedPreferences.setMockInitialValues({
      _kCurKey: jsonEncode(_cache(23)),
    });
    WeatherService.clearMemory();
    expect(WeatherService.memoryCurrent, isNull);

    await WeatherService.warmUp();

    final w = WeatherService.memoryCurrent;
    expect(w, isNotNull, reason: '预热没把缓存读进内存，首页首帧就拿不到天气');
    expect(w!.temperature, 23);
    expect(w.score, 78);
  });

  test('缓存坏了也不能让启动崩：预热自己吞异常', () async {
    SharedPreferences.setMockInitialValues({_kCurKey: '这不是 JSON'});
    WeatherService.clearMemory();
    await WeatherService.warmUp(); // 不抛就算过
    expect(WeatherService.memoryCurrent, isNull);
  });

  testWidgets('首页首帧直接是真实天气卡，不出现占位态', (tester) async {
    SharedPreferences.setMockInitialValues({
      _kCurKey: jsonEncode(_cache(23)),
    });
    WeatherService.clearMemory();
    await WeatherService.warmUp();

    await tester.pumpWidget(_wrap(const HomeScreen()));
    // 只 pumpWidget 一次 = 真正的首帧，后面任何 setState 都还没来

    expect(find.text('正在获取天气…'), findsNothing,
        reason: '首帧还在画占位卡，说明内存预热没接上');
    expect(find.text('--℃'), findsNothing, reason: '首帧是骨架态的 --℃');
    expect(find.text('23℃'), findsOneWidget,
        reason: '首帧没有真实温度，用户会看到卡片先空一下再跳');
    expect(find.text('78'), findsOneWidget, reason: '垂钓指数没跟着秒显');

    // 收尾：首页里挂着定位 6 秒延时与 3 分钟轮询 timer，不推走会报 pending timer
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 20));
  });
}
