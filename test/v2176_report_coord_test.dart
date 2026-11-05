import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/services/spot_service.dart';

/// v2.1.76：报错时把「钓友现场的位置」一起传上去
///
/// 背景：坐标纠偏（v42）只能把高德的 GCJ-02 还原成 WGS-84，换算误差 < 1 米。
/// 所以「纠偏后还偏」一定是源坐标本身不是钓位（高德的 POI 常落在管理处/
/// 大门口/水体中心）。这种偏差换算修不掉，只有到过现场的人的 GPS 才知道
/// 真正的下竿位置 —— 所以报「坐标错误」时要把定位一起带走。
void main() {
  String read(String p) => File(p).readAsStringSync();

  setUp(() => SpotService.testLastReportBody = null);

  /// 测试环境没有登录态，reportSpot 会在最后一步抛「请先登录」。
  /// 但请求体在抛异常之前就已经拼好并记下来了 —— 我们要验证的正是那个 body。
  Future<void> report({
    String reason = '坐标错误',
    String? note,
    double? lat,
    double? lng,
    double? accuracy,
  }) async {
    try {
      await SpotService.reportSpot(
        spotId: 's1',
        spotName: '青龙湖水库',
        reason: reason,
        note: note,
        lat: lat,
        lng: lng,
        accuracy: accuracy,
      );
    } catch (_) {
      // 忽略「请先登录」：本用例只关心 body
    }
  }

  group('请求体：坐标只在拿到时才带', () {
    test('报「坐标错误」且定位成功 → lat/lng/accuracy 都在', () async {
      await report(lat: 34.1466, lng: 113.4857, accuracy: 8.0);
      final b = SpotService.testLastReportBody!;
      expect(b['lat'], 34.1466);
      expect(b['lng'], 113.4857);
      expect(b['accuracy'], 8.0);
      expect(b['reason'], '坐标错误');
    });

    test('没定位成功（没传坐标）→ 请求体里不出现坐标字段', () async {
      await report(note: '找不到');
      final b = SpotService.testLastReportBody!;
      expect(b.containsKey('lat'), isFalse);
      expect(b.containsKey('lng'), isFalse);
      expect(b['note'], '找不到');
    });

    test('accuracy 为 0 / 负数表示「取不到精度」，不要带上', () async {
      await report(lat: 34.1, lng: 113.4, accuracy: 0);
      expect(SpotService.testLastReportBody!.containsKey('accuracy'), isFalse);

      await report(lat: 34.1, lng: 113.4, accuracy: -1);
      expect(SpotService.testLastReportBody!.containsKey('accuracy'), isFalse);
    });

    test('其它原因的报错也能带上坐标字段以外的东西，不报错', () async {
      await report(reason: '已关闭');
      expect(SpotService.testLastReportBody!['reason'], '已关闭');
    });
  });

  group('详情页入口与弹窗', () {
    final detail = read('lib/screens/spot_detail_screen.dart');

    test('地址块里有「位置不对？」入口', () {
      expect(detail.contains('位置不对？点这里把你在现场的位置发给我们'), isTrue);
    });

    test('弹窗打开就自动取位置，不用用户再点一次', () {
      expect(detail.contains('_grab()'), isTrue);
      expect(detail.contains('LocationService.determinePosition()'), isTrue);
      // initState 里就调了
      expect(
        detail.contains('super.initState();') &&
            detail.contains('_grab();'),
        isTrue,
      );
    });

    test('只有选「坐标错误」才显示位置卡片、才把坐标带出去', () {
      expect(detail.contains("if (_reason == '坐标错误') ...[") ||
          detail.contains("if (_reason == '坐标错误')"), isTrue);
      expect(detail.contains("lat: _reason == '坐标错误' ? _lat : null"), isTrue);
      expect(detail.contains("lng: _reason == '坐标错误' ? _lng : null"), isTrue);
    });

    test('定位失败时给中文原因，不是裸异常', () {
      expect(detail.contains('LocationException'), isTrue);
      expect(detail.contains('定位失败，请检查定位权限'), isTrue);
    });

    test('弹窗里说明了「这个位置会被采纳成新坐标」', () {
      expect(detail.contains('建议坐标'), isTrue);
    });

    test('取到位置后提交成功会告诉用户位置一起上报了', () {
      expect(detail.contains('你的位置也一起上报了'), isTrue);
    });
  });
}
