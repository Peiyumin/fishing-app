import 'dart:io';

import 'package:fishing_app/screens/startup/permission_onboard_screen.dart';
import 'package:fishing_app/services/net_diag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 网络这一项：**系统不弹框的时候，必须有一个授权界面顶上**（v2.1.68）
///
/// ── 用户报的现象 ──────────────────────────────────────────────
/// 「点击一键开启权限后，网络功能一直『请求中』，不会弹出授权界面。」
/// 截图里：第 1 项「请求中 / 还在等系统授权」，按钮「正在开启 1/6：网络」，
/// 页面上没有任何能点的东西，就这么停着。
///
/// ── 真因 ────────────────────────────────────────────────────
/// iOS 的「允许使用无线数据」**一个 App 只问一次**。这台机器之前已经答过
/// （被记成「不允许」），所以系统不会再弹任何东西 —— 而 v2.1.67 只会
/// 「反复重试 40 秒」，既弹不出系统框，也不给用户任何可操作的出口。
///
/// ── 现在的两条路 ─────────────────────────────────────────────
/// 用「App 有没有被压成 inactive」判断系统到底弹没弹：
///   · 弹了（inactive）→ 老老实实等用户点，绝不抢先判红、绝不插 App 的框；
///   · 没弹 → **约 2 秒就收手**，用 App 的授权框把这一步补上，并给出
///     「去打开设置」这条唯一能解决问题的路。
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

  group('系统弹没弹，决定等还是收手', () {
    testWidgets('系统框真的弹了（App 变 inactive）→ 一直等，绝不插 App 的框', (t) async {
      var netUp = false;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          debugNetWait: const Duration(seconds: 3),
          debugNetPollGap: const Duration(milliseconds: 50),
          probeNet: () async =>
              netUp ? ok() : down('SocketException: Network is unreachable'),
        ),
      ));
      await settle(t);

      await t.tap(find.text('一键开启全部权限'));
      await t.pump();

      // 系统把授权框盖上来 → App 收到 inactive（真机上就是这个信号）
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump(const Duration(milliseconds: 60));

      // ★ 框在屏幕上，界面必须直接告诉用户点哪一个
      expect(find.text('请点允许'), findsOneWidget,
          reason: '系统框出来了，右侧就该写「请点允许」');
      // 而且绝不能插自己的框、也不能判红 —— 用户还没点呢
      expect(find.text('无线数据还没有授权'), findsNothing,
          reason: '系统框还在屏幕上，插 App 的框就是冤枉人');
      expect(find.text('未连通'), findsNothing);

      // 用户点了「无线局域网与蜂窝网络」
      netUp = true;
      await t.pump(const Duration(milliseconds: 200));
      await t.pump(const Duration(milliseconds: 60));

      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('无线数据还没有授权'), findsNothing);

      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('系统一次都没弹 → 约 2 秒收手并给授权框，不许干等 40 秒', (t) async {
      // 用默认预算（40 秒 / 1 秒轮询），验证「会自己收手」这件事
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          probeNet: () async =>
              down('SocketException: Network is unreachable'),
        ),
      ));
      await settle(t);

      await t.tap(find.text('一键开启全部权限'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));

      // 第一拍：还在请求中，这是对的
      expect(find.text('请求中'), findsOneWidget);
      expect(find.text('无线数据还没有授权'), findsNothing);

      // 1.5 秒时还在重试（还没到收手的条件）
      await t.pump(const Duration(milliseconds: 1500));
      expect(find.text('无线数据还没有授权'), findsNothing);

      // 再走一拍就到第 3 次失败 → 收手 → App 的授权框顶上来
      await t.pump(const Duration(milliseconds: 900));
      await t.pump(const Duration(milliseconds: 60));

      expect(find.text('无线数据还没有授权'), findsOneWidget,
          reason: '系统不会弹的时候，必须给一个授权界面，不能让用户干等');
      expect(find.text('去打开设置'), findsOneWidget);
      expect(find.text('继续开启其他权限'), findsOneWidget);
      // 唯一能解决问题的路径写死在框里
      expect(find.textContaining('渔报 →'), findsOneWidget);
      // 老的那句「其余 5 项都开好了」不能出现 —— 这一步是队列第一步
      expect(find.text('网络被系统挡住了'), findsNothing);

      // 收尾：选「继续」
      await t.tap(find.text('继续开启其他权限'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('授权框点「去打开设置」→ 会重探，通了就变已完成并继续下一项', (t) async {
      var probes = 0;
      var netUp = false;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          debugNetWait: const Duration(milliseconds: 300),
          debugNetPollGap: const Duration(milliseconds: 20),
          probeNet: () async {
            probes++;
            return netUp ? ok() : down('SocketException: Network is unreachable');
          },
        ),
      ));
      await settle(t);

      await t.tap(find.text('一键开启全部权限'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 60));
      expect(find.text('无线数据还没有授权'), findsOneWidget);

      // 用户在设置里打开了「无线数据」
      netUp = true;
      final before = probes;
      await t.tap(find.text('去打开设置'));
      await t.pump();
      // openAppSettings 在宿主机上一个字都不回，代码里 1 秒超时兜住；
      // 之后 600ms 等 paused 落地、500ms 等链路重建，才重探。
      await t.pump(const Duration(milliseconds: 1400));
      await t.pump(const Duration(milliseconds: 800));
      await t.pump(const Duration(milliseconds: 300));

      expect(probes, greaterThan(before), reason: '点「去打开设置」后要重新探测');
      expect(find.text('无线数据还没有授权'), findsNothing);
      expect(find.text('已完成'), findsOneWidget);
      // 网络这一项过了就自动往下走
      await t.pump(const Duration(milliseconds: 700));
      await t.pump(const Duration(milliseconds: 60));
      expect(find.textContaining('正在开启 2/6'), findsOneWidget);

      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('这个框只弹一次：队列收尾时不再重复弹同一件事', (t) async {
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: true, // 五项都授予 → 队列很快跑完
          debugSkipAutoExit: true,
          debugNetWait: const Duration(milliseconds: 300),
          debugNetPollGap: const Duration(milliseconds: 20),
          probeNet: () async =>
              down('SocketException: Network is unreachable'),
        ),
      ));
      await settle(t);

      await t.tap(find.text('一键开启全部权限'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 60));
      expect(find.text('无线数据还没有授权'), findsOneWidget);

      await t.tap(find.text('继续开启其他权限'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));

      expect(find.text('无线数据还没有授权'), findsNothing);
      expect(find.text('网络被系统挡住了'), findsNothing,
          reason: '已经用过一次 App 的授权框，收尾别再弹一遍同样的内容');
      // 行内仍然如实标红，用户可以随时点「去修复」
      expect(find.text('未连通'), findsOneWidget);
    });
  });

  group('源码护栏', () {
    test('必须在「见过系统弹窗」和「没见过」之间分流', () {
      final src = File('lib/screens/startup/permission_onboard_screen.dart')
          .readAsStringSync();
      // 判据只能是 inactive：系统授权框盖上来时 App 一定先变 inactive
      expect(src, contains('AppLifecycleState.inactive'),
          reason: '要能"看见"系统弹窗外，没别的信号可用');
      expect(src, contains('_promptSeen'),
          reason: '见过/没见过要分开处理，否则又会干等到 40 秒');
      // 收手的条件里必须排除「卡满超时」：那种更像弹窗攥着连接，要继续等
      final wait = src.substring(
        src.indexOf('Future<bool> _waitNetReady()'),
        src.indexOf('Future<void> _pollGap('),
      );
      expect(wait, contains('instantFail'));
      expect(wait, contains('!_promptSeen'));
    });

    test('「去打开设置」要等用户回来，不能刷一下就重探', () {
      final src = File('lib/screens/startup/permission_onboard_screen.dart')
          .readAsStringSync();
      expect(src, contains('_openSettingsThenWait'),
          reason: '用户还在设置里翻菜单时，后台重探一万次都是失败');
      expect(src, contains('_foregroundWait'),
          reason: '要靠 resumed 信号判断他真的回来了');
    });
  });
}
