// v2.1.60 视觉修正的护栏
//
// ① 钓点卡：缩略图必须**等大**（96×96），不能再用 IntrinsicHeight 让图跟着
//    文字高度伸缩 —— 一旦有卡多一行标签，图就比别的卡高一截（用户截图里
//    三张卡的图三种高度）。
// ② 卡内行距压到 2~3pt，别回到 7/9/5 那种松散排版。
// ③ 「我的」页封面：从 132 的窄条加高到 248，底部靠长渐变 + 渐进模糊化进白底，
//    不能退回「一道窄条 + 一刀切」。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/screens/spots_screen.dart';

void main() {
  group('钓点卡缩略图等大', () {
    testWidgets('四张卡的缩略图都是 96×96，且矩形完全一致', (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: SpotsScreen()));
      // 无网络时回落演示数据，两拍就够
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));

      final thumbs = find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 96 && w.height == 96);
      expect(thumbs.evaluate().length, greaterThanOrEqualTo(3),
          reason: '演示数据有 4 条，缩略图应该都是 96×96 的 SizedBox');

      final rects = thumbs
          .evaluate()
          .map((e) => tester.getRect(find.byElementPredicate((x) => x == e)))
          .toList();
      for (final r in rects) {
        expect(r.size, const Size(96, 96), reason: '缩略图尺寸必须完全一致');
      }
      // 高度集合必须只有一个值 —— 这就是「图片显示要一样大」
      expect(rects.map((r) => r.height).toSet().length, 1);
    });

    test('spots_screen 不再用 IntrinsicHeight 撑图', () {
      final src = File('lib/screens/spots_screen.dart').readAsStringSync();
      expect(src.contains('IntrinsicHeight('), isFalse,
          reason: '按内容撑高会让缩略图跟着文字高度变，图就不等大了');
    });

    test('卡内行距保持紧凑（没有 7/9/5 那种大间距）', () {
      final src = File('lib/screens/spots_screen.dart').readAsStringSync();
      for (final bad in ['SizedBox(height: 7)', 'SizedBox(height: 9)']) {
        expect(src.contains(bad), isFalse, reason: '卡内出现过大行距 $bad');
      }
    });
  });

  group('我的页封面铺满 + 渐隐虚化', () {
    final src = File('lib/screens/profile_screen.dart').readAsStringSync();

    test('封面高度不再是一道 132 的窄条', () {
      final m = RegExp(r'const coverH = ([\d.]+);').firstMatch(src);
      expect(m, isNotNull, reason: '找不到 coverH 常量');
      final h = double.parse(m!.group(1)!);
      expect(h, greaterThanOrEqualTo(200),
          reason: '封面低于 200 又会变回「只显示一半」的窄条');
    });

    test('封面有渐进模糊层（同源图 + ShaderMask 擦出来）', () {
      expect(src.contains('ImageFiltered'), isTrue);
      expect(src.contains('ShaderMask'), isTrue);
      expect(src.contains('BlendMode.dstIn'), isTrue);
      expect(src.contains('TileMode.clamp'), isTrue,
          reason: 'blur 不加 clamp 会在边缘透出白边');
    });

    test('渐隐是长渐变（4 个 stops），不是一刀切', () {
      final m = RegExp(r'stops: const \[([\d., ]+)\]').allMatches(src).toList();
      expect(m, isNotEmpty);
      final hasLongFade = m.any((e) => e.group(1)!.split(',').length >= 4);
      expect(hasLongFade, isTrue, reason: '需要 0→0.58→0.86→0.98 这种长过渡带');
    });
  });
}
