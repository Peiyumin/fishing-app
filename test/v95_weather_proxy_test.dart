import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/home_mode.dart';
import 'package:fishing_app/services/api_config.dart';
import 'package:fishing_app/services/weather_service.dart';
import 'package:fishing_app/widgets/home_weather_hero.dart';

/// v2.1.95：天气「一直获取中」的兜底通道
///
/// ── 用户报的现象（截图）─────────────────────────────────────
/// 首页天气卡停在「获取中 / 正在获取当前位置的天气…」，四格全是 `--`，
/// 而钓点、动态都正常 —— 说明 App 网络没问题，只有气象数据拿不到。
///
/// ── 真因 ─────────────────────────────────────────────────
/// 天气走的是境外数据源 `api.open-meteo.com`（OVH 加拿大）。部分移动网络
/// （尤其 5G）下 DNS 能解析、TCP 能连，**TLS 握手被卡住** —— Dart 侧看到的就是
/// 一个不返回的请求，5~8 秒后超时抛错；而卡片没有「失败」画法，用户只能干等。
///
/// ── 修法 ─────────────────────────────────────────────────
/// 直连失败 → 同一个 URL 交给自家后端 `/tile-proxy`（机房出口）再试一次；
/// 两条都不通才失败，并且界面显示原因 + 「重试」。
///
/// 这组用例就是钉住这条链路：宿主机打不挂 open-meteo，所以用 MockClient
/// 造出「直连抛异常 / 代理返回 200」两种世界。

Map<String, dynamic> _mockForecast() {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  String d2(int v) => v.toString().padLeft(2, '0');

  final hTime = <String>[];
  final temp = <double>[], hum = <int>[], precip = <double>[];
  final pp = <int>[], code = <int>[], ws = <double>[], wd = <int>[];
  final pres = <double>[], uv = <double>[], cloud = <double>[];
  for (var i = 0; i < 7 * 24; i++) {
    final t = start.add(Duration(hours: i));
    hTime.add('${t.year}-${d2(t.month)}-${d2(t.day)}T${d2(t.hour)}:00');
    temp.add(13.8 + (i % 12) * 0.9);
    hum.add(60 + (i % 30));
    precip.add(0);
    pp.add((i * 7) % 100);
    code.add(i % 5 == 0 ? 0 : (i % 3 == 0 ? 2 : 3));
    ws.add(1.0 + (i % 9) * 2.5);
    wd.add((i * 37) % 360);
    pres.add(1008.0 + (i % 20) * 0.8);
    uv.add((i % 10) * 0.8);
    cloud.add(40.0 + (i % 50));
  }
  final dTime = List.generate(7, (i) {
    final d = start.add(Duration(days: i));
    return '${d.year}-${d2(d.month)}-${d2(d.day)}';
  });

  return {
    'current': {
      'temperature_2m': 16.4,
      'relative_humidity_2m': 72,
      'weather_code': 2,
      'wind_speed_10m': 7.2,
      'wind_direction_10m': 315,
      'pressure_msl': 1008.6,
    },
    'hourly': {
      'time': hTime,
      'temperature_2m': temp,
      'relative_humidity_2m': hum,
      'precipitation': precip,
      'precipitation_probability': pp,
      'weather_code': code,
      'wind_speed_10m': ws,
      'wind_direction_10m': wd,
      'pressure_msl': pres,
      'uv_index': uv,
      'cloud_cover': cloud,
    },
    'daily': {
      'time': dTime,
      'weather_code': List.generate(7, (i) => i % 4),
      'temperature_2m_max': List.generate(7, (i) => 22.0 + i),
      'temperature_2m_min': List.generate(7, (i) => 12.0 + i * 0.4),
      'sunrise': List.generate(7, (i) => '${dTime[i]}T06:12'),
      'sunset': List.generate(7, (i) => '${dTime[i]}T18:05'),
    },
  };
}

http.Response _okJson() => http.Response(
      jsonEncode(_mockForecast()),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WeatherService.clearMemory();
  });

  tearDown(() => WeatherService.clearMemory());

  test('直连抛异常（TLS 卡住）→ 自动走自家代理，天气照样拿到', () async {
    var direct = 0;
    var proxy = 0;
    WeatherService.clientOverride = MockClient((req) async {
      final u = req.url.toString();
      if (u.contains('tile-proxy')) {
        proxy++;
        // 代理请求里带的上游地址必须还是 open-meteo（不能换成别的东西）
        expect(u, contains('api.open-meteo.com'));
        return _okJson();
      }
      direct++;
      throw const SocketException('Connection reset by peer (TLS handshake)');
    });

    final w = await WeatherService.fetch(34.16, 113.48);

    expect(direct, greaterThan(0), reason: '必须真的先试过直连，不能一上来就赖代理');
    expect(proxy, greaterThan(0), reason: '直连失败后必须落到 /tile-proxy');
    expect(WeatherService.lastViaProxy, isTrue);
    expect(WeatherService.lastError, isNull, reason: '代理救回来了就不算失败');
    expect(w.temperature, isNotNull);
    expect(w.fishIndex, isNotEmpty);
  });

  test('直连返回 500 → 也算直连失败，走代理', () async {
    var proxy = 0;
    WeatherService.clientOverride = MockClient((req) async {
      if (req.url.toString().contains('tile-proxy')) {
        proxy++;
        return _okJson();
      }
      return http.Response('upstream error', 500);
    });

    final w = await WeatherService.fetch(34.16, 113.48);
    expect(proxy, greaterThan(0));
    expect(w.fishIndex, isNotEmpty);
  });

  test('直连与代理都不通 → 抛错，并留下可显示的原因', () async {
    WeatherService.clientOverride = MockClient((req) async {
      throw const SocketException('TLS handshake timeout');
    });

    await expectLater(
      WeatherService.fetch(34.16, 113.48),
      throwsA(isA<Exception>()),
    );
    expect(WeatherService.lastError, isNotNull);
    expect(WeatherService.lastError, isNotEmpty);
    expect(WeatherService.lastViaProxy, isFalse);
  });

  test('连续失败后熔断：下一次不再白等直连，直接找代理', () async {
    var direct = 0;
    var proxy = 0;
    WeatherService.clientOverride = MockClient((req) async {
      if (req.url.toString().contains('tile-proxy')) {
        proxy++;
        throw const SocketException('proxy down too');
      }
      direct++;
      throw const SocketException('direct down');
    });

    // 第一次：直连（主请求 + 第二模型各一次）全部失败 → 计数 ≥ 2
    await expectLater(
      WeatherService.fetch(34.16, 113.48),
      throwsA(isA<Exception>()),
    );
    final directAfterFirst = direct;
    expect(directAfterFirst, greaterThanOrEqualTo(2));

    // 第二次：熔断应生效 —— 直连次数不再增加
    await expectLater(
      WeatherService.fetch(34.17, 113.49),
      throwsA(isA<Exception>()),
    );
    expect(direct, directAfterFirst,
        reason: '连续失败后应当跳过直连，否则每次刷新都要白等 5 秒');
    expect(proxy, greaterThan(0));
  });

  test('代理前缀指向自家后端，且上游 URL 被完整编码（带全部查询参数）', () async {
    expect(ApiConfig.tileProxyBase, endsWith('r=/tile-proxy&url='));

    var seen = '';
    WeatherService.clientOverride = MockClient((req) async {
      seen = req.url.toString();
      return http.Response('boom', 502);
    });

    // 只关心「长 URL 有没有被完整带过去」，失败无所谓
    try {
      await WeatherService.fetch(34.1645, 113.4871);
    } catch (_) {}

    expect(seen, contains('tile-proxy'));
    expect(seen, contains(Uri.encodeComponent('forecast_days=7')),
        reason: 'hourly/daily 的一长串参数不能在半路被截断');
    expect(seen, contains(Uri.encodeComponent('latitude=34.1645')));
  });

  // ── 卡片本身：失败要看得见（v2.1.95 的界面部分）──────────────────
  group('首页天气卡的失败态', () {
    Widget host(Widget child) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(backgroundColor: AppTheme.background, body: child),
        );

    testWidgets('拉取失败时右侧变成「重试」，并写出原因', (t) async {
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);

      var retried = 0;
      await t.pumpWidget(host(HomeWeatherHero(
        weather: null,
        placeLabel: '禹州市',
        onTap: () {},
        failed: true,
        failReason: '连接超时',
        onRetry: () => retried++,
      )));
      await t.pump();

      expect(find.text('重试'), findsOneWidget);
      expect(find.text('获取中'), findsNothing,
          reason: '已经失败了还写「获取中」，用户就会一直干等');
      expect(find.textContaining('天气没拉到'), findsOneWidget);
      expect(find.textContaining('连接超时'), findsOneWidget);

      await t.tap(find.text('重试'));
      expect(retried, 1);
    });

    testWidgets('还在拉的时候仍然显示「获取中」（不能误报失败）', (t) async {
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);

      await t.pumpWidget(host(HomeWeatherHero(
        weather: null,
        placeLabel: '禹州市',
        onTap: () {},
        mode: HomeMode.taiDiao,
      )));
      await t.pump();

      expect(find.text('获取中'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      expect(find.textContaining('正在获取当前位置的天气'), findsOneWidget);
    });
  });
}
