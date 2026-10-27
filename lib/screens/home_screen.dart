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
import '../widgets/section_header.dart';
import '../widgets/spot_card.dart';
import '../widgets/waterfall_post_card.dart';
import '../widgets/weather_card.dart';
import 'post_detail_screen.dart';
import 'search_screen.dart';
import 'signin_screen.dart';
import 'weather_screen.dart';
import 'spots_screen.dart';
import 'spot_detail_screen.dart';
import '../widgets/app_refresh.dart';
import '../services/app_settings.dart';

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
  int _feedPage = 1;
  bool _feedHasMore = true;
  bool _feedLoadingMore = false;
  final ScrollController _feedScroll = ScrollController();

  /// 当前定位的地名（首页左上角显示「禹州 / 许昌」这类短名）
  GeoPlace? _place;
  bool _locatingPlace = false;

  /// 自身定位坐标（用于「附近钓点」按距离由近到远排序）
  double? _myLat;
  double? _myLng;

  /// 钓友动态「实时更新」轮询：每 15 秒探测一次最新动态，
  /// 只有出现新帖子（id 集合变化）才刷新列表，无变化不重绘、不打扰。
  Timer? _feedTimer;
  static const Duration _feedInterval = Duration(seconds: 15);

  /// 天气 / 钓点的较慢全量刷新（数据变化慢，3 分钟一次足够）
  Timer? _slowTimer;
  static const Duration _slowInterval = Duration(minutes: 3);

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
    _feedScroll.addListener(_onFeedScroll);
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
    _feedScroll.dispose();
    _feedTimer?.cancel();
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    // 回到前台立刻补一次刷新（可能已经离开很久）
    if (_resumed && _lastUpdated != null) {
      _pollFeed();
      _silentRefresh();
    }
  }

  void _onFeedTick() => _loadFeed(silent: true);

  void _onSpotTick() => _loadSpots();

  /// 启动两类自动刷新：
  ///   - 15 秒：钓友动态「实时更新」探测（有新帖才刷新）
  ///   - 3 分钟：天气 / 钓点全量刷新
  void _startAutoRefresh() {
    _feedTimer?.cancel();
    _slowTimer?.cancel();
    _feedTimer = Timer.periodic(_feedInterval, (_) => _pollFeed());
    _slowTimer = Timer.periodic(_slowInterval, (_) => _silentRefresh());
  }

  /// 钓友动态实时轮询：拉最新一页动态，仅当「id 集合」有变化才刷新列表。
  /// 这样既能在别人发布后立即上屏（最多 15 秒延迟），又不会无谓重绘导致列表跳动。
  Future<void> _pollFeed() async {
    if (!mounted || !_resumed) return;
    try {
      final posts = await PostService.fetchFeed(limit: 20);
      if (!mounted) return;
      final newIds = posts.map((p) => p.id).toSet();
      final oldIds = _posts.map((p) => p.id).toSet();
      // 长度不同，或存在新 id（含置顶插入到非首位的情况）→ 视为有更新
      final changed =
          newIds.length != oldIds.length || !oldIds.containsAll(newIds);
      if (changed) {
        // 个性化推荐开启时首页是「推荐序」，不能直接塞时间序的那一页，
        // 否则新帖到达后整列顺序会突然跳一次 —— 重新按当前排序拉一页
        if (AppSettings.instance.personalized) {
          await _loadFeed(silent: true);
        } else {
          setState(() {
            _posts = posts;
            _lastUpdated = DateTime.now();
          });
        }
      }
    } catch (_) {
      // 轮询失败静默，下次再试
    }
  }

  /// 静默刷新：不弹错误提示，失败就等下一次
  Future<void> _silentRefresh() async {
    if (!mounted || !_resumed) return;
    await Future.wait([
      _pollFeed(),
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
  ///
  /// ★ 排队等待有上限，定位本身也有超时。
  ///   室内 / 地铁 / 电梯里 GPS 可能几十秒都锁不上，旧写法会一直卡在
  ///   这个 while 里，下拉刷新就永远转圈（用户反馈的现象）。
  Future<void> _loadPlace({bool refresh = false}) async {
    var waited = 0;
    // 最多等 6 秒（50 × 120ms），等不到就跳过这一次，别把调用方拖死
    while (_locatingPlace && waited < 50) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      waited++;
      if (!mounted) return;
    }
    if (_locatingPlace) return; // 另一个定位还在跑，这次直接放过
    _locatingPlace = true;
    if (mounted) setState(() {});
    try {
      final p = await GeoPlace.current(refresh: refresh)
          .timeout(const Duration(seconds: 6));
      if (mounted && p != null) setState(() => _place = p);
    } catch (_) {
      // 定位超时 / 失败：保留原来的地名，不影响其它内容刷新
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
      // allowStale：过期的缓存也先亮出来，别让首页天气卡空着等网络
      final cached = await WeatherService.readCachedCurrent(allowStale: true);
      if (cached != null && mounted && _weather == null) {
        setState(() {
          _weather = cached;
          _loadingWeather = false;
        });
      }
    }

    // ② 先用「上次的坐标」秒拉一次天气，不等 GPS
    //    GPS 冷启动在室内要好几秒，旧写法是「等定位 → 再请求天气」，
    //    用户看到的就是首页天气卡空着转圈。现在有上次坐标就立刻请求。
    await _firstFrame.future;
    if (!mounted) return;
    final lastPos = await _readLastPos();
    if (lastPos != null) {
      unawaited(_fetchWeather(lastPos[0], lastPos[1], silent: silent));
    }

    // ③ 定位（带超时，拿不到就用上次坐标/默认坐标）
    double lat = lastPos?[0] ?? 30.2741;
    double lng = lastPos?[1] ?? 120.1551; // 默认：杭州
    var moved = lastPos == null;
    try {
      final pos = await LocationService.determinePosition()
          .timeout(const Duration(seconds: 12));
      lat = pos.latitude;
      lng = pos.longitude;
      if (lastPos == null ||
          (lastPos[0] - lat).abs() > 0.02 ||
          (lastPos[1] - lng).abs() > 0.02) {
        moved = true;
      }
      await _saveLastPos(lat, lng);
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
      // 超时 / 其他异常：沿用上次坐标或默认坐标
    }

    // ④ 坐标没变就不重复请求（②已经拉过了），变了才补一次新坐标的天气
    if (moved) {
      await _fetchWeather(lat, lng, silent: silent);
    }
  }

  static const String _posKey = 'home_last_pos';

  Future<List<double>?> _readLastPos() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_posKey);
      if (raw == null || raw.isEmpty) return null;
      final p = raw.split(',');
      if (p.length != 2) return null;
      final la = double.tryParse(p[0]);
      final ln = double.tryParse(p[1]);
      if (la == null || ln == null) return null;
      return [la, ln];
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLastPos(double lat, double lng) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_posKey, '$lat,$lng');
    } catch (_) {}
  }

  /// 拉最新天气并上屏（失败时保持已有缓存，不把卡片清空）
  Future<void> _fetchWeather(double lat, double lng,
      {bool silent = false}) async {
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

  Future<void> _loadFeed({bool silent = false, bool loadMore = false}) async {
    if (loadMore) {
      if (_feedLoadingMore || !_feedHasMore || _posts.isEmpty) return;
      _feedLoadingMore = true;
      if (mounted) setState(() {});
    }
    try {
      final page = loadMore ? _feedPage + 1 : 1;
      final posts = await PostService.fetchFeed(
        limit: 20,
        offset: (page - 1) * 20,
        // 「设置 - 个性化推荐」关掉后按纯时间倒序，不再按热度推荐
        tab: AppSettings.instance.personalized ? 'recommend' : null,
      );
      if (!mounted) return;
      setState(() {
        if (loadMore) {
          // 去重（演示模式回落时后端会返回同一批，避免死循环追加）
          final seen = _posts.map((p) => p.id).toSet();
          final fresh = posts.where((p) => !seen.contains(p.id)).toList();
          _posts = [..._posts, ...fresh];
          _feedPage = page;
          if (fresh.length < posts.length || posts.length < 20) {
            _feedHasMore = false;
          }
        } else {
          _posts = posts;
          _feedPage = 1;
          _feedHasMore = posts.length >= 20;
          _lastUpdated = DateTime.now();
        }
      });
    } catch (e) {
      if (mounted && !silent && !loadMore) {
        CenterToast.show(context, '动态加载失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingPosts = false;
          if (loadMore) _feedLoadingMore = false;
        });
      }
    }
  }

  /// 首页信息流滚动接近底部时触发上滑加载更多
  void _onFeedScroll() {
    if (!_feedScroll.hasClients) return;
    final pos = _feedScroll.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 400) _loadFeedMore();
  }

  Future<void> _loadFeedMore() async {
    await _loadFeed(loadMore: true);
  }

  /// 上滑加载更多的底部指示器（与顶部刷新提示条彻底分离）
  Widget _feedFooter() {
    if (!_feedHasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text('没有更多了',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
        ),
      );
    }
    if (_feedLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return const SizedBox(height: 18);
  }

  /// 手动下拉刷新：顺带重新定位一次，保证「附近钓点」距离是新的
  ///
  /// ★ 定位不参与 await（v2.1.19）。
  ///   下拉刷新必须「点了就一定会停」，不能因为 GPS 在室内锁不上
  ///   就一直转圈 —— 这是用户反馈的「刷新图标一直转，刷新不出来」。
  ///   现在：定位放后台跑（自己会 setState），内容刷新有硬超时兜底。
  Future<void> _onRefresh() async {
    // 定位先发起，不等它。它回来后会自己刷新地名和钓点距离
    _loadPlace(refresh: true);
    // ★ 下拉只等「动态」一件事：用户下拉就是想看有没有新帖。
    //   旧写法把天气（要先拿 GPS）和钓点一起 await，室内定位锁不上时
    //   刷新要转好几秒 —— 现在是天气/钓点甩到后台，刷新几百毫秒就收。
    try {
      await _loadFeed().timeout(const Duration(seconds: 6));
    } catch (_) {
      // 失败也照常收起提示条，不能把用户晾在加载态里
    }
    unawaited(_loadWeather(silent: true));
    unawaited(_loadSpots());
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
                '渔报',
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
      body: AppRefresh(
        onRefresh: _onRefresh,
        child: ListView(
          controller: _feedScroll,
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
            //
            // ★ 版式与「钓友圈」共用同一张双列瀑布卡（WaterfallPostCard），
            //   用户要求首页这一块和参考图一模一样，所以不再用竖排大卡片。
            //   嵌在 ListView 里 → shrinkWrap + 禁掉自己的滚动，避免两个
            //   滚动容器抢手势（外层 AppRefresh 才是真正的滚动者）。
            _loadingPosts
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _posts.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('还没有动态，点击中间「+」发布第一条吧'),
                        ),
                      )
                    : Column(
                        children: [
                          WaterfallGrid(
                            posts: _posts,
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                            onTap: (p) => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => PostDetailScreen(post: p)),
                            ),
                          ),
                          _feedFooter(),
                        ],
                      ),
          ],
        ),
      ),
    );
  }
}
