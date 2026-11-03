import 'dart:io';

import 'package:fishing_app/screens/startup/permission_onboard_screen.dart';
import 'package:fishing_app/services/net_diag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 网络这一项「点完系统弹窗 → 显示已完成 → 继续下一项」（v2.1.67）
///
/// ── 用户报的现象 ──────────────────────────────────────────────
/// 「点击一键权限后是正确弹出网络权限，点击第一项无线网络数据后，
///   应该显示为已完成，然后进行下一项的权限开启。现在是直接显示
///   『网络被系统挡住了』，逻辑是错的。」
///
/// ── 真因 ────────────────────────────────────────────────────
/// iOS 的「允许使用无线数据」弹窗**挂着**时，`Socket.connect` 不会挂起等待，
/// 而是**立刻**抛 `Network is unreachable`。v2.1.66 把这种失败当成
/// 「系统禁网」，当场下结论并弹框；用户点「允许」的动作比这个结论还慢，
/// 于是「给了权限却报网络不通」。
///
/// ── 现在的行为 ──────────────────────────────────────────────
/// 失败不再立刻定案：停在「请求中」按预算反复重试，通了就把这一项标成
/// 「已完成」，再自动进入下一项（通知）；只有预算用光才判红，且只在
/// 队列末尾提示，不去打断用户正在看的系统弹窗。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  NetDiagResult ok({int tcpMs = 42}) => NetDiagResult(
        tcpOk: true,
        tcpMs: tcpMs,
        tcpError: '',
        httpStatus: 200,
        httpMs: 90,
        httpError: '',
      );

  NetDiagResult down(String err) => NetDiagResult(
        tcpOk: false,
        tcpMs: 0,
        tcpError: err,
        httpStatus: 0,
        httpMs: 0,
        httpError: '',
      );

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 30));
    await t.pump(const Duration(milliseconds: 30));
  }

  group('点完系统弹窗 → 这一项变「已完成」→ 继续下一项', () {
    testWidgets('系统弹窗挂着时连不上（ENETUNREACH）→ 不许判红；点了允许 → 已完成',
        (t) async {
      var probes = 0;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          debugNetWait: const Duration(seconds: 3),
          debugNetPollGap: const Duration(milliseconds: 50),
          probeNet: () async {
            probes++;
            // 前三次 = 系统弹窗还挂在屏幕上（iOS 此时直接 ENETUNREACH）
            if (probes <= 3) return down('SocketException: Network is unreachable');
            // 第四次 = 用户点了「无线局域网与蜂窝网络」
            return ok();
          },
        ),
      ));
      await settle(t);

      await t.tap(find.text('一键开启全部权限'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));

      // ★ 这一条就是用户看到的 bug：弹窗还在，页面已经红着脸说「被系统禁网」
      expect(find.text('未连通'), findsNothing,
          reason: '系统弹窗还没被点，不能先把「未连通」挂出来');
      expect(find.text('网络被系统挡住了'), findsNothing);
      expect(find.text('请求中'), findsOneWidget);

      // 走过几次重试（用户点下「允许」）
      await t.pump(const Duration(milliseconds: 200));
      await t.pump(const Duration(milliseconds: 60));

      expect(probes, greaterThanOrEqualTo(4));
      expect(find.text('未连通'), findsNothing);
      // ★ 用户的原话：这一项要显示为「已完成」
      expect(find.text('已完成'), findsOneWidget);
      expect(find.textContaining('已连通'), findsOneWidget);
      // 而且不能弹那个「被挡住了」的框来打断
      expect(find.text('网络被系统挡住了'), findsNothing);

      // 停留一下之后自动进入下一项（通知），不需要用户再点一次
      await t.pump(const Duration(milliseconds: 700));
      await t.pump(const Duration(milliseconds: 60));
      expect(find.textContaining('正在开启 2/6：通知'), findsOneWidget,
          reason: '网络完成后必须自动往下走，而不是停在那儿等用户点');

      // 把队列剩下的收尾跑完
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('网络通了以后，顶部计数从 0/6 变成 1/6', (t) async {
      var probes = 0;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          debugNetWait: const Duration(seconds: 3),
          debugNetPollGap: const Duration(milliseconds: 50),
          probeNet: () async {
            probes++;
            if (probes <= 2) return down('SocketException: Network is unreachable');
            return ok();
          },
        ),
      ));
      await settle(t);
      await t.tap(find.text('允许').first);
      await t.pump();
      expect(find.textContaining('0/6'), findsOneWidget);

      await t.pump(const Duration(milliseconds: 200));
      await t.pump(const Duration(milliseconds: 60));
      expect(find.textContaining('1/6'), findsOneWidget,
          reason: '网络这一项也要计入「已开启」的进度');
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('从系统设置切回来（resumed）→ 立刻补探，不用干等', (t) async {
      var probes = 0;
      var netAllowed = false; // 模拟「设置里的无线数据开关」
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          debugNetWait: const Duration(milliseconds: 300),
          debugNetPollGap: const Duration(milliseconds: 20),
          probeNet: () async {
            probes++;
            return netAllowed ? ok() : down('SocketException: Network is unreachable');
          },
        ),
      ));
      await settle(t);

      // 先让它落到红的「未连通」
      await t.tap(find.text('允许').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await settle(t);
      expect(find.text('未连通'), findsOneWidget);
      // v2.1.68：系统没弹授权框时，单点「允许」也会先给 App 的授权框，关掉它
      await t.tap(find.text('继续开启其他权限'));
      await settle(t);
      await t.pump(const Duration(milliseconds: 300));
      await settle(t);
      final before = probes;

      // 用户在设置里打开了「无线数据」，切回 App
      netAllowed = true;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(t);
      await t.pump(const Duration(milliseconds: 100));
      await settle(t);

      expect(probes, greaterThan(before), reason: '切回前台要立刻补探');
      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('未连通'), findsNothing);
    });
  });

  group('源码护栏', () {
    test('App 的授权框只能在「系统确实没弹」时出现，且不能在队列中间瞎弹', () {
      final src = File('lib/screens/startup/permission_onboard_screen.dart')
          .readAsStringSync();
      final body = src.substring(
        src.indexOf('Future<void> _requestAll()'),
        src.indexOf('Future<void> _openSettings()'),
      );
      // ★ v2.1.68：允许在队列中间给「授权框」（系统不弹时必须有界面顶上），
      //   但**必须**用 _promptSeen 把关 —— 系统框正在屏幕上时插嘴就是冤枉人。
      final askAt = body.indexOf('_askNetAuthorize()');
      expect(askAt, greaterThan(-1), reason: '系统不弹时必须有一个 App 侧授权框');
      expect(body.substring(0, askAt), contains('!_promptSeen'),
          reason: '没见过系统弹窗才能插 App 的框');

      // 那条「其余 N 项都开好了」的收尾框仍然只能在队列末尾
      final loopAt = body.indexOf('for (final r in _rows)');
      final promptAt = body.indexOf('await _promptNetBlocked()');
      expect(loopAt, greaterThan(-1));
      expect(promptAt, greaterThan(loopAt),
          reason: '用户还在点系统弹窗时，不能被一句「网络被挡住了」打断');
    });

    test('失败要停在「请求中」重试，不能直接落红', () {
      final src = File('lib/screens/startup/permission_onboard_screen.dart')
          .readAsStringSync();
      final body = src.substring(
        src.indexOf('Future<bool> _waitNetReady()'),
        src.indexOf('Future<void> _pollGap('),
      );
      expect(body, contains('_net = _NetState.checking'),
          reason: '失败后要回到「请求中」继续等，而不是 _net = offline');
      expect(body, contains('debugNetWait'), reason: '预算可调，测试不用真等 40 秒');
      // ★ v2.1.68：系统没弹框时必须能自己收手，别让用户对着「请求中」干等
      expect(body, contains('_promptSeen'),
          reason: '要用「系统弹没弹」来决定等还是收手');
      expect(body, contains('_isTimeoutError'),
          reason: '卡满超时的失败要继续等（可能弹窗正攥着连接），秒失败才收手');
    });
  });
}
