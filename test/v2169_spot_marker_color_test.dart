import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/fishing_spot.dart';
import 'package:fishing_app/utils/spot_marker_style.dart';
import 'package:fishing_app/widgets/spot_pin.dart';

/// 地图标记按身份区分颜色 + 改成小房子（v2.1.69）
///
/// 用户要求：野钓点绿 / 黑坑·鱼塘·收费红 / 渔具店蓝，图标改成小房子。
///
/// 之前所有钓点都是「红针 + 白鱼」，一张地图上分不出免费河段和 200/4h 的黑坑，
/// 所以判据定成三条：
///   · 分类只看钓点本身（kind / type / fee），不看出身；
///   · 三类颜色互不相同，且和用户说的颜色对得上（绿/红/蓝）；
///   · 两套地图内核都必须按分类取色（源码护栏），不能只改一处。
void main() {
  FishingSpot spot({
    String kind = 'wild',
    String type = '野钓',
    String fee = '',
    String name = '测试点',
  }) =>
      FishingSpot(
        id: 'id-$name',
        name: name,
        type: type,
        kind: kind,
        lat: 34.19,
        lng: 113.47,
        rating: 0,
        description: '',
        fee: fee,
      );

  group('分类规则', () {
    test('野钓点（没有收费信息）→ 绿', () {
      final s = spot(kind: 'wild', type: '野钓');
      expect(SpotMarkerStyle.roleOf(s), SpotMarkerRole.wild);
      expect(SpotMarkerStyle.colorOf(s), SpotMarkerStyle.wildColor);
    });

    test('本地钓场 → 红（哪怕没填 fee）', () {
      final s = spot(kind: 'venue', type: '路亚');
      expect(SpotMarkerStyle.roleOf(s), SpotMarkerRole.paid);
      expect(SpotMarkerStyle.colorOf(s), SpotMarkerStyle.paidColor);
    });

    test('渔具店 → 蓝', () {
      final s = spot(kind: 'shop', type: '渔具店');
      expect(SpotMarkerStyle.roleOf(s), SpotMarkerRole.shop);
      expect(SpotMarkerStyle.colorOf(s), SpotMarkerStyle.shopColor);
    });

    test('野钓点但写明了价格 → 红', () {
      expect(SpotMarkerStyle.roleOf(spot(fee: '50 元/天')), SpotMarkerRole.paid);
      expect(SpotMarkerStyle.roleOf(spot(fee: '正钓 200/4h')), SpotMarkerRole.paid);
      expect(SpotMarkerStyle.roleOf(spot(fee: '¥80')), SpotMarkerRole.paid);
    });

    test('type 写黑坑 / 鱼塘 → 红（即使 kind 是 wild）', () {
      expect(SpotMarkerStyle.roleOf(spot(type: '黑坑')), SpotMarkerRole.paid);
      expect(SpotMarkerStyle.roleOf(spot(type: '鱼塘')), SpotMarkerRole.paid);
    });

    test('「免费 / 免费停车」不算收费 → 绿', () {
      expect(SpotMarkerStyle.roleOf(spot(fee: '免费')), SpotMarkerRole.wild);
      expect(SpotMarkerStyle.roleOf(spot(fee: '免费停车')), SpotMarkerRole.wild);
      expect(SpotMarkerStyle.roleOf(spot(fee: '无')), SpotMarkerRole.wild);
    });

    test('三类颜色互不相同（绿 / 红 / 蓝）', () {
      final colors = SpotMarkerRole.values.map(SpotMarkerStyle.colorOfRole).toSet();
      expect(colors.length, 3);
      expect(SpotMarkerStyle.wildColor.green, greaterThan(SpotMarkerStyle.wildColor.red),
          reason: '绿：G 分量应最大');
      expect(SpotMarkerStyle.paidColor.red, greaterThan(SpotMarkerStyle.paidColor.blue),
          reason: '红：R 分量应最大');
      expect(SpotMarkerStyle.shopColor.blue, greaterThan(SpotMarkerStyle.shopColor.red),
          reason: '蓝：B 分量应最大');
    });

    test('原生内核的图片 id 按分类各一张', () {
      expect(SpotMarkerRole.values.map(SpotMarkerStyle.iconIdOfRole).toSet(),
          {'spot-pin-wild', 'spot-pin-paid', 'spot-pin-shop'});
    });
  });

  group('标记绘制', () {
    testWidgets('SpotPin 用传入的颜色画，改色必须重绘', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: SpotPin(color: SpotMarkerStyle.wildColor)),
      ));
      final paint = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<SpotPinPainter>()
          .first;
      expect(paint.color, SpotMarkerStyle.wildColor);
      expect(const SpotPinPainter().color, AppTheme.danger,
          reason: '默认色保持旧行为，避免别处调用变黑');
      expect(
        const SpotPinPainter(color: Colors.green)
            .shouldRepaint(const SpotPinPainter(color: Colors.blue)),
        isTrue,
      );
      expect(
        const SpotPinPainter(color: Colors.green)
            .shouldRepaint(const SpotPinPainter(color: Colors.green)),
        isFalse,
      );
    });
  });

  test('源码护栏：两套内核都按分类取色', () {
    final map = File('lib/screens/spot_map_screen.dart').readAsStringSync();
    expect(map.contains('SpotPin(color: SpotMarkerStyle.colorOf(s))'), isTrue,
        reason: 'flutter_map 内核的标记颜色没接上分类');

    final gl = File('lib/screens/spot_map_gl.dart').readAsStringSync();
    expect(gl.contains("'match'"), isTrue,
        reason: '原生内核必须用 match 表达式按 role 切图');
    expect(gl.contains("['get', 'role']"), isTrue,
        reason: 'match 表达式必须读 role 属性');
    expect(gl.contains('_ensureSpotIcons'), isTrue,
        reason: '原生内核必须把三类针图都注册进 addImage');
    expect(gl.contains("'role': SpotMarkerStyle.roleOf(s).name"), isTrue,
        reason: '要素里必须带 role，否则表达式取不到值');
  });
}
