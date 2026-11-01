import 'dart:io';

import 'package:fishing_app/screens/startup/permission_onboard_screen.dart';
import 'package:fishing_app/services/net_diag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首次启动权限引导页的「网络」项回归测试（v2.1.63）
///
/// 事故背景：用户新装 App，权限引导页里 5 项全点了「允许」，进 App 后
/// 登录/注册一直提示「连接失败」，回头看清单觉得「少了个网络权限」。
///
/// 实测结论（不是猜的）：
///   · APK 里 `android.permission.INTERNET`、`ACCESS_NETWORK_STATE` 都在，
///     `usesCleartextTraffic=true` 也在（aapt2 直接读的安装包）；
///   · ipa 里 `NSAppTransportSecurity.NSAllowsArbitraryLoads=true` 在，
///     四项用法说明也齐。
///   所以不是打包丢了权限 —— 两个平台根本没有可申请的「网络权限」。
///
/// 真正的原因是 iOS 那个「是否允许使用无线数据」系统弹窗：它只在 App
/// **第一次真的发请求**时弹出，不在任何权限清单里，老流程里这个时机落在
/// 「引导页关闭、进首页之后」，用户完全不知道还有这么一个框。
///
/// 修法：把网络做成引导页第一项（进页面就探一次，把弹窗在引导页内消化掉），
/// 并且**网络连不上时不许自动进首页**。下面锁的就是这两条。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// 探测结果构造器：默认「端口通 + 接口 200」= 真的能上网
  NetDiagResult okResult({int tcpMs = 36}) => NetDiagResult(
        tcpOk: true,
        tcpMs: tcpMs,
        tcpError: '',
        httpStatus: 200,
        httpMs: 80,
        httpError: '',
      );

  NetDiagResult offlineResult(String err) => NetDiagResult(
        tcpOk: false,
        tcpMs: 6012,
        tcpError: err,
        httpStatus: 0,
        httpMs: 0,
        httpError: '',
      );

  /// 探测是异步的，跑几拍让 setState 落定。
  /// 不能用 pumpAndSettle —— 检测中会有一个不停转的进度圈。
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 30));
    await t.pump(const Duration(milliseconds: 30));
  }

  group('「网络」项出现在清单里', () {
    testWidgets('列表第一项是网络，总数按 6 项算', (t) async {
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          probeNet: () async => okResult(),
        ),
      ));
      await settle(t);

      expect(find.text('网络'), findsOneWidget);
      // 网络 + 通知/定位/相机/麦克风/相册 = 6
      expect(find.textContaining('/6'), findsOneWidget);
      // 五项系统权限仍在
      expect(find.text('通知'), findsOneWidget);
      expect(find.text('位置信息'), findsOneWidget);

      // 屏幕放不下 6 行，最后一项要滚一下才会被构建（ListView 懒构建）
      await t.drag(find.byType(ListView), const Offset(0, -320));
      await t.pump();
      expect(find.text('照片与视频'), findsOneWidget);
    });

    testWidgets('探测通 → 显示「已连通」并打勾，不再劝用户去修', (t) async {
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          probeNet: () async => okResult(tcpMs: 36),
        ),
      ));
      await settle(t);

      expect(find.textContaining('已连通'), findsOneWidget);
      expect(find.textContaining('36 ms'), findsOneWidget);
      expect(find.text('去修复'), findsNothing);
      expect(find.text('未连通'), findsNothing);
    });

    testWidgets('端口连不上 → 标「未连通」+「去修复」，按钮变红字', (t) async {
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: true,
          probeNet: () async =>
              offlineResult('SocketException: Connection timed out'),
        ),
      ));
      await settle(t);

      expect(find.text('未连通'), findsOneWidget);
      expect(find.text('去修复'), findsOneWidget);
      // 超时要翻译成人话，不能把英文异常直接铺给用户
      expect(find.textContaining('连接超时'), findsOneWidget);
      expect(find.text('网络未通，点这里修复'), findsOneWidget);
      // 也不能把用户永久关在这儿
      expect(find.text('仍要先进入'), findsOneWidget);
    });

    testWidgets('端口通但接口 500 → 说「服务异常」，不是让用户折腾 WiFi', (t) async {
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          probeNet: () async => NetDiagResult(
            tcpOk: true,
            tcpMs: 40,
            tcpError: '',
            httpStatus: 500,
            httpMs: 90,
            httpError: '',
          ),
        ),
      ));
      await settle(t);

      expect(find.text('服务异常'), findsOneWidget);
      expect(find.textContaining('HTTP 500'), findsOneWidget);
      expect(find.textContaining('已连通'), findsNothing);
    });
  });

  group('自动进入首页的闸门', () {
    testWidgets('权限全开 + 网络不通 → 绝不自动进（本次修复的核心）', (t) async {
      var exited = false;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () => exited = true,
          debugGrantPerms: true,
          probeNet: () async =>
              offlineResult('SocketException: Network is unreachable'),
        ),
      ));
      await settle(t);
      // 原来 450ms 就会自动跳走，这里多等一会儿确认没跳
      await t.pump(const Duration(seconds: 2));

      expect(exited, isFalse,
          reason: '网络不通还自动进首页，用户只会在登录页撞「连接失败」');
      expect(find.text('未连通'), findsOneWidget);
    });

    testWidgets('权限全开 + 网络正常 → 照旧自动进首页', (t) async {
      var exited = false;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () => exited = true,
          debugGrantPerms: true,
          probeNet: () async => okResult(),
        ),
      ));
      await settle(t);
      await t.pump(const Duration(milliseconds: 700));

      expect(exited, isTrue);
    });

    testWidgets('权限全开 + 服务器异常 → 放行（这是服务端问题，用户修不了）', (t) async {
      var exited = false;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () => exited = true,
          debugGrantPerms: true,
          probeNet: () async => NetDiagResult(
            tcpOk: true,
            tcpMs: 40,
            tcpError: '',
            httpStatus: 502,
            httpMs: 90,
            httpError: '',
          ),
        ),
      ));
      await settle(t);
      await t.pump(const Duration(milliseconds: 700));

      expect(exited, isTrue);
    });
  });

  group('修复弹窗', () {
    testWidgets('点「去修复」给出可照做的步骤 + 诊断详情', (t) async {
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          probeNet: () async =>
              offlineResult('SocketException: Connection timed out'),
        ),
      ));
      await settle(t);

      await t.tap(find.text('去修复'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('网络连不上怎么办'), findsOneWidget);
      // 必须给具体路径，不能只说「请检查网络」
      expect(find.textContaining('换一个网络再检测'), findsOneWidget);
      // 诊断详情可复制（用户要发截图/文本时用得上）
      expect(find.text('复制诊断'), findsOneWidget);
      expect(find.text('重新检测'), findsOneWidget);

      // 关掉弹窗，让 toast/Timer 走完
      await t.tap(find.text('重新检测'));
      await t.pump();
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('网络正常时点整行 = 重新检测，不会弹修复窗', (t) async {
      var probes = 0;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          probeNet: () async {
            probes++;
            return okResult();
          },
        ),
      ));
      await settle(t);
      expect(probes, 1);

      await t.tap(find.text('网络'));
      await settle(t);

      expect(probes, 2);
      expect(find.text('网络连不上怎么办'), findsNothing);
    });
  });

  group('网络权限的客观事实护栏', () {
    test('Android 清单里必须有 INTERNET（release 包丢它就是全网崩）', () {
      // 读源码文件而不是运行时：这条要防的是「有人手滑删了清单那一行」，
      // 那种改动在 debug 包里完全看不出来（debug 有自己的清单兜底）。
      final src = _read('android/app/src/main/AndroidManifest.xml');
      expect(src, contains('android.permission.INTERNET'));
      expect(src, contains('android.permission.ACCESS_NETWORK_STATE'));
      // 后端是 http://IP:8801，Android 9+ 默认禁明文，这个开关必须在
      expect(src, contains('android:usesCleartextTraffic="true"'));
    });

    test('iOS 必须放行明文 HTTP，且补了本地网络说明', () {
      final src = _read('ios/Runner/Info.plist');
      expect(src, contains('NSAppTransportSecurity'));
      expect(src, contains('NSAllowsArbitraryLoads'));
      // 缺这个 key 时，切到局域网地址会被系统直接终止进程
      expect(src, contains('NSLocalNetworkUsageDescription'));
    });
  });
}

String _read(String rel) {
  // 测试的工作目录是项目根（flutter test 约定）
  return _file(rel);
}

String _file(String rel) {
  final f = File(rel);
  if (!f.existsSync()) {
    throw StateError('找不到 $rel（测试工作目录应为项目根）');
  }
  return f.readAsStringSync();
}
