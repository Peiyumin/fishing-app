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

    testWidgets('失败后自动重试，用户点了「允许」→ 显示已连通', (t) async {
      var probes = 0;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          probeNet: () async {
            probes++;
            // 第一次：用户还在看系统弹窗，请求挂着直到超时
            if (probes == 1) return fail('SocketException: Connection timed out');
            // v2.1.67：失败会按预算一直重试，第二拍就代表「用户点了允许」
            // 第二次：用户点了「允许」，链路已可用
            return okResult();
          },
        ),
      ));
      await settle(t);

      await t.tap(find.text('一键开启全部权限'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      // 第一轮失败后要等一个轮询间隔才重试
      expect(find.text('未连通'), findsNothing,
          reason: '重试之前不该先把红脸挂出来再收回');

      await t.pump(const Duration(milliseconds: 1200));
      await settle(t);

      expect(probes, greaterThanOrEqualTo(2), reason: '失败必须自己重试');
      expect(find.textContaining('已连通'), findsOneWidget);
      expect(find.text('未连通'), findsNothing);

      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('系统禁网（no route）→ 预算用光才判红，且说清是被系统关了', (t) async {
      var probes = 0;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          debugNetWait: const Duration(milliseconds: 300),
          debugNetPollGap: const Duration(milliseconds: 20),
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

      // v2.1.67：ENETUNREACH 既可能是「真被禁」也可能是「系统弹窗还挂着」，
      // 两者用异常分不开，只能靠重试到预算用光来区分。
      expect(probes, greaterThan(2), reason: '重试到最后才下结论');
      expect(find.text('未连通'), findsOneWidget);
      // ★ 不能再说「手机没有可用网络」—— 手机明明上着网，是 App 被禁
      expect(find.textContaining('手机没有可用网络'), findsNothing);
      // 路径按平台分叉（iOS「无线数据」/ 安卓「流量」），都指向 app 的设置页。
      // v2.1.68 起会同时出现在两处：行内副标题 + App 的授权框，所以是 findsWidgets。
      expect(find.textContaining('→ 渔报'), findsWidgets);
    });

    testWidgets('系统没弹授权框 → 立刻用 App 的框补上（不能一直「请求中」）', (t) async {
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: true, // 五项系统权限都给了，只剩网络
          debugSkipAutoExit: true,
          debugNetWait: const Duration(milliseconds: 300),
          debugNetPollGap: const Duration(milliseconds: 20),
          probeNet: () async => fail('SocketException: Network is unreachable'),
        ),
      ));
      await settle(t);

      await t.tap(find.text('一键开启全部权限'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));

      // ★ v2.1.67 的老框不许再出现：它说的是「其余 5 项都开好了」，
      //   而这一步是队列第一步，五项根本还没问过。
      expect(find.text('网络被系统挡住了'), findsNothing);

      // 预算跑完、系统一次都没弹 → App 的授权框必须顶上来
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 60));
      expect(find.text('无线数据还没有授权'), findsOneWidget,
          reason: '系统不弹框时，App 必须有一个授权界面，不能让用户干等');
      expect(find.text('去打开设置'), findsOneWidget);
      expect(find.text('继续开启其他权限'), findsOneWidget);
      // 唯一能解决问题的路径必须写死在框里
      expect(find.textContaining('渔报 →'), findsOneWidget);

      // 选择「先继续」→ 框收起，队列照常往下走，不卡在这一步
      await t.tap(find.text('继续开启其他权限'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('无线数据还没有授权'), findsNothing);
    });

    testWidgets('点「去修复」→ 标题直指系统挡网，并给「去系统设置」', (t) async {
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          debugNetWait: const Duration(milliseconds: 300),
          debugNetPollGap: const Duration(milliseconds: 20),
          probeNet: () async => fail('SocketException: Network is unreachable'),
        ),
      ));
      await settle(t);
      await t.tap(find.text('允许').first);
      await settle(t);
      await t.pump(const Duration(seconds: 2));
      await settle(t);
      // v2.1.68：单点「允许」失败后同样会先给 App 的授权框，先关掉它
      await t.tap(find.text('继续开启其他权限'));
      await settle(t);
      await t.pump(const Duration(milliseconds: 400));
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
    test('网络这一项必须「重试到有结果」，不能一次失败就判死', () {
      final src = _read('lib/screens/startup/permission_onboard_screen.dart');
      // ★ v2.1.67 的教训：iOS 弹窗挂着时 socket 立刻 ENETUNREACH，
      //   不是超时 —— 所以单次超时设多长都没用，必须轮询重试。
      expect(src, contains('_waitNetReady'), reason: '必须有轮询重试的路径');
      expect(src, contains('Duration(seconds: 40)'),
          reason: '整个网络步骤的预算要足够用户看清并点掉系统弹窗');
      expect(src, contains('_pollGap'),
          reason: '两次重试之间要留间隔，且要能被「切回前台」打断');
      expect(src, contains('WidgetsBindingObserver'),
          reason: '从系统设置切回来要立刻补探，而不是干等下一拍');
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
