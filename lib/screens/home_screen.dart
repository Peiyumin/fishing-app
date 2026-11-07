import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../models/fishing_spot.dart';
import '../models/home_layout.dart';
import '../models/home_mode.dart';
import '../models/post.dart';
import '../services/geo_place.dart';
import '../services/home_service.dart';
import '../services/location_service.dart';
import '../services/post_service.dart';
import '../services/refresh_bus.dart';
import '../services/session_provider.dart';
import '../services/tide_service.dart';
import '../services/spot_service.dart';
import '../services/weather_service.dart';
import '../utils/coord_transform.dart';
import '../utils/spot_sort.dart';
import '../widgets/center_toast.dart';
import '../widgets/login_gate.dart';
import '../widgets/grid_nav.dart';
import '../widgets/home_ad_banner.dart';
import '../widgets/home_weather_hero.dart';
import '../widgets/location_prompt.dart';
import '../widgets/home_top_bar.dart';
import '../widgets/section_header.dart';
import '../widgets/spot_card.dart';
import '../widgets/waterfall_post_card.dart';
import 'post_detail_screen.dart';
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

  /// 顶部钓法分类（v2.1.86）：台钓 / 路亚 / 钓场 / 海钓
  ///
  /// 它不只改标签 —— 换钓法会用**同一小时**的天气按新权重重算指数，
  /// 并且把天气通栏的第三格换成对应数据（海钓看潮汐，其余看水氧）。
  HomeMode _mode = HomeMode.taiDiao;

  /// 海钓用的潮汐估算（内陆/没定位时是 null，第三格显示「--」）
  TideInfo? _tide;

  /// 钓法偏好的本地键：用户上次选哪一类，下次打开还是哪一类
  static const String _modeKey = 'home_mode_v1';

  /// 首页装修（分类导航 + 广告位 + 一行几个），后台 `/home/layout` 下发
  ///
  /// v46：先取内存/兜底，首帧就能画出宫格；随后异步换成后台真实配置。
  HomeLayout _layout = HomeService.current;
  List<FishingSpot> _spots = [];
  List<Post> _posts = [];
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
    // ★ v2.1.74：先用「启动时预热好的内存缓存」把天气卡填上。
    //
    //   以前这里是 _loadingWeather = true，首帧先画转圈，等 SharedPreferences
    //   异步读完再画卡片 —— 视觉上就是「打开 App 天气卡空一下再蹦出来」。
    //   启动页期间已经跑过 WeatherService.warmUp()，这里同步取值即可，
    //   第一帧就是真实天气；随后 _loadWeather 只做「静默更新」。
    _weather = WeatherService.memoryCurrent;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_firstFrame.isCompleted) _firstFrame.complete();
    });
    _loadPlace(); // 先用缓存秒显地名（断网也能看到上次城市）
    _loadLayout(); // 后台配的宫格/广告：先用缓存，再静默换成最新的
    _loadMode(); // 上次选的钓法（台钓/路亚/钓场/海钓）
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
        setState(() => _weather = cached);
      }
    }

    // ② 先用「上次的坐标」秒拉一次天气，不等 GPS
    //    GPS 冷启动在室内要好几秒，旧写法是「等定位 → 再请求天气」，
    //    用户看到的就是首页天气卡空着转圈。现在有上次坐标就立刻请求。
    await _firstFrame.future;
    if (!mounted) return;
    final lastPos = await _readLastPos();
    if (lastPos != null) {
      // 海钓的潮汐要有坐标才有意义。GPS 还没回来（室内/刚开机）时先用
      // 上次的位置兜底，别让用户点了「海钓」看到一格「--」。
      if (mounted && _myLat == null) {
        setState(() {
          _myLat = lastPos[0];
          _myLng = lastPos[1];
          _tide = _computeTide();
        });
      }
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
          // 海钓的潮汐要用坐标，拿到定位就补算一次
          _tide = _computeTide();
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

  // ── 钓法分类：台钓 / 路亚 / 钓场 / 海钓（v2.1.86）──────────────

  /// 读上次选的钓法（启动时调用一次；读不到就是台钓）
  Future<void> _loadMode() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final m = HomeMode.fromKey(sp.getString(_modeKey));
      if (!mounted || m == _mode) return;
      setState(() {
        _mode = m;
        _applyModeToWeather();
      });
    } catch (_) {
      // 偏好读失败不影响首页
    }
  }

  /// 切钓法：改标签 → 按新权重重算指数 → 海钓再补潮汐 → 记住选择
  void _setMode(HomeMode m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _applyModeToWeather();
    });
    // 存偏好失败不该影响这次切换：界面已经改完了，最多下次打开回到台钓
    SharedPreferences.getInstance()
        .then((sp) => sp.setString(_modeKey, m.key))
        .catchError((_) => false);
  }

  /// 用当前钓法权重，把「现在这一小时」的指数重算一遍
  ///
  /// ★ 为什么必须重算：海钓的权重里潮汐占 31%、路亚看掠食性活跃时段、
  ///   台钓看水温适温 —— 同一个小时，四套秤砣称出来不是一个数。
  ///   只改标签不换数，用户点「海钓」看到和「台钓」一模一样的 78 分，
  ///   只会判定「这个切换是假的」。
  ///
  /// ★ 只改本页的 `_weather`，**不动** `WeatherService.memoryCurrent`：
  ///   内存里那份是全站基线（天气页/钓点页都按台钓口径读），
  ///   在这里就地改掉会让别的页面跟着抖。
  void _applyModeToWeather() {
    final b = WeatherService.memoryBundle;
    _tide = _computeTide();
    if (b == null) return; // 只有本地快照时保持原样，等拉到新数据再对齐
    _weather = FishingWeather.fromIndex(
      b,
      b.indexOfCurrentHour(DateTime.now()),
      mode: _mode.fishingMode,
    );
  }

  /// 潮汐估算（只有海钓要看；算法是纯函数，没坐标就返回 null）
  TideInfo? _computeTide() {
    final lat = _myLat;
    final lng = _myLng;
    if (lat == null || lng == null) return null;
    return TideService.at(lat, lng, DateTime.now());
  }

  /// 拉最新天气并上屏（失败时保持已有缓存，不把卡片清空）
  Future<void> _fetchWeather(double lat, double lng,
      {bool silent = false}) async {
    try {
      final w = await WeatherService.fetch(lat, lng);
      if (mounted) {
        setState(() {
          _weather = w;
          // 拉回来的是「台钓口径」的快照；当前选的是别的钓法就按那套权重重算，
          // 否则用户切到海钓、后台刷新一次又被打回 78 分
          _applyModeToWeather();
        });
      }
    } catch (e) {
      if (mounted) {
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

  List<FishingSpot> _sortedByDistance(List<FishingSpot> list) =>
      // v2.1.69：与「钓点」页共用同一个排序口径（无坐标沉底、同距按名称定序）
      sortSpotsByDistance(list, _myLat, _myLng);

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

  /// 拉首页装修（分类导航 + 广告位 + 一行几个）
  ///
  /// 两步走：
  ///   1. 先读本地缓存 —— 上次启动时后台配过什么，现在就画什么，首帧不用等网络；
  ///   2. 再请求 `/home/layout` —— 后台刚改完配置，用户下次进首页就能看到。
  /// 任何一步失败都保持当前布局（最差是内置那 10 个入口），首页不会空。
  Future<void> _loadLayout() async {
    final cached = await HomeService.loadCache();
    if (!mounted) return;
    if (cached != null) setState(() => _layout = cached);

    final fresh = await HomeService.refresh();
    if (!mounted) return;
    // 名字/图标/顺序都可能变，直接整块替换；HomeLayout 很小，重画代价可忽略
    setState(() => _layout = fresh);
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
    unawaited(_loadLayout()); // 后台刚上的广告/分类，下拉就能立刻看到
    if (mounted) setState(() => _lastUpdated = DateTime.now());
  }

  /// 游客点任何内容都先弹登录页（v2.1.48），登录成功后接着做原动作
  Future<void> _guard(VoidCallback action, {String? hint}) async {
    final ok = await ensureLogin(context, hint: hint);
    if (!ok || !mounted) return;
    action();
  }

  @override
  Widget build(BuildContext context) {
    final topAd = _layout.topAd;
    return Scaffold(
      // v2.1.84：顶栏整块抽成 HomeTopBar —— 左上角毛笔「渔报」+ 右侧铃铛，
      // 并且显式盖掉主题那条 1px 底边线（以前它横在「渔报」下面像一条白胶带）。
      // 搜索框、左上定位胶囊在 v2.1.83 已移除：搜索走「钓点」页，
      // 定位地名在下面的天气通栏里显示，顶部不再堆入口。
      //
      // v2.1.86：标题下面挂钓法分类（台钓/路亚/钓场/海钓），切换后
      // 下面的天气通栏第三格跟着换（海钓 → 潮汐，其余 → 水氧），指数也重算。
      appBar: HomeTopBar(mode: _mode, onModeChanged: _setMode),
      body: AppRefresh(
        onRefresh: _onRefresh,
        child: ListView(
          controller: _feedScroll,
          children: [
            // ① 顶部天气（改版：整块深色通栏，指数 + 建议 + 四格指标）
            HomeWeatherHero(
              weather: _weather,
              placeLabel: _place?.label,
              waterTemp: WeatherService.memoryWaterTemp,
              mode: _mode,
              tide: _tide,
              onTap: () => _guard(() => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WeatherScreen()))),
            ),
            // ② 分类导航：名字 / 图标 / 顺序 / 一行几个全部来自后台
            GridNav(items: _layout.categories, crossAxisCount: _layout.gridCols),
            // ③ 首页广告位：后台没配在投广告时整块不占位，不留空坑
            if (topAd != null) HomeAdBanner(ad: topAd),
            // 钓点横向列表（标题 + 进入钓点页）
            SectionHeader(
              title: '附近钓点',
              // 由近到远是小字说明，不跟标题一样大（原来拼在 title 里，字号一样大很突兀）
              subtitle: _myLat == null ? null : '由近到远',
              actionLabel: '更多',
              onAction: () => _guard(() => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SpotsScreen()))),
            ),
            SizedBox(
              // 卡片自身 96 高（见 SpotCard.cardHeight），这里只留一点呼吸空间，
              // 高度写死可以彻底避免「加了标签把卡片撑变形 / 被裁掉」
              //
              // v2.1.61：+6 → +2，横向列表的上下再无谓留白
              // v2.1.62：+2 → 0，卡片自己已经有 8pt 内边距，外面不再加
              height: SpotCard.cardHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePad),
                children: _spots
                    .map((s) => SpotCard(
                          spot: s,
                          distanceMeters: _distanceOf(s),
                          onTap: () => _guard(() =>
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => SpotDetailScreen(spot: s)))),
                        ))
                    .toList(),
              ),
            ),
            const SectionHeader(
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
                            // v2.1.62：上 4 → 2、下 pagePad → 6，
                            // 和上面的「钓友动态」标题咬得更紧
                            padding: const EdgeInsets.fromLTRB(
                                AppTheme.pagePad, 2, AppTheme.pagePad, 6),
                            onTap: (p) => _guard(() =>
                                Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => PostDetailScreen(post: p)))),
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
