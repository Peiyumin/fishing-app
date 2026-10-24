import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/models/weather_forecast.dart';
import 'package:fishing_app/screens/weather_screen.dart';
import 'package:fishing_app/services/location_service.dart';
import 'package:fishing_app/services/weather_service.dart';

/// 天气页「当前时段」口径回归（v2.1.21）
///
/// 用户反馈：**首页实时天气是准的，天气页（钓鱼天气预报 · 7 天）里的
/// 「当前时间段」不准 —— 没有风力、没有湿度，垂钓指数也和首页对不上。**
///
/// 查下来是三个叠加的问题，这个测试把每一个都钉住：
///
///   ① **锚错小时**：上一版把当前卡锚成 `bundle.curHour`（= 拉包那一刻的整点）。
///      bundle 会被缓存，18:20 拉的包到 20:40 还锚在 18:00，而首页卡用的是
///      `DateTime.now()`。→ 断言卡片显示的是"现在这个整点"。
///   ② **半新半旧**：时间标签用 `h.hhmm`（现在），温度/天气/风/气压却用
///      `bundle.curTemp` 等（拉包时）。→ 断言温度取的是现在这小时的值。
///   ③ **字段缺**：当前卡没有湿度，风也只写"几级"没有具体风速。
///      → 断言「湿度 (%)」和「xxkm/h」都在。
///
/// 为了能分辨"取的是哪一小时"，这里把两个小时的数据做成**完全不同的量级**：
/// 现在这小时 31.7℃ / 湿度42 / 晴 / 18km/h，2 小时前 10.1℃ / 湿度88 / 小雨 / 3km/h。

const double _nowTemp = 31.7;
const int _nowHum = 42;
const int _nowCode = 0; // 晴
const double _nowWind = 18;

const double _staleTemp = 10.1;
const int _staleHum = 88;
const int _staleCode = 61; // 小雨
const double _staleWind = 3;

/// 造一个「2 小时前拉的」天气包：curHour / cur* 全是 2 小时前的快照
WeatherBundle _bundleFetchedTwoHoursAgo() {
  final now = DateTime.now();
  final base = DateTime(now.year, now.month, now.day, now.hour);
  final hours = <HourPoint>[];
  for (var i = -8; i <= 20; i++) {
    final isNow = i == 0;
    final isStale = i == -2; // 拉包时刻
    hours.add(HourPoint(
      time: base.add(Duration(hours: i)),
      temp: isNow ? _nowTemp : (isStale ? _staleTemp : 20.0),
      humidity: isNow ? _nowHum : (isStale ? _staleHum : 60),
      pressure: isNow ? 1005 : (isStale ? 1020 : 1012),
      precipProb: isNow ? 0 : (isStale ? 80 : 10),
      precip: isNow ? 0 : (isStale ? 3.2 : 0),
      windSpeed: isNow ? _nowWind : (isStale ? _staleWind : 9),
      windDir: isNow ? 90 : (isStale ? 270 : 180),
      weatherCode: isNow ? _nowCode : (isStale ? _staleCode : 2),
    ));
  }
  return WeatherBundle(
    lat: 30.24,
    lng: 120.12,
    // ★ 这几个字段故意填成 2 小时前的值 —— 修复前页面正是拿它们当"当前"显示的
    curTemp: _staleTemp,
    curHumidity: _staleHum,
    curPressure: 1020,
    curWindSpeed: _staleWind,
    curWindDir: 270,
    curPrecip: 3.2,
    curCode: _staleCode,
    curPrecipProb: 80,
    curHour: base.subtract(const Duration(hours: 2)),
    hours: hours,
    days: [
      DaySummary(
        date: base,
        weatherCode: _nowCode,
        tempMax: 32,
        tempMin: 15,
        precipSum: 0,
        precipProbMax: 20,
        windSpeedMax: 20,
        windDirDom: 90,
      ),
    ],
  );
}

void main() {
  // ★ 整条测试只造一份包：如果在断言时再造一份，跨整点时基线会漂
  late WeatherBundle bundle;

  setUp(() {
    // 不 mock 掉本地存储的话，SharedPreferences 的平台通道在 fake-async 下
    // 永远不回来，页面会一直停在 loading —— 那不是被测代码的问题。
    SharedPreferences.setMockInitialValues({});
    bundle = _bundleFetchedTwoHoursAgo();
    WeatherService.testForecastOverride = (lat, lng) async => bundle;
    LocationService.testDetermineOverride =
        ({LocationAccuracy accuracy = LocationAccuracy.high}) async => Position(
              longitude: 120.12,
              latitude: 30.24,
              timestamp: DateTime.now(),
              accuracy: 10,
              altitude: 100,
              altitudeAccuracy: 1,
              heading: 0,
              headingAccuracy: 1,
              speed: 0,
              speedAccuracy: 1,
            );
  });

  tearDown(() {
    WeatherService.testForecastOverride = null;
    LocationService.testDetermineOverride = null;
  });

  testWidgets('当前卡锚"现在这个整点"、字段补全、指数与首页同源', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: WeatherScreen()));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull, reason: '首屏渲染异常');

    // 页面应当显示「现在所在的那一小时」——不是拉包时刻，也不是还没到的下一小时
    final nowHour = bundle.hourCurrent(DateTime.now())!;
    final staleLabel = '${(_staleTemp).toStringAsFixed(0)}';
    expect(nowHour.temp, _nowTemp, reason: '测试数据自检：现在这小时应是 31.7℃');

    // ① 时间标签 = 现在这个整点 + 现在这小时的天气现象
    expect(find.text('${nowHour.hhmm} · 晴'), findsOneWidget,
        reason: '当前卡的时段必须是"现在这个整点"，不能锚在拉包时刻，'
            '也不能是还没到的下一小时');
    expect(find.textContaining('· 小雨'), findsNothing,
        reason: '不能拿缓存的旧时段（2 小时前的"小雨"）当当前时段显示');

    // ② 温度取的是现在这小时的值
    expect(find.text(_nowTemp.toStringAsFixed(1)), findsWidgets,
        reason: '当前卡温度应取"现在这小时"，而不是拉包时刻的 $_staleTemp℃');

    // ③ 风力 + 湿度两个字段必须在
    expect(find.text('湿度 (%)'), findsOneWidget, reason: '当前卡要显示湿度');
    expect(find.text('${_nowWind.toStringAsFixed(0)}km/h'), findsWidgets,
        reason: '风力要显示具体风速（km/h），不能只写"几级"');

    // ④ 指数口径标出来（与首页默认的鲫鱼·台钓对齐，换鱼种也能看出为什么变）
    expect(find.text('鲫鱼 · 台钓'), findsOneWidget,
        reason: '指数要标出口径，否则和首页对比会被当成"数据错了"');

    // ⑤ 指数与首页实时天气卡同源同值
    final home = FishingWeather.fromBundle(bundle);
    expect(find.text('${home.score}'), findsWidgets,
        reason: '天气页当前时刻的垂钓指数应与首页实时天气卡一致');

    // 顺带：湿度数值也得是"现在这小时"的
    expect(find.text('$_nowHum'), findsWidgets, reason: '湿度要取现在这小时的值');

    expect(staleLabel.isNotEmpty, true);
    expect(tester.takeException(), isNull);
  });
}
