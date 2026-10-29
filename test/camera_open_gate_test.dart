import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fishing_app/utils/open_gate.dart';

/// 相机页「永远卡在正在打开相机…」的回归护栏。
///
/// 事故原因：页面把 `bool _opening = true`（加载态）同时当重入锁，
/// `_openCamera()` 第一行 `if (_opening) return;` → 第一次调用就被挡住，
/// 一个 CameraController 都不会创建，两端界面都永远转圈。
void main() {
  group('OpenGate：新建即空闲，第一次必须能进', () {
    test('全新闸门 busy=false，tryEnter 返回 true', () {
      final g = OpenGate();
      expect(g.busy, isFalse, reason: '新建的闸门必须是空闲的，否则首次调用就被自锁');
      expect(g.tryEnter(), isTrue, reason: '第一次进入必须成功，这是相机能打开的前提');
      expect(g.busy, isTrue);
    });

    test('已占用时拒绝重入（防两个控制器抢摄像头）', () {
      final g = OpenGate();
      expect(g.tryEnter(), isTrue);
      expect(g.tryEnter(), isFalse);
      expect(g.tryEnter(), isFalse);
    });

    test('leave 之后可以再次进入（切换前后摄 / 点重试）', () {
      final g = OpenGate();
      g.tryEnter();
      g.leave();
      expect(g.busy, isFalse);
      expect(g.tryEnter(), isTrue);
    });

    test('重复 leave 无害', () {
      final g = OpenGate();
      g.tryEnter();
      g.leave();
      g.leave();
      expect(g.busy, isFalse);
      expect(g.tryEnter(), isTrue);
    });

    test('异常路径也必须走 leave 才不卡死（try/finally 语义）', () {
      final g = OpenGate();
      try {
        g.tryEnter();
        throw StateError('模拟 initialize 抛异常');
      } catch (_) {
        // 真实代码里 finally 在这里执行
      } finally {
        g.leave();
      }
      expect(g.busy, isFalse, reason: '失败后闸门必须释放，否则「重试打开相机」按钮点了没反应');
    });
  });

  group('相机页源码护栏', () {
    final src = File('lib/screens/watermark_camera_screen.dart').readAsStringSync();
    // 只看**代码**，不看注释：文件里保留了一段「当年为什么这么写错」的说明，
    // 里面就带着那两行反面写法，直接 contains 会误判成 bug 还在。
    final code = src.replaceAll(RegExp(r'//[^\n]*'), '');

    test('不允许再把加载态初值写成 true（自锁根因）', () {
      expect(code.contains('bool _opening = true'), isFalse,
          reason: 'bool _opening 初值必须是 false —— 它的语义是「初始化中」，不是「已占用」');
    });

    test('不允许用 _opening 当重入锁', () {
      expect(RegExp(r'if\s*\(\s*_opening\s*\)\s*return').hasMatch(code), isFalse,
          reason: '重入判断必须走 OpenGate，别再拿 UI 加载态当锁');
    });

    test('_openCamera 必须用闸门保护并且用 finally 释放', () {
      final i = src.indexOf('Future<void> _openCamera');
      expect(i, greaterThan(0));
      final body = src.substring(i, (i + 3000) > src.length ? src.length : i + 3000);
      expect(body.contains('_gate.tryEnter()'), isTrue,
          reason: '没有闸门保护 → 连点会开出两个控制器互相抢摄像头');
      expect(body.contains('_gate.leave()'), isTrue,
          reason: '没有释放 → 第二次打开（切换镜头/重试）没有任何反应');
      expect(body.contains('finally'), isTrue,
          reason: '释放必须写在 finally 里，否则任一 return/异常都会把闸门永久占住');
    });

    test('相机成功后才去要定位/天气（避免三个权限框同时弹）', () {
      final i = src.indexOf('Future<void> _openCamera');
      final body = src.substring(i, (i + 3000) > src.length ? src.length : i + 3000);
      expect(body.contains('_loadInfo()'), isTrue,
          reason: '天气/定位应在相机开成功后触发，不能和相机权限同时申请');
      expect(src.contains('addPostFrameCallback((_) => _loadInfo())'), isFalse,
          reason: '定位权限框会顶掉 iOS 的相机权限申请');
    });
  });
}
