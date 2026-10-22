import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'models/app_bootstrap.dart';
import 'screens/fish_guide_screen.dart';
import 'screens/member_center_screen.dart';
import 'screens/message_center_screen.dart';
import 'screens/nearby_anglers_screen.dart';
import 'screens/signin_screen.dart';
import 'screens/startup/preview_pager_screen.dart';
import 'screens/startup/splash_screen.dart';
import 'screens/startup/startup_ad_screen.dart';
import 'screens/wallet_screen.dart';
import 'services/app_service.dart';
import 'services/message_poller.dart';
import 'services/session_provider.dart';
import 'screens/home_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/spots_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/publish_hub_screen.dart';
import 'widgets/update_dialog.dart';

/// 全局导航 key：用于「新消息」顶部弹条在任意页面悬浮展示
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // Flutter 绑定初始化（必须在 async main 开头调用）
  WidgetsFlutterBinding.ensureInitialized();

  // 恢复本地登录态：只要用户没点「退出登录」，重开 App 保持在线
  final session = SessionProvider();
  await session.restore();

  // 全局消息轮询：随登录态自动启停，App 生命周期内持续轮询未读
  MessagePoller.instance.attach(session);
  MessagePoller.instance.onNewMessage = (delta, _) {
    _showNewMessageBanner(delta);
  };

  runApp(
    // 用 Provider 在全局共享登录态
    ChangeNotifierProvider(
      create: (_) => session,
      child: const MyApp(),
    ),
  );
}

/// 新消息顶部弹条：未读增加时悬浮提示，点击进消息中心（营造「实时收到」的体感）
void _showNewMessageBanner(int delta) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  final overlay = Overlay.of(ctx);
  if (overlay == null) return;
  var removed = false;
  late OverlayEntry entry;
  void dismiss() {
    if (!removed) {
      removed = true;
      entry.remove();
    }
  }

  entry = OverlayEntry(
    builder: (_) => Positioned(
      top: MediaQuery.of(ctx).padding.top + 10,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () {
            dismiss();
            Navigator.of(ctx).pushNamed('/message-center');
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.primaryDark],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '收到 $delta 条新消息（评论 / 点赞等）',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: Colors.white70, size: 16),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Timer(const Duration(seconds: 3), dismiss);
}

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
      MessagePoller.instance.refreshNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '垂钓圈',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // 首帧还没画出来时，系统窗口底色用品牌绿，避免冷启动闪一下白屏
      color: AppTheme.primary,
      home: const StartupGate(),
      routes: {
        '/message-center': (_) => const MessageCenterScreen(),
        '/signin': (_) => const SigninScreen(),
        '/wallet': (_) => const WalletScreen(),
        '/member-center': (_) => const MemberCenterScreen(),
        '/member-orders': (_) => const MemberOrdersScreen(),
        '/fish-guide': (_) => const FishGuideScreen(),
        '/nearby-anglers': (_) => const NearbyAnglersScreen(),
      },
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 启动配置最多等这么久：超时就用「无启动内容」直接进首页。
  /// 服务器慢 / 断网时不能让用户一直干等在启动页（表现为「白屏过一会才进」）。
  static const _bootTimeout = Duration(milliseconds: 2500);

  Future<void> _load() async {
    AppBootstrap boot;
    try {
      boot = await AppService.bootstrap().timeout(_bootTimeout);
    } catch (_) {
      // 超时或后端不可用：不展示启动广告/预览页，直接进首页
      boot = const AppBootstrap();
    }
    if (!mounted) return;
    setState(() {
      _boot = boot;
      _loading = false;
    });
    // 启动后检查热更新（有新版本才弹窗；强制更新不可跳过）
    UpdateDialog.checkAndShow(context);
  }

  /// 清空启动内容 → 进入主框架
  void _enterApp() {
    if (!mounted) return;
    setState(() => _boot = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SplashScreen();
    final boot = _boot;
    if (boot == null || !boot.hasStartupContent) return const MainShell();
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

  // 底部单个 tab（图标 + 文字）
  // 选中态只变图标/文字颜色，不加背景块 —— 保持导航栏干净
  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    final selected = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => _onTabTapped(index),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? activeIcon : icon,
                size: 22,
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? AppTheme.primary : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
