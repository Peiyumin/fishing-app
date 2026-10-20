import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/fishing_spot.dart';
import '../models/post.dart';
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

  @override
  void initState() {
    super.initState();
    _loadWeather();
    _loadSpots();
    _loadFeed();
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
  Future<void> _loadWeather() async {
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
    try {
      final w = await WeatherService.fetch(lat, lng);
      if (mounted) setState(() => _weather = w);
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, '天气加载失败：$e');
      }
    } finally {
      if (mounted) setState(() => _loadingWeather = false);
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
        title: const Text('垂钓圈'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        // 顶部搜索框
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                            title: '实时天气',
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
                            child: WeatherCard(weather: _weather!),
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
