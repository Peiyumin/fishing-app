import 'dart:async';
import 'dart:io';

import 'package:fishing_app/screens/startup/permission_onboard_screen.dart';
import 'package:fishing_app/services/net_diag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 权限引导页「网络」这一项到底怎么算通过（v2.1.66）
///
/// ── 用户报的现象 ──────────────────────────────────────────────
/// 「点一键开启后，通知会弹系统框，网络不弹就跳过了，紧接着显示网络不通
///   需要修复，给它权限也还是报网络不通。」
///
/// ── 真因（两条，都得修）──────────────────────────────────────
/// ① **超时 6 秒，比用户点弹窗还快。**
///    iOS 的「是否允许使用无线数据」没有 API 可申请，唯一触发方式是
///    「App 第一次真正发网络请求」。引导页的探测就是那一次请求：弹窗挂起时
///    `Socket.connect` 一直等着，用户还没看清弹窗，6 秒超时先到 → 判成
///    「未连通」→ 用户点完「允许」，页面也不会自己恢复。
///    所以引导页改为 15 秒，并加一次自动补探（超时类失败才补）。
/// ② **ENETUNREACH 被翻译成「手机没有可用网络」。**
///    iOS 关掉本 App 的「无线数据」时，socket 直接 no route —— 手机明明
///    上着网。文案把人指去重启路由器，永远修不好。现在直说：
///    「联网被系统关了：设置 → 渔报 → 无线数据」，并给「去系统设置」按钮。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  NetDiagResult okResult({int tcpMs = 42}) => NetDiagResult(
        tcpOk: true,
        tcpMs: tcpMs,
        tcpError: '',
        httpStatus: 200,
        httpMs: 90,
        httpError: '',
      );

  NetDiagResult fail(String err, {int ms = 6000}) => NetDiagResult(
        tcpOk: false,
        tcpMs: ms,
        tcpError: err,
        httpStatus: 0,
        httpMs: 0,
        httpError: '',
      );

  /// 探测是异步的，跑几拍让 setState 落定（不能 pumpAndSettle）
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 30));
    await t.pump(const Duration(milliseconds: 30));
  }

  group('网络这一项要像一次真的授权请求', () {
    testWidgets('点一键开启 → 网络项显示「请求中」并在界面上说明会弹系统框', (t) async {
      // 用 Completer 把探测挂住，好在「正在请求」这一帧上做断言
      final gate = Completer<NetDiagResult>();
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          probeNet: () => gate.future,
        ),
      ));
      await settle(t);

      await t.tap(find.text('一键开启全部权限'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));

      // ★ 关键：不能一按下去就静默跑完。要让用户看见「正在请求网络授权」
      expect(find.text('请求中'), findsOneWidget);
      expect(find.textContaining('允许使用无线数据'), findsOneWidget,
          reason: 'iOS 的无线数据弹窗没有 API 可申请，只能在界面里提前告知');
      // 按钮上要写清现在轮到第几项（截图里原来只有一句「正在开启…」）
      expect(find.textContaining('正在开启 1/6：网络'), findsOneWidget);

      gate.complete(okResult());
      await settle(t);
      // 队列后面的权限项走完，别留 pending timer
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('超时失败 → 自动补探一次，第二次通了就显示已连通', (t) async {
      var probes = 0;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          probeNet: () async {
            probes++;
            // 第一次：用户还在看系统弹窗，请求挂着直到超时
            if (probes == 1) return fail('SocketException: Connection timed out');
            // 第二次：用户点了「允许」，链路已可用
            return okResult();
          },
        ),
      ));
      await settle(t);

      await t.tap(find.text('一键开启全部权限'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      // 第一轮失败后要等 900ms 才补探
      expect(find.text('未连通'), findsNothing,
          reason: '补探之前不该先把红脸挂出来再收回');

      await t.pump(const Duration(milliseconds: 1200));
      await settle(t);

      expect(probes, 2, reason: '超时类失败必须自动补探一次');
      expect(find.textContaining('已连通'), findsOneWidget);
      expect(find.text('未连通'), findsNothing);

      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('系统禁网（no route）→ 不瞎补探，直接说清是被系统关了', (t) async {
      var probes = 0;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          probeNet: () async {
            probes++;
            return fail('SocketException: Network is unreachable');
          },
        ),
      ));
      await settle(t);

      await t.tap(find.text('允许').first);
      await settle(t);
      await t.pump(const Duration(seconds: 2));
      await settle(t);

      expect(probes, 1, reason: '系统禁网补探多少次都是同一个结果，立刻收手');
      expect(find.text('未连通'), findsOneWidget);
      // ★ 不能再说「手机没有可用网络」—— 手机明明上着网，是 App 被禁
      expect(find.textContaining('手机没有可用网络'), findsNothing);
      // 路径按平台分叉（iOS「无线数据」/ 安卓「流量」），都指向 app 的设置页
      expect(find.textContaining('→ 渔报'), findsOneWidget);
    });

    testWidgets('点「去修复」→ 标题直指系统挡网，并给「去系统设置」', (t) async {
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          probeNet: () async => fail('SocketException: Network is unreachable'),
        ),
      ));
      await settle(t);
      await t.tap(find.text('允许').first);
      await settle(t);
      await t.pump(const Duration(seconds: 2));
      await settle(t);

      await t.tap(find.text('去修复'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('网络被系统挡住了'), findsOneWidget);
      // 必须把「一个 App 只问一次」这条事实讲出来，否则用户会一直等弹窗
      expect(find.textContaining('不会再弹'), findsOneWidget);
      expect(find.textContaining('手动打开'), findsOneWidget);
      expect(find.text('去系统设置'), findsOneWidget);

      await t.tap(find.text('重新检测'));
      await t.pump();
      await t.pump(const Duration(seconds: 2));
    });
  });

  group('源码护栏', () {
    test('引导页探测必须给系统弹窗留够时间（≥15s），且失败要补探', () {
      final src = _read('lib/screens/startup/permission_onboard_screen.dart');
      expect(src, contains('Duration(seconds: 15)'),
          reason: '6 秒的默认超时比用户点弹窗还快，会误判成网络不通');
      expect(src, contains('_probeWithRetry'), reason: '必须有补探路径');
      expect(src, contains('_netMaybeWaiting'),
          reason: '补探只该针对「等回应超时」，系统禁网补也没用');
    });

    test('NetDiag 的超时必须可传入（否则引导页没法单独放宽）', () {
      final src = _read('lib/services/net_diag.dart');
      expect(src, contains('Duration tcpTimeout'));
      expect(src, contains('Duration httpTimeout'));
    });

    test('iOS 修复路径第一条必须是「设置 → 渔报 → 无线数据」', () {
      final src = _read('lib/widgets/net_fix_steps.dart');
      expect(src, contains('设置 → 渔报 → 无线数据'),
          reason: '这个开关就在 App 自己的设置页里，比「蜂窝网络」短一层');
    });
  });
}

String _read(String rel) {
  final f = File(rel);
  if (!f.existsSync()) {
    throw StateError('找不到 $rel（测试工作目录应为项目根）');
  }
  return f.readAsStringSync();
}
