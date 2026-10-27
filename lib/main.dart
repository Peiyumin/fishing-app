import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'models/app_bootstrap.dart';
import 'models/message.dart';
import 'screens/chat_screen.dart';
import 'screens/fish_guide_screen.dart';
import 'screens/pond_screen.dart';
import 'screens/member_center_screen.dart';
import 'screens/message_center_screen.dart';
import 'screens/nearby_anglers_screen.dart';
import 'screens/notify_settings_screen.dart';
import 'screens/permission_check_screen.dart';
import 'screens/post_detail_screen.dart';
import 'screens/signin_screen.dart';
import 'screens/startup/preview_pager_screen.dart';
import 'screens/startup/splash_screen.dart';
import 'screens/startup/startup_ad_screen.dart';
import 'screens/wallet_screen.dart';
import 'services/app_service.dart';
import 'services/app_shortcuts.dart';
import 'services/app_settings.dart';
import 'services/message_poller.dart';
import 'services/notification_service.dart';
import 'services/post_service.dart';
import 'services/session_provider.dart';
import 'screens/home_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/spots_screen.dart';
import 'screens/spot_map_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/publish_hub_screen.dart';
import 'screens/publish_catch_screen.dart';
import 'widgets/update_dialog.dart';

/// 全局导航 key：用于「新消息」顶部弹条在任意页面悬浮展示
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 老安卓（Android 5.x / API 22 及以下）系统证书库缺失三张现代根证书：
///   - ISRG Root X1      （Let's Encrypt / open-meteo 天气）
///   - DigiCert Global Root G2（星图地球 / bigdatacloud 定位反查）
///   - GTS Root R4       （Google Trust Services / openfreemap 在线河网）
/// 缺它们时 Dart HTTP 与现代 HTTPS 全部报 CERTIFICATE_VERIFY_FAILED，
/// 表现就是「安卓天气报错、定位反查失败」。
///
/// 注意：Android 5.x 不支持 network_security_config 注入自定义 CA，
/// 只能在 Dart 层把根证书塞进默认 SecurityContext，绕开系统证书库。
/// 这一步只管 Dart HTTP（天气/定位反查等）；原生 MapLibre SDK 拉瓦片的
/// HTTPS 不归这里管，那个走后端 /tile-proxy 代理（见 spot_map_gl）。
Future<void> _injectRootCerts() async {
  const certs = [
    'assets/certs/isrg_root_x1.pem',
    'assets/certs/digicert_global_root_g2.pem',
    'assets/certs/gts_root_r4.pem',
  ];
  try {
    final ctx = SecurityContext.defaultContext;
    for (final path in certs) {
      final data = await rootBundle.load(path);
      ctx.setTrustedCertificatesBytes(data.buffer.asUint8List());
    }
    debugPrint('[certs] 已注入 ${certs.length} 张根证书');
  } catch (e) {
    // 注入失败不应阻断启动：现代系统本来就有这些根证书
    debugPrint('[certs] 注入根证书失败（可忽略）：$e');
  }
}

/// 把启动页底图解进图片缓存，让 Dart 首帧就能直接画出来
///
/// 只解码这一张（约 500KB JPEG），不做任何网络请求，最多等 800ms；
/// 失败也不阻塞启动 —— 大不了退回「黑底 + 图片稍后淡入」。
Future<void> _precacheSplash() async {
  final completer = Completer<void>();
  final stream = const AssetImage('assets/startup/splash_brand.jpg')
      .resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (_, __) {
      if (!completer.isCompleted) completer.complete();
    },
    onError: (_, __) {
      if (!completer.isCompleted) completer.complete();
    },
  );
  stream.addListener(listener);
  await completer.future.timeout(
    const Duration(milliseconds: 800),
    onTimeout: () {},
  );
  stream.removeListener(listener);
}

void main() {
  // Flutter 绑定初始化（必须在 async main 开头调用）
  WidgetsFlutterBinding.ensureInitialized();

  // 图片解码缓存限制：默认 100MB / 1000 张，地图瓦片一屏几十张很容易顶满，
  // 在 2GB 内存的老机型上会被系统直接杀掉（表现为「打开地图闪退」）。
  // 瓦片已有磁盘缓存，重解码成本很低，所以这里压到 64MB / 500 张。
  PaintingBinding.instance.imageCache.maximumSizeBytes = 64 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 500;

  // ★★ v2.1.44：runApp 之前**不再**串行 await 任何初始化。
  //
  //   以前这里是：注入根证书 → 恢复登录态 → 读偏好 → 初始化推送 →
  //   预解码启动图（最多 800ms），一路 await 完才 runApp。这期间屏幕上是
  //   系统启动图（旧版还是纯黑），于是冷启动就是「黑屏好几秒才看到启动页」。
  //   现在先把界面画出来，这些初始化全部挪到启动页背后并行跑
  //   （_StartupGateState._prepare），做完才放行进主界面。
  runApp(
    // 用 Provider 在全局共享登录态
    ChangeNotifierProvider(
      create: (_) => SessionProvider(),
      child: const MyApp(),
    ),
  );
}

/// 点通知后跳转到对应页面
///
/// 映射关系：
///   私信        → 与发送者的聊天页
///   官方公告    → 消息中心（公告列表）
///   评论/点赞   → 对应动态详情（帖子已删除则回消息中心）
///   其它        → 消息中心
Future<void> openFromNotification(Map<String, dynamic> p) async {
  final kind = (p['kind'] ?? '').toString();
  final type = (p['type'] ?? '').toString();
  final peerId = (p['peerId'] ?? '').toString();
  final refId = (p['refId'] ?? '').toString();

  // Navigator 可能还没就绪，最多等 2 秒
  NavigatorState? nav = navigatorKey.currentState;
  for (var i = 0; i < 10 && nav == null; i++) {
    await Future.delayed(const Duration(milliseconds: 200));
    nav = navigatorKey.currentState;
  }
  if (nav == null) return;

  if (kind == 'chat' && peerId.isNotEmpty) {
    nav.push(MaterialPageRoute(
      builder: (_) => ChatScreen(peerId: peerId, nickname: (p['fromName'] ?? '钓友').toString()),
    ));
    return;
  }
  if (type == 'system') {
    nav.pushNamed('/message-center');
    return;
  }
  if (refId.isNotEmpty) {
    final post = await PostService.fetchById(refId);
    if (post != null) {
      nav.push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)));
      return;
    }
  }
  nav.pushNamed('/message-center');
}

/// 长按图标快捷项的跳转（我的图鉴 / 赛博鱼缸 / 记渔获）
///
/// 和通知跳转一样，冷启动时 Navigator 可能还没挂稳，最多等 2 秒。
Future<void> _openShortcut(String type) async {
  NavigatorState? nav = navigatorKey.currentState;
  for (var i = 0; i < 10 && nav == null; i++) {
    await Future.delayed(const Duration(milliseconds: 200));
    nav = navigatorKey.currentState;
  }
  if (nav == null) return;
  switch (type) {
    case AppShortcuts.guide:
      nav.pushNamed('/fish-guide');
      break;
    case AppShortcuts.tank:
      nav.pushNamed('/fish-tank');
      break;
    case AppShortcuts.catchFish:
      nav.push(MaterialPageRoute(builder: (_) => const PublishCatchScreen()));
      break;
  }
}

/// 新消息顶部横幅：带具体内容的卡片，点击直达对应页面
///
/// 多条消息时合并成一张（标题显示条数，正文给最新一条），
/// 不做「一条一个横幅」的堆叠 —— 一次轮询可能带回十几条，会糊满屏幕。
void _showFeedBanner(List<FeedItem> items, MsgSummary summary) {
  if (items.isEmpty) return;
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  final overlay = Overlay.maybeOf(ctx);
  if (overlay == null) return;

  var removed = false;
  late OverlayEntry entry;
  void dismiss() {
    if (!removed) {
      removed = true;
      entry.remove();
    }
  }

  final first = items.first;
  final single = items.length == 1;
  final title = single ? first.pushTitle : '${items.length} 条新消息';
  final body = single
      ? first.pushBody
      : items
          .take(2)
          .map((e) => e.pushTitle)
          .where((s) => s.isNotEmpty)
          .join(' · ');

  final icon = first.isChat
      ? Icons.mail_outline
      : first.isSystem
          ? Icons.campaign_outlined
          : first.type == 'like'
              ? Icons.favorite_border
              : Icons.chat_bubble_outline;

  entry = OverlayEntry(
    builder: (_) => Positioned(
      top: MediaQuery.of(ctx).padding.top + 8,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () {
            dismiss();
            openFromNotification(first.toPayload());
          },
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < 0) dismiss();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x26000000), blurRadius: 16, offset: Offset(0, 6))
              ],
            ),
            child: Row(children: [
              // 有头像用头像（一眼知道是谁），没有就用类型图标
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: first.fromAvatar.isNotEmpty
                      ? Image.network(first.fromAvatar,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _bannerIcon(icon))
                      : _bannerIcon(icon),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary)),
                      ),
                      if (summary.total > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.danger,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${summary.total}',
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ]),
                    const SizedBox(height: 2),
                    Text(body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppTheme.textSecondary),
            ]),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Timer(const Duration(seconds: 4), dismiss);
}

Widget _bannerIcon(IconData icon) => Container(
      color: AppTheme.primaryLight,
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: AppTheme.primary),
    );


class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // 监听 App 前后台切换：回到前台立即查一次未读
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 切回前台：立刻补拉一次，把后台期间错过的消息一次性提醒
      // （iOS 挂起后 Dart 定时器停摆，只能靠这个时机补齐）
      MessagePoller.instance.refreshNow(fromBackground: true);
      NotificationService.instance.checkPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听本机偏好：v2.1.44 起 AppSettings 在 runApp 之后才 load，
    // 读完会 notifyListeners → 这里重建一次 MaterialApp，
    // builder 里的 textScaler 于是拿到正确的字号档位。
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) => MaterialApp(
      navigatorKey: navigatorKey,
      title: '渔报',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // 首帧还没画出来时，系统窗口底色用品牌绿，避免冷启动闪一下白屏
      color: AppTheme.primary,
      // 字体大小：只缩放文字，不改布局尺寸（MaterialApp 级生效）
      builder: (context, child) {
        final scale = AppSettings.instance.fontScale;
        if (scale == 1.0 || child == null) return child ?? const SizedBox.shrink();
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child,
        );
      },
      home: const StartupGate(),
      routes: {
        '/message-center': (_) => const MessageCenterScreen(),
        '/signin': (_) => const SigninScreen(),
        '/wallet': (_) => const WalletScreen(),
        '/member-center': (_) => const MemberCenterScreen(),
        '/member-orders': (_) => const MemberOrdersScreen(),
        '/fish-guide': (_) => const FishGuideScreen(),
        '/fish-tank': (_) => const PondScreen(),
        '/nearby-anglers': (_) => const NearbyAnglersScreen(),
        '/spot-map': (_) => const SpotMapScreen(),
        '/notify-settings': (_) => const NotifySettingsScreen(),
        '/permission-check': (_) => const PermissionCheckScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
      ),
    );
  }
}

/// 启动门：拉取后台配置的启动内容
///   启动页广告（倒计时跳过）→ 启动预览页（滑动引导）→ 首页
/// 后台没配任何内容时直接进首页，不影响使用
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _loading = true;
  AppBootstrap? _boot;

  /// 启动封面自己的动画是否播完了。
  /// ★ 不能只看 `_loading`：启动接口 200ms 就回来的话，进度条还没动
  ///   就被切走了。现在由 [SplashScreen] 负责「至少亮 1.6 秒 + 把进度
  ///   涨到 100%」，播完调 [onFinished]，这里才真正放行。
  bool _splashDone = false;

  /// 启动配置最多等这么久：超时就用「无启动内容」直接进首页。
  /// 服务器慢 / 断网时不能让用户一直干等在启动页（表现为「白屏过一会才进」）。
  static const _bootTimeout = Duration(milliseconds: 2500);

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  /// 启动前要做的全部准备（v2.1.44：并行 + 不阻塞 runApp）
  ///
  /// 顺序上有两条硬约束：
  ///   ① 根证书必须最先注入 —— 后面每一次 HTTPS（启动配置 / 天气 / 定位）
  ///      在老安卓上都要靠它，晚一步就是一片 CERTIFICATE_VERIFY_FAILED；
  ///   ② 登录态恢复完才能挂消息轮询，否则轮询用的是空 token。
  /// 其余（本机偏好 / 推送 / 启动图预解码 / 启动配置接口）互不相干，全部并行。
  Future<void> _prepare() async {
    final session = context.read<SessionProvider>();

    // ① 根证书（本地资源，几十毫秒）
    await _injectRootCerts();

    // ② 启动配置接口：先发出去，和下面几件事并行跑
    final bootF = AppService.bootstrap()
        .timeout(_bootTimeout)
        .catchError((_) => const AppBootstrap());

    await Future.wait<void>([
      // 本机偏好：字体大小 / 个性化推荐 / 鱼获隐私默认值。
      // 现在它在 runApp 之后才读，所以 MyApp 用 AnimatedBuilder 监听
      // AppSettings，读完触发一次重建，字号档位照样立即生效。
      AppSettings.instance.load().catchError((_) {}),
      // 恢复登录态（SessionProvider 是 ChangeNotifier，恢复后自动通知）
      session.restore().catchError((_) {}),
      // 系统通知（私信 / 评论 / 点赞 / 官方公告）
      _initPush(),
      // 预解码启动页底图：Dart 启动页第一帧就能直接画出来，不会先黑一下
      _precacheSplash(),
      // 长按图标快捷入口：注册 channel + 取冷启动待处理项
      AppShortcuts.init(),
    ]);

    // ③ 长按快捷入口：跳转逻辑交给 _openShortcut（等 navigator 就绪）
    AppShortcuts.onAction = _openShortcut;

    // ④ 登录态就绪后才挂全局消息轮询
    MessagePoller.instance.attach(session);
    MessagePoller.instance.onNewItems = (items, summary) {
      _showFeedBanner(items, summary);
    };

    final boot = await bootF;
    if (!mounted) return;
    setState(() {
      _boot = boot;
      _loading = false;
    });

    // 启动后检查热更新（有新版本才弹窗；强制更新不可跳过）
    UpdateDialog.checkAndShow(context);
  }

  /// 推送初始化 + 挂点击回调（失败不影响启动）
  Future<void> _initPush() async {
    try {
      await NotificationService.instance.init();
      NotificationService.instance.onTap = openFromNotification;
    } catch (_) {
      // 用户拒绝通知权限 / 无网络时拿不到 token，正常现象
    }
  }

  /// 冷启动是被「点击通知」拉起来的：等主界面挂稳再跳，只处理一次
  bool _pendingNavHandled = false;

  void _handlePendingNav() {
    if (_pendingNavHandled) return;
    _pendingNavHandled = true;
    // 长按图标的快捷项（冷启动时攒下的）也在这一刻补跳
    AppShortcuts.flushPending();
    final p = NotificationService.instance.pendingPayload;
    if (p == null) return;
    NotificationService.instance.pendingPayload = null;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) openFromNotification(p);
    });
  }

  /// 清空启动内容 → 进入主框架
  void _enterApp() {
    if (!mounted) return;
    setState(() => _boot = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashDone) {
      return SplashScreen(
        ready: !_loading,
        onFinished: () {
          if (!mounted || _splashDone) return;
          setState(() => _splashDone = true);
        },
      );
    }
    final boot = _boot;
    if (boot == null || !boot.hasStartupContent) {
      // 主界面挂完再处理「点通知冷启动」的跳转
      WidgetsBinding.instance.addPostFrameCallback((_) => _handlePendingNav());
      return const MainShell();
    }
    if (boot.ads.isNotEmpty) {
      return StartupAdScreen(
        ads: boot.ads,
        onFinished: () {
          // 广告看完还有预览页 → 继续展示预览页
          if (boot.previews.isNotEmpty) {
            setState(() => _boot = AppBootstrap(previews: boot.previews));
          } else {
            _enterApp();
          }
        },
      );
    }
    return PreviewPagerScreen(previews: boot.previews, onFinished: _enterApp);
  }
}

/// 主框架：底部导航（中间是凸起的「发布」按钮）
/// 说明：天气入口在首页「实时天气」卡片，点击进入天气独立页
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // 四个常规页面（发布页用悬浮按钮单独打开，不占底部 item）
  // v2.1.10：删掉「地图」Tab —— 地图已嵌入钓点页的「野钓钓点」Tab 内
  int _currentIndex = 0;
  final List<Widget> _pages = const [
    HomeScreen(),
    DiscoverScreen(),
    SpotsScreen(),
    ProfileScreen(),
  ];

  void _onTabTapped(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack 保留各页面状态，切换不重新加载
      body: IndexedStack(index: _currentIndex, children: _pages),
      // 中间凹口容纳发布按钮
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        tooltip: '发布',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PublishHubScreen()),
        ),
        child: const Icon(Icons.add, size: 30),
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.home_outlined, Icons.home, '首页'),
              _navItem(1, Icons.explore_outlined, Icons.explore, '发现'),
              const SizedBox(width: 56), // 中间留白给发布按钮
              _navItem(2, Icons.place_outlined, Icons.place, '钓点'),
              _navItem(3, Icons.person_outline, Icons.person, '我的'),
            ],
          ),
        ),
      ),
    );
  }

  // 底部单个 tab（图标 + 文字 + 选中指示条）
  //
  // 选中态：近黑图标 + 近黑加粗文字 + 下方一条短荧光黄绿横条。
  // 不用「整块浅色底」，那样五个 tab 会变成五个色块，反而喧宾夺主。
  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    final selected = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => _onTabTapped(index),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? activeIcon : icon,
                size: 22,
                color: selected ? AppTheme.primary : AppTheme.textTertiary,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppTheme.primary : AppTheme.textTertiary,
                ),
              ),
              const SizedBox(height: 3),
              // 选中指示条：3×14 的圆角黄绿短横
              Container(
                width: selected ? 14 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
