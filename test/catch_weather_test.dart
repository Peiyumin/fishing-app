import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/models/catch_weather.dart';
import 'package:fishing_app/models/post.dart';

/// 渔获时天气快照：详情页的天气必须「定死」在发布那一刻，
/// 所以这里锁死三件事：序列化往返不丢精度、还原出来的三个模型数值一致、
/// 后端把快照当 JSON 字符串下发时也能解析出来。
void main() {
  CatchWeather sample() => CatchWeather(
        at: DateTime(2026, 10, 27, 12),
        temp: 18.1,
        humidity: 62,
        pressure: 1032.0,
        precipProb: 0,
        windSpeed: 12.0,
        windDir: 45,
        weatherCode: 1000,
        pressureTrend: 'steady',
        waterTemp: 17.3,
        oxygen: 8.3,
        score: 74,
        description: '晴',
        fishIndex: '口弱',
        fishAdvice: '气压高、口偏弱，主攻底层',
        atLabel: '12:00',
      );

  group('渔获时天气快照', () {
    test('JSON 往返不丢字段', () {
      final a = sample();
      final b = CatchWeather.fromJson(jsonDecode(jsonEncode(a.toJson())));
      expect(b, isNotNull);
      expect(b!.temp, a.temp);
      expect(b.humidity, a.humidity);
      expect(b.pressure, a.pressure);
      expect(b.waterTemp, a.waterTemp);
      expect(b.oxygen, a.oxygen);
      expect(b.score, a.score);
      expect(b.description, '晴');
      expect(b.fishIndex, '口弱');
      expect(b.atLabel, '12:00');
      expect(b.at, a.at);
    });

    test('还原成详情页渲染用的三个模型，数值完全一致', () {
      final a = sample();
      final h = a.toHourPoint();
      final w = a.toWaterMetrics();
      final f = a.toFishingWeather();

      expect(h.temp, 18.1);
      expect(h.pressure, 1032.0);
      expect(h.humidity, 62);
      expect(h.precipProb, 0);
      expect(h.hhmm, '12:00');

      expect(w.temp, 17.3);
      expect(w.oxygen, 8.3);

      expect(f.temperature, 18.1);
      expect(f.description, '晴');
      expect(f.fishIndex, '口弱');
      expect(f.score, 74);
    });

    test('帖子把快照当 JSON 字符串下发时也能解析', () {
      final raw = jsonEncode(sample().toJson());
      final post = Post.fromJson({
        'id': 'p1',
        'user_id': 'u1',
        'title': '今日鱼获分享',
        'category': 'post',
        'created_at': '2026-10-27T12:00:00.000Z',
        'weather_json': raw,
      });
      expect(post.weather, isNotNull);
      expect(post.weather!.score, 74);
      expect(post.weather!.atLabel, '12:00');
    });

    test('没有快照的老帖子不会崩，weather 为 null', () {
      final post = Post.fromJson({
        'id': 'p2',
        'user_id': 'u1',
        'title': '今日鱼获分享',
        'category': 'post',
        'created_at': '2026-10-27T12:00:00.000Z',
      });
      expect(post.weather, isNull);
    });

    test('坏 JSON 不会抛异常', () {
      expect(Post.parseWeather('{not json'), isNull);
      expect(Post.parseWeather(''), isNull);
      expect(Post.parseWeather(null), isNull);
    });
  });
}
