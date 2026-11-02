import 'dart:io';

import 'package:fishing_app/screens/startup/permission_onboard_screen.dart';
import 'package:fishing_app/services/net_diag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首次启动权限引导页的「网络」项回归测试（v2.1.64）
///
/// ── 事故背景（v2.1.63 已修的部分，这里继续钉住）─────────────────
/// 用户新装 App，引导页 5 项全点「允许」，进 App 后登录一直「连接失败」，
/// 回头看清单觉得「少了个网络权限」。实测（aapt2 读安装包 + 拆 ipa）：
///   · APK 里 INTERNET / ACCESS_NETWORK_STATE / usesCleartextTraffic 都在
///   · ipa 里 NSAllowsArbitraryLoads = true 在
///   → 两个平台根本没有可申请的「网络权限」，真凶是 iOS 那个
///     「是否允许使用无线数据」弹窗（只在第一次真发请求时弹）。
///
/// ── 本版（v2.1.64）改的是「它长什么样、什么时候动」──────────────
/// v2.1.63 一进页面就自动探测，于是页面刚出来网络那一项就红着脸写
/// 「未连通 / 去修复」，而下面五项干干净净写着「允许」—— 用户觉得
/// 「怎么一上来就说我有毛病」，且那个系统弹窗的时机比权限清单还早。
///
/// 现在：网络项初始就是中性的「允许」态，和下面五项同一个样式；
/// 点「一键开启全部权限」时它排**队列第一位**，和其他项一样一项一项过。
/// 下面锁的就是这个新行为。
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

  group('网络项初始就和其余五项一样', () {
    testWidgets('进页面不探测：显示「允许」，没有「未连通 / 去修复」', (t) async {
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

      // ★ 关键：页面刚出来不该自己发请求（那会让网络项一进来就变红）
      expect(probes, 0, reason: '进页面就自动探测 = 一打开就红着脸说用户网络有问题');

      expect(find.text('网络'), findsOneWidget);
      // 网络 + 通知/定位/相机/麦克风/相册 = 6，且此刻一项都没完成
      expect(find.textContaining('/6'), findsOneWidget);
      expect(find.textContaining('0/6'), findsOneWidget);
      // 副标题是中性的用途说明，不是错误原因
      expect(find.textContaining('用于登录、注册'), findsOneWidget);
      expect(find.text('未连通'), findsNothing);
      expect(find.text('去修复'), findsNothing);

      // 屏幕放不下 6 行，最后一项要滚一下才会被构建（ListView 懒构建）
      await t.drag(find.byType(ListView), const Offset(0, -320));
      await t.pump();
      expect(find.text('照片与视频'), findsOneWidget);
    });

    testWidgets('网络行的「允许」和系统权限行用的是同一个按钮样式', (t) async {
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          probeNet: () async => okResult(),
        ),
      ));
      await settle(t);

      // 可视区内 5 项都是「允许」（网络 + 通知/定位/相机/麦克风）。
      // 第 6 项「照片与视频」在屏幕外，ListView 懒构建不渲染它（见上一条测试）。
      expect(find.text('允许'), findsNWidgets(5));
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('单独点网络的「允许」→ 探测通 → 已连通 + 打勾', (t) async {
      var probes = 0;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false,
          probeNet: () async {
            probes++;
            return okResult(tcpMs: 36);
          },
        ),
      ));
      await settle(t);
      expect(probes, 0);

      await t.tap(find.text('允许').first);
      await settle(t);

      expect(probes, 1);
      expect(find.textContaining('已连通'), findsOneWidget);
      expect(find.textContaining('36 ms'), findsOneWidget);
      expect(find.text('去修复'), findsNothing);
      expect(find.text('未连通'), findsNothing);
    });

    testWidgets('单独点「允许」但端口连不上 → 标「未连通」+「去修复」', (t) async {
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false, // 新装用户：权限还没给，进页面不会自动探测
          probeNet: () async =>
              offlineResult('SocketException: Connection timed out'),
        ),
      ));
      await settle(t);
      // 初始不探测，所以此时还是「允许」
      expect(find.text('未连通'), findsNothing);

      await t.tap(find.text('允许').first);
      await settle(t);
      // v2.1.66：超时类失败先停在「请求中」等补探（可能系统弹窗刚被点完），
      // 补探仍失败才转红。
      await t.pump(const Duration(milliseconds: 1200));
      await settle(t);

      expect(find.text('未连通'), findsOneWidget);
      expect(find.text('去修复'), findsOneWidget);
      // 超时要翻译成人话，不能把英文异常直接铺给用户
      expect(find.textContaining('连接超时'), findsOneWidget);

      // 补探那一拍必须走完，否则收尾时留下 pending timer
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('权限本来就全开（升级来的）→ 自动探一次；不通过就停住并转红', (t) async {
      var exited = false;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () => exited = true,
          debugGrantPerms: true,
          probeNet: () async =>
              offlineResult('SocketException: Connection timed out'),
        ),
      ));
      await settle(t);
      await t.pump(const Duration(seconds: 2));

      expect(exited, isFalse, reason: '网络不通就不能放进首页');
      expect(find.text('未连通'), findsOneWidget);
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
      await t.tap(find.text('允许').first);
      await settle(t);

      expect(find.text('服务异常'), findsOneWidget);
      expect(find.textContaining('HTTP 500'), findsOneWidget);
      expect(find.textContaining('已连通'), findsNothing);
    });
  });

  group('一键开启 = 从网络开始逐项过一遍', () {
    testWidgets('点「一键开启全部权限」先探网络（队列第一位）', (t) async {
      var probes = 0;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () {},
          debugGrantPerms: false, // 新装用户：五项都要弹窗
          probeNet: () async {
            probes++;
            return okResult();
          },
        ),
      ));
      await settle(t);
      // 新装用户进页面不探测
      expect(probes, 0);

      await t.tap(find.text('一键开启全部权限'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));

      // 队列第一位就是网络：点下去立刻开始探测，早于任何一项系统权限
      expect(probes, 1,
          reason: '「一键开启」必须从网络开始，否则 iOS 的无线数据弹窗又要落到登录页之后');

      // 把后面的权限队列走完（测试环境没有权限平台通道，request 会被 catch）
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('一键开启时网络不通 → 不自动进首页，且如实标出未连通', (t) async {
      var exited = false;
      var probes = 0;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () => exited = true,
          debugGrantPerms: false,
          probeNet: () async {
            probes++;
            return offlineResult('SocketException: Network is unreachable');
          },
        ),
      ));
      await settle(t);

      await t.tap(find.text('一键开启全部权限'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(probes, 1, reason: '队列第一位必须是网络');

      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 2));

      expect(exited, isFalse, reason: '网络不通还放进去，用户只会在登录页撞「连接失败」');
      expect(find.text('未连通'), findsOneWidget);
    });

    test('源码护栏：探测必须写在权限循环之前（即队列第一位）', () {
      final src = File('lib/screens/startup/permission_onboard_screen.dart')
          .readAsStringSync();
      final body = src.substring(
        src.indexOf('Future<void> _requestAll()'),
        src.indexOf('Future<void> _openSettings()'),
      );
      final probeAt = body.indexOf('_probeWithRetry(');
      final loopAt = body.indexOf('for (final r in _rows)');
      expect(probeAt, greaterThan(-1),
          reason: '_requestAll 里必须探测网络（v2.1.66 起走 _probeWithRetry）');
      expect(loopAt, greaterThan(-1));
      expect(probeAt, lessThan(loopAt),
          reason: '网络探测必须在五项系统权限之前，否则顺序就不对');
    });
  });

  group('自动进入首页的闸门', () {
    testWidgets('权限全开 + 从没探过网络 → 自动探一次，通了才进（老用户升级无感）', (t) async {
      var exited = false;
      var probes = 0;
      await t.pumpWidget(MaterialApp(
        home: PermissionOnboardScreen(
          onDone: () => exited = true,
          debugGrantPerms: true,
          probeNet: () async {
            probes++;
            return okResult();
          },
        ),
      ));
      await settle(t);
      await t.pump(const Duration(milliseconds: 700));

      // 权限本来就全开的升级用户：不该手动点任何东西，也不该
      // 因为多了个「待检测」被永久卡住
      expect(probes, 1, reason: '放行前必须先确认网络；否则等于没修');
      expect(exited, isTrue);
    });

    testWidgets('权限全开 + 探测确认不通 → 绝不自动进（原核心回归）', (t) async {
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
      await t.pump(const Duration(seconds: 2));

      expect(exited, isFalse);
      expect(find.text('未连通'), findsOneWidget);
    });

    testWidgets('权限全开 + 服务器异常 → 放行（服务端问题，用户修不了）', (t) async {
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
      await t.pump(const Duration(seconds: 2));

      expect(find.text('服务异常'), findsOneWidget);
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
      await t.tap(find.text('允许').first);
      await settle(t);
      // 等补探那一拍走完，页面才落到「未连通」
      await t.pump(const Duration(milliseconds: 1200));
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
      await t.tap(find.text('允许').first);
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
