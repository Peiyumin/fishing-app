import 'dart:io';

import 'package:fishing_app/screens/startup/permission_onboard_screen.dart';
import 'package:fishing_app/services/net_diag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 启动顺序回归测试（v2.1.65）
///
/// ── 用户报的 bug ──────────────────────────────────────────────
/// 新装 App，**启动页还在转「正在获取最新渔情」，iOS 的
/// 「允许“渔报”使用无线数据？」就盖在启动图上弹了出来**。
/// 那时候用户连权限清单都还没看到，完全不知道系统在问什么。
///
/// ── 真因 ─────────────────────────────────────────────────────
/// `_StartupGate._prepare()` 一上来就发 `AppService.bootstrap()`
/// （`/app/bootstrap`），而那一行几乎和启动页同一帧执行。iOS 的
/// 「使用无线数据」弹窗由 App **第一次真正发起请求**触发，于是必然
/// 落在启动页上。`UpdateDialog.checkAndShow()` 紧随其后，也是第二次请求。
///
/// ── 正确顺序（用户明确要求）──────────────────────────────────
/// 启动页 → 权限清单 → 点「一键开启全部权限」→ 一项一项弹系统框
/// → 显示「设置完成」→ 进登录注册页。
///
/// 所以首次安装时，**启动页期间一个请求都不许发**，第一次联网必须
/// 发生在用户点「一键开启全部权限」那一刻（队列第一位是网络）。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  NetDiagResult okResult({int tcpMs = 36}) => NetDiagResult(
        tcpOk: true,
        tcpMs: tcpMs,
        tcpError: '',
        httpStatus: 200,
        httpMs: 80,
        httpError: '',
      );

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 30));
    await t.pump(const Duration(milliseconds: 30));
  }

  final mainSrc = File('lib/main.dart').readAsStringSync();
  final onboardSrc =
      File('lib/screens/startup/permission_onboard_screen.dart')
          .readAsStringSync();

  group('首次安装：启动页期间不许联网', () {
    test('启动门先读「是否走过权限引导」，再决定要不要发 bootstrap', () {
      // 必须存在 _firstRun 这个闸门（没有它就等于又在启动页联网）
      expect(mainSrc.contains('_firstRun'), isTrue);

      // bootstrap 必须是「首次安装 → 空配置 / 否则 → 真请求」这个二选一，
      // 不能无条件 `AppService.bootstrap()`
      final idx = mainSrc.indexOf('final bootF =');
      expect(idx, greaterThan(0), reason: '找不到 bootF 的赋值');
      final seg = mainSrc.substring(idx, idx + 400);
      expect(seg.contains('_firstRun'), isTrue,
          reason: 'bootF 必须受 _firstRun 约束，否则首次安装照样在启动页联网');
      expect(seg.contains('AppBootstrap()'), isTrue,
          reason: '首次安装要直接给空配置，不能发请求');

      // 唯一无条件调用点应该在 else 分支里
      expect(mainSrc.contains('AppService.bootstrap()'), isTrue);
    });

    test('检查热更新也不能在首次安装时跑（那是第二次启动期请求）', () {
      final idx = mainSrc.indexOf('UpdateDialog.checkAndShow(context)');
      expect(idx, greaterThan(0));
      // 往前看 80 个字符必须能见到 `!_firstRun`
      final before = mainSrc.substring(idx > 80 ? idx - 80 : 0, idx);
      expect(before.contains('!_firstRun'), isTrue,
          reason: '启动页刚结束就查更新，会把无线数据弹窗再提前一次');
    });

    test('首次安装直接给空启动配置（不走启动广告/预览）', () {
      // 用户要的是「启动页 → 权限页 → 登录注册页」直线，
      // 刚装完就塞广告既不礼貌也会多一次请求
      expect(mainSrc.contains('Future<AppBootstrap>.value(const AppBootstrap())'),
          isTrue);
    });

    test('引导页仍以网络作为一键开启队列的第一位', () {
      final idx = onboardSrc.indexOf('Future<void> _requestAll() async {');
      expect(idx, greaterThan(0));
      final loopIdx = onboardSrc.indexOf('for (final r in _rows)', idx);
      final netIdx = onboardSrc.indexOf('第 1 项：网络', idx);
      expect(netIdx, greaterThan(0));
      expect(netIdx, lessThan(loopIdx),
          reason: 'iOS 的无线数据弹窗只认「第一次请求」，网络必须在权限循环之前');
    });
  });

  group('权限给完 → 显示「设置完成」→ 再进下一步', () {
    testWidgets('全部开启后先出现「设置完成」整页，1.2 秒后才回调 onDone', (t) async {
      var done = false;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () => done = true,
          debugGrantPerms: true,
          debugSkipAutoExit: true,
          probeNet: () async => okResult(),
        ),
      ));
      await settle(t);

      await t.tap(find.text('一键开启全部权限'));
      // 队列：网络探测 → 等待 320ms → 五项都已是授予态直接跳过
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 50));

      expect(find.text('设置完成'), findsOneWidget,
          reason: '用户要求「设置好后显示设置完成」，不能一闪而过');
      expect(find.textContaining('项权限已全部开启'), findsOneWidget);
      expect(done, isFalse, reason: '完成页要停一下，不能立刻跳走');

      // 1.2 秒之后才真正进下一步
      await t.pump(const Duration(milliseconds: 1300));
      expect(done, isTrue);
    });

    testWidgets('完成页显示的总项数是 6（网络 + 五项系统权限）', (t) async {
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: true,
          debugSkipAutoExit: true,
          probeNet: () async => okResult(),
        ),
      ));
      await settle(t);
      await t.tap(find.text('一键开启全部权限'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('6 项权限已全部开启'), findsOneWidget);
      // 完成页上不该再留权限清单
      expect(find.text('通知'), findsNothing);
      expect(find.text('一键开启全部权限'), findsNothing);

      await t.pump(const Duration(milliseconds: 1500));
    });

    testWidgets('网络不通时不会误显示「设置完成」', (t) async {
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: true,
          debugSkipAutoExit: true,
          probeNet: () async =>
              NetDiagResult(
                tcpOk: false,
                tcpMs: 6000,
                tcpError: 'SocketException: Connection timed out',
                httpStatus: 0,
                httpMs: 0,
                httpError: '',
              ),
        ),
      ));
      await settle(t);
      await t.tap(find.text('一键开启全部权限'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(find.text('设置完成'), findsNothing);
      // v2.1.66：超时类失败会先停在「请求中」补探一次（900ms），
      // 补探仍不通才转红 —— 否则会出现「红一下又变绿」的闪动。
      await t.pump(const Duration(milliseconds: 1600));
      expect(find.text('未连通'), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
    });

    test('收尾顺序护栏：必须先立 _allSet 再 refresh', () {
      final req = onboardSrc.indexOf('Future<void> _requestAll() async {');
      final allSetIdx = onboardSrc.indexOf('_allSet = true', req);
      final refreshIdx = onboardSrc.indexOf('await _refresh()', allSetIdx);
      expect(allSetIdx, greaterThan(req));
      expect(refreshIdx, greaterThan(allSetIdx),
          reason:
              '_refresh() 内部会调 _maybeAutoExit，先 refresh 会让它在 450ms 后把完成页顶掉');
    });
  });

  group('启动闸门', () {
    testWidgets('knownNeedOnboard: true 时直接出引导页，不闪纯底色', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: FirstRunPermissionGate(
          knownNeedOnboard: true,
          child: Text('主界面'),
        ),
      ));
      await t.pump();

      // 上层已经判定过要引导，第一帧就该是权限页，不该先铺一块空底色
      expect(find.text('开启需要的权限'), findsOneWidget);
      expect(find.text('主界面'), findsNothing);

      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('knownNeedOnboard 为 null 时仍自己读偏好（老用户放行）', (t) async {
      SharedPreferences.setMockInitialValues({kPermOnboardDone: true});
      await t.pumpWidget(const MaterialApp(
        home: FirstRunPermissionGate(child: Text('主界面')),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));

      expect(find.text('主界面'), findsOneWidget);
      expect(find.text('开启需要的权限'), findsNothing);
    });
  });
}
