import 'package:fishing_app/models/fishing_species.dart';
import 'package:fishing_app/models/water_body.dart';
import 'package:fishing_app/models/weather_forecast.dart';
import 'package:fishing_app/services/ai_spot_service.dart';
import 'package:fishing_app/services/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// 造一份「现在前后都有数据」的天气包
WeatherBundle _fakeBundle({double temp = 22, int windDir = 180}) {
  final now = DateTime.now();
  final base = DateTime(now.year, now.month, now.day, now.hour);
  final hours = <HourPoint>[];
  for (var i = -6; i <= 20; i++) {
    hours.add(HourPoint(
      time: base.add(Duration(hours: i)),
      temp: temp,
      humidity: 65,
      pressure: 1013,
      precipProb: 10,
      precip: 0,
      windSpeed: 9,
      windDir: windDir,
      weatherCode: 2,
    ));
  }
  return WeatherBundle(
    lat: 30.24,
    lng: 120.12,
    curTemp: temp,
    curHumidity: 65,
    curPressure: 1013,
    curWindSpeed: 9,
    curWindDir: windDir,
    curPrecip: 0,
    curCode: 2,
    curPrecipProb: 10,
    hours: hours,
    days: [
      DaySummary(
        date: DateTime(now.year, now.month, now.day),
        weatherCode: 2,
        tempMax: 27,
        tempMin: 16,
        precipSum: 0,
        precipProbMax: 20,
        windSpeedMax: 14,
        windDirDom: windDir,
      ),
    ],
  );
}

WaterBody _river(String id, String name, double lat, double lng) => WaterBody(
      id: id,
      name: name,
      isRiver: true,
      geometry: [
        LatLng(lat, lng),
        LatLng(lat + 0.02, lng + 0.02),
        LatLng(lat + 0.05, lng + 0.05),
      ],
    );

void main() {
  setUp(() {
    WeatherService.testForecastOverride = (lat, lng) async => _fakeBundle();
  });
  tearDown(() {
    WeatherService.testForecastOverride = null;
  });

  group('AI 推荐钓点', () {
    test('按距离由近到远排序', () async {
      final list = await AiSpotService.recommend(
        lat: 30.24,
        lng: 120.12,
        spots: const [],
        waters: [
          _river('far', '远河', 31.2, 121.2), // ~130km
          _river('near', '近河', 30.25, 120.13), // ~1.5km
          _river('mid', '中河', 30.6, 120.5), // ~55km
        ],
        maxKm: 200,
      );
      expect(list.length, 3);
      for (var i = 1; i < list.length; i++) {
        expect(list[i].km, greaterThanOrEqualTo(list[i - 1].km),
            reason: '第 $i 个比前一个更近，排序错了');
      }
      expect(list.first.name, contains('近河'));
    });

    test('超出 maxKm 的不推荐', () async {
      final list = await AiSpotService.recommend(
        lat: 30.24,
        lng: 120.12,
        spots: const [],
        waters: [
          _river('near', '近河', 30.25, 120.13),
          _river('far', '远河', 33.0, 123.0), // 300km+
        ],
        maxKm: 60,
      );
      expect(list.map((e) => e.kind).length, 1);
      expect(list.single.name, contains('近河'));
    });

    test('分数在 0~100 且档位文案一致', () async {
      final list = await AiSpotService.recommend(
        lat: 30.24,
        lng: 120.12,
        spots: const [],
        waters: [_river('a', 'A河', 30.25, 120.13)],
        maxKm: 60,
      );
      final s = list.single;
      expect(s.score, inInclusiveRange(0, 100));
      if (s.score >= 90) {
        expect(s.grade, '爆护');
      } else if (s.score >= 80) {
        expect(s.grade, '有口');
      } else if (s.score < 25) {
        expect(s.grade, '无口');
      }
      // 理由里必须带水温，用户才知道凭什么推荐
      expect(s.reason, contains('水温'));
    });

    test('同距离下河流比湖泊更抗闷（分数更高或持平）', () async {
      final river = await AiSpotService.recommend(
        lat: 30.24,
        lng: 120.12,
        spots: const [],
        waters: [_river('r', '河', 30.25, 120.13)],
      );
      final lake = await AiSpotService.recommend(
        lat: 30.24,
        lng: 120.12,
        spots: const [],
        waters: [
          WaterBody(
            id: 'l',
            name: '湖',
            isRiver: false,
            kindLabel: '湖泊',
            geometry: [
              LatLng(30.25, 120.13),
              LatLng(30.26, 120.13),
              LatLng(30.26, 120.14),
              LatLng(30.25, 120.14),
              LatLng(30.25, 120.13),
            ],
          ),
        ],
      );
      expect(river.single.score, greaterThanOrEqualTo(lake.single.score));
    });

    test('距离文案：1km 内用米', () {
      expect(AiSpotService.kmText(0.42), '420m');
      expect(AiSpotService.kmText(3.25), '3.3km');
    });
  });

  group('天气时段统一', () {
    test('indexOfHourNear 取绝对时间最近的一小时（20:35 → 21:00）', () {
      final b = _fakeBundle();
      final i = b.indexOfHourNear(DateTime.now());
      expect(i, greaterThanOrEqualTo(0));
      final h = b.hours[i];
      // 与当前时间差不超过半小时
      expect(h.time.difference(DateTime.now()).inMinutes.abs(),
          lessThanOrEqualTo(31));
    });

    test('indexOfCurrentHour 取"现在所在"的那一小时（20:35 → 20:00）', () {
      // ★ 这是 v2.1.21 新增的口径：「当前时段」不能是还没到的下一小时。
      final b = _fakeBundle();
      final now = DateTime.now();
      final i = b.indexOfCurrentHour(now);
      expect(i, greaterThanOrEqualTo(0));
      expect(b.hours[i].time.hour, now.hour,
          reason: '当前时段必须是现在所处的整点，跨半点也不能跳到下一小时');
      expect(b.hours[i].time.day, now.day);
    });

    test('首页天气卡与天气页用同一小时的温度/天气/指数', () {
      final b = _fakeBundle(temp: 23.4);
      final w = FishingWeather.fromBundle(b);
      final now = DateTime.now();
      final h = b.hourCurrent(now)!;
      expect(w.temperature, h.temp, reason: '温度必须来自当前整点');
      expect(w.humidity, h.humidity, reason: '湿度必须来自同一小时');
      expect(w.windSpeed, h.windSpeed);
      expect(w.weatherCode, h.weatherCode);
      expect(w.atLabel, '${h.time.hour.toString().padLeft(2, '0')}:00',
          reason: '必须带时段标签，用户才知道是哪一小时');
      expect(w.score, inInclusiveRange(0, 100));
      // 与天气页顶部卡同引擎同小时 → 指数必须一致
      final mode = FishingMode.all.first;
      final sp = FishingSpecies.all.first;
      final metrics = WaterMetrics.derive(b.hours);
      final idx = b.indexOfCurrentHour(now);
      expect(w.score, Bite.score(h: h, w: metrics[idx], sp: sp, mode: mode),
          reason: '首页卡与天气页当前卡的垂钓指数必须同源同值');
    });

    test('缓存反序列化能带上分数与时段', () {
      final w = FishingWeather.fromBundle(_fakeBundle());
      final j = w.toJson();
      final back = FishingWeather.fromJson(j);
      expect(back.score, w.score);
      expect(back.atLabel, w.atLabel);
      expect(back.temperature, w.temperature);
    });
  });
}
