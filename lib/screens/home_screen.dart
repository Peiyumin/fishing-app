import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/fishing_spot.dart';
import '../models/post.dart';
import '../services/geo_place.dart';
import '../services/location_service.dart';
import '../services/post_service.dart';
import '../services/session_provider.dart';
import '../services/spot_service.dart';
import '../services/weather_service.dart';
import '../widgets/center_toast.dart';
import '../widgets/grid_nav.dart';
import '../widgets/location_prompt.dart';
import '../widgets/post_card.dart';
import '../widgets/section_header.dart';
import '../widgets/spot_card.dart';
import '../widgets/weather_card.dart';
import 'search_screen.dart';
import 'weather_screen.dart';
import 'spots_screen.dart';
import 'spot_detail_screen.dart';

/// 首页：搜索框 + 宫格导航 + 天气/钓点 + 实时动态流
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FishingWeather? _weather;
  List<FishingSpot> _spots = [];
  List<Post> _posts = [];
  bool _loadingWeather = true;
  bool _loadingPosts = true;

  /// 当前定位的地名（首页左上角显示「禹州 / 许昌」这类短名）
  GeoPlace? _place;
  bool _locatingPlace = false;

  @override
  void initState() {
    super.initState();
    _loadPlace();
    _loadWeather();
    _loadSpots();
    _loadFeed();
  }

  /// 解析当前定位的中文地名（显示在软件名左侧）
  Future<void> _loadPlace({bool refresh = false}) async {
    if (_locatingPlace) return;
    _locatingPlace = true;
    if (mounted && refresh) setState(() {});
    try {
      final p = await GeoPlace.current(refresh: refresh);
      if (mounted && p != null) setState(() => _place = p);
    } finally {
      if (mounted) setState(() => _locatingPlace = false);
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
  Future<void> _loadWeather() async {
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
    double lat = 30.2741, lng = 120.1551; // 默认：杭州
    try {
      final pos = await LocationService.determinePosition();
      lat = pos.latitude;
      lng = pos.longitude;
    } on LocationException catch (e) {
      // 首次打开 App：权限被拒时引导用户授权（其他原因静默用默认坐标）
      if (e.type == LocationErrorType.permissionDenied && mounted) {
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
        // 已有缓存时不打扰用户；完全没有数据时才提示
        if (_weather == null) {
          CenterToast.show(context, '天气暂不可用，请检查网络');
        }
      }
    }
  }

  Future<void> _loadSpots() async {
    final spots = await SpotService.fetchSpots();
    if (mounted) setState(() => _spots = spots);
  }

  Future<void> _loadFeed() async {
    try {
      final posts = await PostService.fetchFeed(limit: 20);
      if (mounted) setState(() => _posts = posts);
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, '动态加载失败：$e');
      }
    } finally {
      if (mounted) setState(() => _loadingPosts = false);
    }
  }

  Future<void> _onRefresh() async {
    await Future.wait([_loadFeed(), _loadWeather(), _loadSpots()]);
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
              actionLabel: '更多',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SpotsScreen()),
              ),
            ),
            SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _spots
                    .map((s) => SpotCard(
                          spot: s,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => SpotDetailScreen(spot: s)),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SectionHeader(title: '钓友动态'),
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
