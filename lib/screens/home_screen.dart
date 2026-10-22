import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../models/fishing_spot.dart';
import '../models/post.dart';
import '../services/geo_place.dart';
import '../services/location_service.dart';
import '../services/post_service.dart';
import '../services/refresh_bus.dart';
import '../services/session_provider.dart';
import '../services/spot_service.dart';
import '../services/weather_service.dart';
import '../utils/coord_transform.dart';
import '../widgets/center_toast.dart';
import '../widgets/grid_nav.dart';
import '../widgets/location_prompt.dart';
import '../widgets/msg_bell.dart';
import '../widgets/post_card.dart';
import '../widgets/section_header.dart';
import '../widgets/spot_card.dart';
import '../widgets/weather_card.dart';
import 'search_screen.dart';
import 'signin_screen.dart';
import 'weather_screen.dart';
import 'spots_screen.dart';
import 'spot_detail_screen.dart';

/// 首页：搜索框 + 宫格导航 + 天气/钓点 + 实时动态流
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  FishingWeather? _weather;
  List<FishingSpot> _spots = [];
  List<Post> _posts = [];
  bool _loadingWeather = true;
  bool _loadingPosts = true;

  /// 当前定位的地名（首页左上角显示「禹州 / 许昌」这类短名）
  GeoPlace? _place;
  bool _locatingPlace = false;

  /// 自身定位坐标（用于「附近钓点」按距离由近到远排序）
  double? _myLat;
  double? _myLng;

  /// 首页自动刷新定时器：每 3 分钟拉一次最新动态 / 天气 / 钓点
  Timer? _autoTimer;
  static const Duration _autoInterval = Duration(minutes: 3);

  /// App 是否在前台（后台时不自动刷新，省流量也避免无谓请求）
  bool _resumed = true;

  /// 上一次自动刷新的时间（展示在「钓友动态」标题右侧）
  DateTime? _lastUpdated;

  /// 首帧渲染完成的信号：定位/权限请求都要等它，
  /// 否则 iOS 会因为在首帧之前弹系统权限框而直接丢掉弹框
  /// （表现：iOS 从不提示定位权限、打开 App 不会自动定位）。
  final Completer<void> _firstFrame = Completer<void>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_firstFrame.isCompleted) _firstFrame.complete();
    });
    _loadPlace(); // 先用缓存秒显地名（断网也能看到上次城市）
    _loadWeather();
    _loadSpots();
    _loadFeed();
    // 发布成功（渔获 / 动态 / 钓点）后即时刷新首页，不用手动下拉
    RefreshBus.feedTick.addListener(_onFeedTick);
    RefreshBus.spotTick.addListener(_onSpotTick);
    _startAutoRefresh();
    // 首帧渲染完成后再真正定位一次，保证打开 App 就自动获取当前位置
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoLocate());
    // 登录后自动弹出每日签到窗口（后台可关；同一自然日只弹一次）
    _autoPopupSignin();
  }

  /// 每日签到自动弹窗：用本地日期做闸门，避免同一天重复打扰；
  /// 未登录或签到已关闭时静默跳过。
  Future<void> _autoPopupSignin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _todayKey();
      if (prefs.getString('signin_popup_date') == today) return;
      if (!mounted) return;
      final shown = await showSigninDialog(context);
      if (shown) await prefs.setString('signin_popup_date', today);
    } catch (_) {
      // 弹窗失败不影响首页
    }
  }

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RefreshBus.feedTick.removeListener(_onFeedTick);
    RefreshBus.spotTick.removeListener(_onSpotTick);
    _autoTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    // 回到前台立刻补一次刷新（可能已经离开很久）
    if (_resumed && _lastUpdated != null) {
      _silentRefresh();
    }
  }

  void _onFeedTick() => _loadFeed(silent: true);

  void _onSpotTick() => _loadSpots();

  /// 每 3 分钟自动刷新一次（后台时跳过）
  void _startAutoRefresh() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(_autoInterval, (_) => _silentRefresh());
  }

  /// 静默刷新：不弹错误提示，失败就等下一次
  Future<void> _silentRefresh() async {
    if (!mounted || !_resumed) return;
    await Future.wait([
      _loadFeed(silent: true),
      _loadWeather(silent: true),
      _loadSpots(),
    ]);
    if (mounted) setState(() => _lastUpdated = DateTime.now());
  }

  /// 打开 App 自动定位（每次进首页都刷新一次地名，不需要手动点）
  Future<void> _autoLocate() async {
    // 等界面稳一稳再请求权限，系统弹框才有宿主窗口
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    await _loadPlace(refresh: true);
  }

  /// 解析当前定位的中文地名（显示在软件名左侧）
  ///
  /// 并发保护：多个入口同时触发时排队执行，绝不并发调用
  /// requestPermission（并发会把 iOS 的系统权限框顶掉）。
  Future<void> _loadPlace({bool refresh = false}) async {
    while (_locatingPlace) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
    }
    _locatingPlace = true;
    if (mounted) setState(() {});
    try {
      final p = await GeoPlace.current(refresh: refresh);
      if (mounted && p != null) setState(() => _place = p);
    } finally {
      _locatingPlace = false;
      if (mounted) setState(() {});
    }
  }

  String? _lastSessionAvatar;
  bool _sessionWatchInited = false;

  /// 登录态变化（登录 / 编辑头像 / 退出）时刷新信息流，
  /// 保证自己动态上的头像、昵称立即更新，不需要杀掉 App 重开
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = Provider.of<SessionProvider>(context);
    if (!_sessionWatchInited) {
      // 首次只记录基准值，不触发刷新
      _sessionWatchInited = true;
      _lastSessionAvatar = session.avatarUrl;
      return;
    }
    final changed = session.avatarUrl != _lastSessionAvatar ||
        session.userId != _watchedUserId;
    if (changed) {
      _lastSessionAvatar = session.avatarUrl;
      _watchedUserId = session.userId;
      _loadFeed();
    }
  }

  String? _watchedUserId;

  // 获取定位后拉天气；定位失败则默认杭州坐标
  //
  // 策略：先读本地缓存「秒显」上次天气（断网/弱网也能看），
  // 再在后台拉最新值覆盖。这样每次打开 App 不会白屏转圈。
  Future<void> _loadWeather({bool silent = false}) async {
    // ① 缓存秒显（仅当当前还没有数据时，避免覆盖刚拉到的真实值）
    if (_weather == null) {
      final cached = await WeatherService.readCachedCurrent();
      if (cached != null && mounted && _weather == null) {
        setState(() {
          _weather = cached;
          _loadingWeather = false;
        });
      }
    }

    // ② 定位
    //    等首帧渲染完再请求权限：iOS 在首帧之前弹系统定位框会被丢掉
    await _firstFrame.future;
    if (!mounted) return;
    double lat = 30.2741, lng = 120.1551; // 默认：杭州
    try {
      final pos = await LocationService.determinePosition();
      lat = pos.latitude;
      lng = pos.longitude;
      // 记下自身坐标：「附近钓点」据此按距离由近到远排序
      if (mounted) {
        setState(() {
          _myLat = lat;
          _myLng = lng;
        });
        // 拿到定位后重排一次钓点（首次进入时钓点可能已先于定位返回）
        unawaited(_loadSpots());
      }
    } on LocationException catch (e) {
      // 首次打开 App：权限被拒时引导用户授权（其他原因静默用默认坐标）
      if (!silent && e.type == LocationErrorType.permissionDenied && mounted) {
        LocationPrompt.showError(context, e);
      }
    } catch (_) {
      // 忽略，使用默认坐标
    }

    // ③ 后台刷新最新天气
    try {
      final w = await WeatherService.fetch(lat, lng);
      if (mounted) {
        setState(() {
          _weather = w;
          _loadingWeather = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingWeather = false);
        // 已有缓存 / 自动刷新时不打扰用户；完全没有数据时才提示
        if (_weather == null && !silent) {
          CenterToast.show(context, '天气暂不可用，请检查网络');
        }
      }
    }
  }

  /// 附近钓点：按「距我距离」由近到远排序（未定位成功时保持后台排序）
  Future<void> _loadSpots() async {
    final spots = await SpotService.fetchSpots();
    if (mounted) setState(() => _spots = _sortedByDistance(spots));
  }

  List<FishingSpot> _sortedByDistance(List<FishingSpot> list) {
    final lat = _myLat;
    final lng = _myLng;
    if (lat == null || lng == null || list.length < 2) return list;
    final copy = List<FishingSpot>.from(list);
    copy.sort((a, b) => CoordTransform.distanceMeters(lat, lng, a.lat, a.lng)
        .compareTo(CoordTransform.distanceMeters(lat, lng, b.lat, b.lng)));
    return copy;
  }

  /// 某个钓点距我的距离（米）；未定位时返回 null
  double? _distanceOf(FishingSpot s) {
    final lat = _myLat;
    final lng = _myLng;
    if (lat == null || lng == null) return null;
    return CoordTransform.distanceMeters(lat, lng, s.lat, s.lng);
  }

  Future<void> _loadFeed({bool silent = false}) async {
    try {
      final posts = await PostService.fetchFeed(limit: 20);
      if (mounted) {
        setState(() {
          _posts = posts;
          _lastUpdated = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        CenterToast.show(context, '动态加载失败：$e');
      }
    } finally {
      if (mounted) setState(() => _loadingPosts = false);
    }
  }

  /// 手动下拉刷新：顺带重新定位一次，保证「附近钓点」距离是新的
  Future<void> _onRefresh() async {
    await Future.wait([
      _loadFeed(),
      _loadWeather(),
      _loadPlace(refresh: true),
    ]);
    await _loadSpots();
    if (mounted) setState(() => _lastUpdated = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 顶部高度收紧（默认 56 → 46），软件名居中，定位地名浮在左侧
        toolbarHeight: 46,
        centerTitle: true,
        titleSpacing: 12,
        title: SizedBox(
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // —— 软件名：居中 ——
              const Text(
                '垂钓圈',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: Colors.white),
              ),
              // —— 定位地名：靠左浮层（点击可刷新定位）——
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () async {
                    GeoPlace.clearCache();
                    await _loadPlace(refresh: true);
                    await _loadWeather();
                    if (mounted) {
                      CenterToast.show(context, '已重新定位');
                    }
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_locatingPlace && _place == null)
                          const SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.6, color: Colors.white),
                          )
                        else
                          const Icon(Icons.location_on,
                              size: 13, color: Colors.white),
                        const SizedBox(width: 3),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 76),
                          child: Text(
                            _place == null || _place!.label.isEmpty
                                ? '定位中'
                                : _place!.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down,
                            size: 14, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
              ),
              // —— 消息铃铛：靠右浮层（带未读红点）——
              const Align(
                alignment: Alignment.centerRight,
                child: MsgBellButton(),
              ),
            ],
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        // 顶部搜索框（高度一并收紧）
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              ),
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusPill),
                    border: Border.all(color: AppTheme.border),
                    boxShadow: AppTheme.lightShadow,
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 14),
                      Icon(Icons.search,
                          color: AppTheme.textSecondary, size: 20),
                      SizedBox(width: 8),
                      Text('搜索钓点 / 钓友 / 渔获',
                          style: TextStyle(
                              fontSize: 14, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          children: [
            const GridNav(),
            // 天气（点击进入 7 天预报独立页）
            _loadingWeather
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _weather == null
                    ? const SizedBox()
                    :                           Column(
                        children: [
                          SectionHeader(
                            title: (_place == null || _place!.label.isEmpty)
                                ? '实时天气'
                                : '${_place!.label} · 实时天气',
                            actionLabel: '7天预报',
                            onAction: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const WeatherScreen()),
                            ),
                          ),
                          InkWell(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const WeatherScreen()),
                            ),
                            borderRadius: BorderRadius.circular(14),
                            child: WeatherCard(
                              weather: _weather!,
                              placeLabel: _place?.label,
                            ),
                          ),
                        ],
                      ),
            // 钓点横向列表（标题 + 进入钓点页）
            SectionHeader(
              title: '附近钓点',
              // 由近到远是小字说明，不跟标题一样大（原来拼在 title 里，字号一样大很突兀）
              subtitle: _myLat == null ? null : '由近到远',
              actionLabel: '更多',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SpotsScreen()),
              ),
            ),
            SizedBox(
              // 卡片自身 96 高（见 SpotCard.cardHeight），这里只留一点呼吸空间，
              // 高度写死可以彻底避免「加了标签把卡片撑变形 / 被裁掉」
              height: SpotCard.cardHeight + 6,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _spots
                    .map((s) => SpotCard(
                          spot: s,
                          distanceMeters: _distanceOf(s),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => SpotDetailScreen(spot: s)),
                          ),
                        ))
                    .toList(),
              ),
            ),
            SectionHeader(
              title: '钓友动态',
              subtitle: '实时更新',
            ),
            // 动态信息流（实时刷新）
            _loadingPosts
                ? const Center(child: CircularProgressIndicator())
                : _posts.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('还没有动态，点击中间「+」发布第一条吧'),
                        ),
                      )
                    : Column(
                        children: _posts
                            .map((p) => PostCard(post: p))
                            .toList(),
                      ),
          ],
        ),
      ),
    );
  }
}
