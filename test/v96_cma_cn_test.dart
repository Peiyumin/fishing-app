import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/services/cma_cn_weather.dart';
import 'package:fishing_app/services/geo_place.dart';
import 'package:fishing_app/services/weather_service.dart';

/// v2.1.96：接中国气象局做国内天气源
///
/// ── 起因 ─────────────────────────────────────────────────
/// 唯一数据源是境外 Open-Meteo，部分移动网络下 TLS 握手被卡住，天气永远
/// 停在「获取中」。用户追问「不能用国内的天气数据嘛」。
///
/// ── 实测国内源能给什么（2026-11-16）───────────────────────
/// 中央气象台是「0 晴 / 1 多云 / 2 阴 / 7 小雨…」这套自己的编码，必须逐条
/// 翻成 WMO，否则图标和文字全对不上；**没有逐小时、没有紫外线数值、没有
/// 日出日落**，逐时按日最高最低温做分段正弦插值；气压趋势不编（置 null）。
///
/// 这组用例钉三件事：
///   1. 报文能正确翻译（含代码映射、湿度曲线不是平线）；
///   2. 境外全断时自动落到国内源并标记 `lastSource`；
///   3. 境外正常时不额外打国内接口（省流量、也不改变原有精度）。

/// 气象局 `/api/autocomplete` 的响应
String _autocomplete(String hits) => jsonEncode({
      'msg': 'success',
      'code': 0,
      'data': hits.split(';'),
    });

/// 气象局 `/api/weather/view` 的响应
String _viewJson() {
  final now = DateTime.now();
  String d(DateTime t) => '${t.year}/${t.month}/${t.day}';
  final days = <Map<String, Object>>[];
  for (var i = 0; i < 7; i++) {
    final t = now.add(Duration(days: i));
    days.add({
      'date': d(t),
      'high': 13.0 + i,
      'low': 6.0 + i,
      'dayText': i == 0 ? '小雨' : '晴',
      'dayCode': i == 0 ? 7 : 0,
      'dayWindDirection': '东北风',
      'dayWindScale': '3~4级',
      'nightText': i == 0 ? '小雨' : '晴',
      'nightCode': i == 0 ? 7 : 0,
      'nightWindDirection': '东北风',
      'nightWindScale': '微风',
    });
  }
  return jsonEncode({
    'msg': 'success',
    'code': 0,
    'data': {
      'location': {
        'id': '57088',
        'name': '禹州',
        'path': '中国, 河南, 许昌, 禹州',
        'longitude': 113.48,
        'latitude': 34.16,
        'timezone': 8,
      },
      'daily': days,
      'now': {
        'precipitation': 0.4,
        'temperature': 10.0,
        'pressure': 1004.0,
        'humidity': 87.0,
        'windDirection': '东北风',
        'windDirectionDegree': 55.0,
        'windSpeed': 2.2,
        'windScale': '微风',
        'feelst': 8.5,
      },
      'jieQi': '',
      'alarm': [],
      'lastUpdate': '2026/11/16 14:35',
    },
  });
}

/// 让气象局的客户端应答；`onPath` 可统计每个接口被调了几次
http.Client _cmaClient(void Function(String path)? onPath) {
  return MockClient((req) async {
    final p = req.url.path;
    onPath?.call(p);
    if (p.contains('autocomplete')) {
      return http.Response.bytes(
        utf8.encode(_autocomplete(
            '57088|禹州|Yuzhou|中国;57083|郑州|Zhengzhou|中国')),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (p.contains('weather/view')) {
      return http.Response.bytes(
        utf8.encode(_viewJson()),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('not found', 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WeatherService.clearMemory();
    GeoPlace.setMemoForTest(null);
  });

  tearDown(() {
    WeatherService.clearMemory();
    GeoPlace.setMemoForTest(null);
  });

  group('气象局报文 → 通用天气包', () {
    test('实况与 7 天都能翻译出来', () async {
      CmaCnWeatherService.clientOverride = _cmaClient(null);
      final b = await CmaCnWeatherService.fetchBundle(34.16, 113.48,
          placeName: '禹州市');
      expect(b, isNotNull);

      expect(b!.curTemp, closeTo(10.0, 0.01));
      expect(b.curPressure, closeTo(1004.0, 0.01));
      expect(b.curHumidity, 87);
      expect(b.curWindSpeed, closeTo(2.2 * 3.6, 0.1), reason: 'm/s 要换成 km/h');
      expect(b.curWindDir, 55);
      // 今天小雨 → 降水概率不能是 0
      expect(b.curPrecipProb, greaterThan(50));
      expect(b.days.length, 7);
      expect(b.hours.length, 7 * 24);
      expect(CmaCnWeatherService.lastStationName, '禹州');
    });

    test('气象局代码 7（小雨）要翻成 WMO 61，不能原样透传', () async {
      CmaCnWeatherService.clientOverride = _cmaClient(null);
      final b = await CmaCnWeatherService.fetchBundle(34.16, 113.48,
          placeName: '禹州');
      // 原样透传的话会是 7 → WMO 7 是「未知」，图标和文字都会错
      expect(b!.days.first.weatherCode, 61);
      expect(b.curCode, 61);
      expect(b.hours.first.weatherCode, 61);
    });

    test('逐时是插值出来的，但必须有日内起伏（否则水温模型算不了）', () async {
      CmaCnWeatherService.clientOverride = _cmaClient(null);
      final b = await CmaCnWeatherService.fetchBundle(34.16, 113.48,
          placeName: '禹州');
      final today = b!.hours.take(24).toList();
      final t5 = today[5].temp;
      final t14 = today[14].temp;
      expect(t14, greaterThan(t5), reason: '14 时应当比 5 时暖');
      expect(t14 - t5, greaterThan(3),
          reason: '日高低温差 7℃，插值后日内振幅不能缩成 1~2℃');

      // 湿度不能是一条平线（真实露点算不出，但至少随温度反向变化）
      final hums = today.map((h) => h.humidity).toSet();
      expect(hums.length, greaterThan(3));

      // 气压趋势必须为空：气象局日报不给变压，编一个会直接带偏垂钓指数
      expect(today.every((h) => h.pressureTrend == null), isTrue);
      expect(today.every((h) => h.pressureDelta3h == null), isTrue);
    });

    test('站名对不上就不给数据，绝不拿模糊结果冒充本地天气', () async {
      CmaCnWeatherService.clientOverride =
          MockClient((req) async => http.Response.bytes(
                utf8.encode(_autocomplete('57083|郑州|Zhengzhou|中国')),
                200,
                headers: {'content-type': 'application/json'},
              ));
      final b = await CmaCnWeatherService.fetchBundle(34.16, 113.48,
          placeName: '不存在的地名zzz');
      expect(b, isNull, reason: '模糊命中别的城市会让用户看到外地的天气');
    });

    test('接口挂了就老实返回 null，不抛给界面', () async {
      CmaCnWeatherService.clientOverride = MockClient((req) async {
        throw const SocketException('down');
      });
      final b = await CmaCnWeatherService.fetchBundle(34.16, 113.48,
          placeName: '禹州');
      expect(b, isNull);
      expect(CmaCnWeatherService.lastError, isNotNull);
    });
  });

  group('境外源不通 → 自动落到国内源', () {
    test('Open-Meteo 与后端代理全断，仍能拿到天气', () async {
      GeoPlace.setMemoForTest(const GeoPlace(
        province: '河南省',
        city: '许昌市',
        district: '禹州市',
        short: '禹州',
        display: '河南省许昌市禹州市',
      ));
      // 境外：直连和后端代理都抛异常
      WeatherService.clientOverride = MockClient((req) async {
        throw const SocketException('TLS handshake timeout');
      });
      CmaCnWeatherService.clientOverride = _cmaClient(null);

      final w = await WeatherService.fetch(34.16, 113.48);

      expect(WeatherService.lastSource, 'cma-cn');
      expect(WeatherService.lastIsDomestic, isTrue);
      expect(WeatherService.lastError, isNull,
          reason: '国内源救回来了就不该再显示「天气没拉到」');
      expect(w.temperature, closeTo(10.0, 0.5));
      expect(w.pressure, closeTo(1004.0, 0.5));
      expect(w.fishIndex, isNotEmpty);
      // 首页要能显示的水氧 / 水温也得算得出来
      expect(WeatherService.memoryWaterTemp, isNotNull);
    });

    test('区县没有气象站时退回地级市再查', () async {
      GeoPlace.setMemoForTest(const GeoPlace(
        province: '河南省',
        city: '许昌市',
        district: '魏都区',
        short: '魏都',
        display: '河南省许昌市魏都区',
      ));
      WeatherService.clientOverride = MockClient((req) async {
        throw const SocketException('down');
      });
      final seen = <String>[];
      CmaCnWeatherService.clientOverride = MockClient((req) async {
        if (req.url.path.contains('autocomplete')) {
          final q = req.url.queryParameters['q'] ?? '';
          seen.add(q);
          // 只有「许昌」查得到站，区县名查不到
          final hits = q == '许昌' ? '57089|许昌|Xuchang|中国' : '';
          return http.Response.bytes(
            utf8.encode(hits.isEmpty
                ? jsonEncode({'msg': 'success', 'code': 0, 'data': []})
                : _autocomplete(hits)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response.bytes(
          utf8.encode(_viewJson()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final w = await WeatherService.fetch(34.16, 113.48);
      expect(seen, contains('魏都'), reason: '先按区县名查');
      expect(seen, contains('许昌'), reason: '区县查不到要退回地级市');
      expect(w.temperature, isNotNull);
    });

    test('境外源正常时不打国内接口（保持原有精度、也不多耗流量）', () async {
      GeoPlace.setMemoForTest(const GeoPlace(
        district: '禹州市',
        short: '禹州',
        display: '河南省许昌市禹州市',
      ));
      var cmaCalls = 0;
      CmaCnWeatherService.clientOverride = _cmaClient((_) => cmaCalls++);

      var proxyCalls = 0;
      WeatherService.clientOverride = MockClient((req) async {
        if (req.url.toString().contains('tile-proxy')) {
          proxyCalls++;
          return http.Response('proxy should not be used', 502);
        }
        if (req.url.toString().contains('models=cma_grapes_global')) {
          return http.Response('{}', 200);
        }
        if (req.url.toString().contains('open-meteo')) {
          return http.Response.bytes(
            utf8.encode(jsonEncode(_openMeteo())),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final w = await WeatherService.fetch(34.16, 113.48);
      expect(WeatherService.lastSource, 'open-meteo');
      expect(cmaCalls, 0, reason: '境外源好的时候不该再去打气象局');
      expect(proxyCalls, 0);
      expect(w.temperature, isNotNull);
    });

    test('没有地名又不通 → 照旧抛错，不硬凑一份假天气', () async {
      GeoPlace.setMemoForTest(null);
      WeatherService.clientOverride = MockClient((req) async {
        throw const SocketException('down');
      });
      CmaCnWeatherService.clientOverride = _cmaClient(null);

      await expectLater(
        WeatherService.fetch(34.16, 113.48),
        throwsA(isA<Exception>()),
      );
      expect(WeatherService.lastError, isNotNull);
    });
  });
}

/// 一份最小的 Open-Meteo 正常报文（境外源可用时走这条路）
Map<String, dynamic> _openMeteo() {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  String d2(int v) => v.toString().padLeft(2, '0');
  String iso(DateTime t) =>
      '${t.year}-${d2(t.month)}-${d2(t.day)}T${d2(t.hour)}:00';

  final hours = List.generate(7 * 24, (i) => start.add(Duration(hours: i)));
  final days = List.generate(7, (i) => start.add(Duration(days: i)));
  return {
    'current': {
      'temperature_2m': 12.5,
      'relative_humidity_2m': 70,
      'weather_code': 2,
      'wind_speed_10m': 8.0,
      'wind_direction_10m': 300,
      'pressure_msl': 1009.0,
      'precipitation': 0.0,
      'precipitation_probability': 10,
    },
    'hourly': {
      'time': hours.map(iso).toList(),
      'temperature_2m': List.generate(168, (i) => 10.0 + (i % 12) * 0.7),
      'relative_humidity_2m': List.generate(168, (i) => 55 + (i % 30)),
      'precipitation': List.filled(168, 0.0),
      'precipitation_probability': List.generate(168, (i) => (i * 3) % 100),
      'weather_code': List.generate(168, (i) => i % 4 == 0 ? 0 : 2),
      'wind_speed_10m': List.generate(168, (i) => 2.0 + (i % 9) * 2.0),
      'wind_direction_10m': List.generate(168, (i) => (i * 29) % 360),
      'pressure_msl': List.generate(168, (i) => 1007.0 + (i % 18) * 0.7),
      'uv_index': List.generate(168, (i) => (i % 10) * 0.7),
      'cloud_cover': List.generate(168, (i) => 30.0 + (i % 60)),
    },
    'daily': {
      'time': days
          .map((d) => '${d.year}-${d2(d.month)}-${d2(d.day)}')
          .toList(),
      'weather_code': List.filled(7, 2),
      'temperature_2m_max': List.filled(7, 18.0),
      'temperature_2m_min': List.filled(7, 8.0),
      'precipitation_sum': List.filled(7, 0.0),
      'precipitation_probability_max': List.filled(7, 20),
      'wind_speed_10m_max': List.filled(7, 15.0),
      'wind_direction_10m_dominant': List.filled(7, 300),
      'uv_index_max': List.filled(7, 4.0),
      'sunrise': List.filled(7, '${start.year}-01-01T06:30'),
      'sunset': List.filled(7, '${start.year}-01-01T18:10'),
    },
  };
}
