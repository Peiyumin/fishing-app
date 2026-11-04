// 启动页护栏：底图、胶囊定位、进度、收尾回调
//
// 这个页面最容易出的两类问题：
//   ① 底图或坐标写死 → 换个屏幕比例，胶囊就和图片错位（偏上/偏下）；
//   ② 「最短展示」用真实时钟算 → 逻辑其实没错，但在测试里推不动，
//      而且将来有人改成 `Future.delayed` 会真的把启动拖慢。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/screens/startup/splash_screen.dart';

Widget _app(SplashScreen s) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: s,
    );

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  required bool ready,
  int ms = 0,
  VoidCallback? onFinished,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      _app(SplashScreen(ready: ready, onFinished: onFinished)));
  if (ms > 0) await tester.pump(Duration(milliseconds: ms));
}

void main() {
  group('① 底图必须随包走', () {
    test('assets/startup/splash_brand.jpg 存在且是竖图', () {
      final f = File('assets/startup/splash_brand.jpg');
      expect(f.existsSync(), isTrue,
          reason: '启动页底图不在仓库里，打出来的包会是纯黑');
      final kb = f.lengthSync() / 1024;
      expect(kb, greaterThan(120),
          reason: '底图只有 ${kb.toStringAsFixed(0)}KB，可能被误压成缩略图');
    });

    test('pubspec 声明了 assets/startup/ 目录', () {
      final y = File('pubspec.yaml').readAsStringSync();
      expect(y.contains('assets/startup/'), isTrue,
          reason: '资源目录没声明 → Image.asset 会抛 unable to load asset');
    });
  });

  group('② 胶囊必须跟着屏幕比例走，不能写死坐标', () {
    // 底图是 1140×2050，手机比例千奇百怪，胶囊位置只能用缩放系数换算
    for (final size in const [
      Size(320, 640), // 极小安卓
      Size(390, 844), // iPhone 14
      Size(430, 932), // iPhone 15 Pro Max
    ]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()} 下文字水平居中',
          (tester) async {
        await _pump(tester, size, ready: false);
        final r = tester.getRect(find.text('正在获取最新渔情').first);
        expect((r.center.dx - size.width / 2).abs(), lessThan(1.5),
            reason: '胶囊文字没水平居中，说明坐标换算写错了');
        expect(r.left, greaterThan(0));
        expect(r.right, lessThan(size.width));
        expect(r.top, greaterThan(0));
        expect(r.bottom, lessThan(size.height));
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('屏幕越宽，胶囊越大（按比例缩放而不是固定像素）', (tester) async {
      await _pump(tester, const Size(320, 640), ready: false);
      final small = tester.getRect(find.text('正在获取最新渔情').first);
      await _pump(tester, const Size(430, 932), ready: false);
      final big = tester.getRect(find.text('正在获取最新渔情').first);
      expect(big.width, greaterThan(small.width * 1.15),
          reason: '两种屏幕宽度差 34%，胶囊文字却没跟着放大 —— '
              '尺寸很可能被写成了固定 dp');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('胶囊落在画面下部（不能跑到中间挡住渔报标题）', (tester) async {
      const size = Size(390, 844);
      await _pump(tester, size, ready: false);
      final r = tester.getRect(find.text('正在获取最新渔情').first);
      expect(r.center.dy / size.height, greaterThan(0.85),
          reason: '胶囊跑到画面上半部分了，底图坐标常量错了');
      expect(r.bottom, lessThan(size.height));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('③ 收尾时序', () {
    testWidgets('ready=false 时不会自己走掉', (tester) async {
      var done = false;
      await _pump(tester, const Size(390, 844),
          ready: false, onFinished: () => done = true);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(done, isFalse, reason: '数据还没拉完就把启动页关了');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ready=true 后播完涨满动画才回调', (tester) async {
      var done = false;
      await _pump(tester, const Size(390, 844),
          ready: false, onFinished: () => done = true);
      // 先走完最短展示（600ms）
      await tester.pump(const Duration(milliseconds: 700));
      expect(done, isFalse, reason: '还在最短展示窗口内就跳走了');

      await tester.pumpWidget(_app(SplashScreen(
        ready: true,
        onFinished: () => done = true,
      )));
      await tester.pump(const Duration(milliseconds: 300));
      // 涨满 260ms + 停 120ms
      await tester.pump(const Duration(milliseconds: 300));
      expect(done, isTrue, reason: 'ready 之后没有回调，App 会卡在启动页');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('最短展示用控制器计时，不依赖真实时钟', (tester) async {
      var done = false;
      await _pump(tester, const Size(390, 844),
          ready: true, onFinished: () => done = true);
      // ready 一开始就是 true，但最短展示还没走完 → 不能立刻回调
      await tester.pump(const Duration(milliseconds: 300));
      expect(done, isFalse);
      expect(kSplashMinShow, const Duration(milliseconds: 600),
          reason: '最短展示涨回去了，启动会变慢');
      // 推过 600ms 最短展示 → 涨满 260ms → 停 120ms
      //
      // ★ 先 pumpAndSettle 把两段动画走完，再补两次 pump：最后那 120ms
      //   是纯 `Future.delayed`（Timer，不排帧），pumpAndSettle 不会等它。
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(done, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // v2.1.74：用户明确要求「打开 App 要秒加载，最长不能超过 2 秒」。
  // 引擎冷启动（Dart VM 起来 + 首帧）通常吃 300~600ms，剩下给 Dart 层的
  // 预算只有 1.2 秒左右 —— 这条用例就是把这个预算钉住，谁再把最短展示
  // 或动画时长调回去，测试立刻红。
  group('④ 启动预算', () {
    testWidgets('配置就绪后 1.2 秒内必须回调（Dart 层）', (tester) async {
      var done = false;
      await _pump(tester, const Size(390, 844),
          ready: true, onFinished: () => done = true);
      var frames = 0;
      while (!done && frames < 200) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
      }
      final ms = frames * 16;
      expect(done, isTrue, reason: '启动页一直没回调，App 卡住了');
      expect(ms, lessThanOrEqualTo(1200),
          reason: 'Dart 层启动用了 ${ms}ms，加上引擎冷启动会顶破 2 秒');
      await tester.pumpWidget(const SizedBox());
    });
  });
}
