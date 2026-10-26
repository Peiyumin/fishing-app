import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../services/post_service.dart';
import '../services/follow_service.dart';
import '../services/session_provider.dart';
import '../services/api_config.dart';
import '../utils/geo_names.dart';
import '../widgets/center_toast.dart';
import '../widgets/app_refresh.dart';
import '../widgets/waterfall_post_card.dart';
import 'auth_screen.dart';
import 'post_detail_screen.dart';

/// 发现页（钓友圈）：双列瀑布流
///
/// 布局照用户给的参考图重做：顶部大标题 + 四个中英双行胶囊 tab，
/// 下面是两列卡片 —— 图片左上角标（鱼种数）、右上评论数、图上叠鱼种名与
/// 绿色「指数」，图下正文两行、城市、作者行（头像 + 昵称 + LV + 点赞）。
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  /// [中文名, 英文副标, 接口 tab 参数]
  static const List<List<String>> _tabDefs = [
    ['推荐', 'FOR YOU', 'recommend'],
    ['热门', 'HOT', 'hot'],
    ['同城', 'LOCAL', 'city'],
    ['关注', 'FOLLOW', 'follow'],
  ];

  int _tab = 0;

  /// 每个 tab 的结果各自缓存：切回来秒显，不再整块消失重新请求
  final Map<String, List<Post>> _cache = {};

  /// 只有「当前 tab 一条数据都没有」时才全屏转圈。
  ///
  /// ★ 这里以前是 `_load()` 一进来就无条件 `_loading = true`，把整个内容区
  ///   连同外层的 `AppRefresh` / `RefreshIndicator` 一起换成一个小转圈，于是：
  ///
  ///   ① 每次下拉刷新，列表**整个消失**闪一下白；
  ///   ② 列表被销毁重建 → **滚动位置归零**，刚翻到的位置跳回顶部；
  ///   ③ `RefreshIndicator` 被销毁后立刻重建，手指还在屏幕上的话会被再次
  ///      判定成一次下拉 → 又刷新 → 0.3~0.7 秒闪一次的自激循环
  ///      （用户录屏里前 11 秒闪着不停就是这个）；
  ///   ④ `AppRefresh` 的「垂钓圈 为您玩命加载…」提示条刚滑出就被销毁，
  ///      **从来没机会显示**。
  ///
  ///   现在只有首次进页面 / 切到一个还没数据的 tab 才转圈，刷新一律保留旧列表。
  bool _loading = true;

  String? _emptyHint; // 空列表时的说明（如同城未授权）
  String? _city; // 当前定位城市（同城 Tab）

  /// 正在请求中的 tab：连点同一个 tab 不重复打请求
  final Set<String> _inflight = {};

  /// 每个 tab 上一次真正发起请求的时间。
  /// 用来掐掉「刷新刚结束又被触发」的连击 —— 手指还在屏幕上时，
  /// RefreshIndicator 反复重建会让 onRefresh 被连着叫好几次。
  final Map<String, DateTime> _lastLoadAt = {};

  static const Duration _minGap = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _tabKey => _tabDefs[_tab][2];

  /// 当前 tab 要显示的列表（有缓存就用缓存，切回来不闪）
  List<Post> get _posts => _cache[_tabKey] ?? const <Post>[];

  Future<void> _load() async {
    final tab = _tabKey;
    final hasData = (_cache[tab] ?? const <Post>[]).isNotEmpty;
    if (mounted) {
      setState(() {
        // 有旧数据就继续显示，让下面的提示条去转圈；无数据才全屏等
        _loading = !hasData;
        _emptyHint = null;
      });
    }
    if (_inflight.contains(tab)) return; // 同一个 tab 已有请求在飞，等它回来
    if (hasData) {
      // 已经有内容了：0.6 秒内的重复触发直接吞掉（不影响首次进页面/tab）
      final now = DateTime.now();
      final last = _lastLoadAt[tab];
      if (last != null && now.difference(last) < _minGap) return;
      _lastLoadAt[tab] = now;
    }
    _inflight.add(tab);
    try {
      String? city;
      if (tab == 'city') {
        // 同城：先取定位城市；失败则给出引导提示
        city = _city ??= await GeoNames.currentCity();
        if (city == null || city.isEmpty) {
          if (mounted) {
            setState(() {
              _cache[tab] = const <Post>[];
              if (_tabKey == tab) {
                _loading = false;
                _emptyHint = '未能获取定位城市，请在系统设置中允许定位权限后下拉刷新';
              }
            });
          }
          return;
        }
      }
      if (tab == 'follow' && ApiConfig.enabled) {
        if (!mounted) return; // await 过定位，可能已经离场
        final sp = Provider.of<SessionProvider>(context, listen: false);
        if (!sp.isLoggedIn) {
          if (mounted) {
            setState(() {
              _cache[tab] = const <Post>[];
              if (_tabKey == tab) {
                _loading = false;
                _emptyHint = '登录后即可查看已关注钓友的动态';
              }
            });
          }
          return;
        }
      }
      final posts = await PostService.fetchFeed(limit: 30, tab: tab, city: city);
      List<Post> result = posts;
      if (tab == 'follow') {
        // 本地兜底过滤：老后端忽略 tab 参数会返回全量，
        // 只保留「我关注的用户」发布的动态
        try {
          final me = await FollowService.fetchMe();
          final following = await FollowService.fetchFollowing(me.id);
          final ids = following.map((u) => u.id).toSet();
          result = posts.where((p) => ids.contains(p.userId)).toList();
        } on FollowNotAvailableException {
          if (mounted) {
            setState(() {
              _cache[tab] = const <Post>[];
              if (_tabKey == tab) {
                _loading = false;
                _emptyHint = '关注功能需升级后端后启用';
              }
            });
          }
          return;
        }
      }
      if (mounted) {
        setState(() {
          // 请求期间用户可能已经切走：结果照样进缓存，但不改别的 tab 的界面
          _cache[tab] = result;
          if (_tabKey == tab) {
            _loading = false;
            _emptyHint = (tab == 'city' && result.isEmpty)
                ? '当前城市（${city ?? '未知'}）暂无动态，发布动态后会自动展示在这里'
                : null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_tabKey == tab) _loading = false;
        });
        CenterToast.show(context, '加载失败：$e');
      }
    } finally {
      _inflight.remove(tab);
    }
  }

  Future<void> _goLogin() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          // ── 浅色头部：和设计稿一致 ──
          //
          // 钓友圈是「内容流」页面，头部让位给内容：底色就是页面底，
          // 黑色大标题 + 冷灰副标，唯一的色块是选中那颗黑胶囊。
          // 状态栏图标转深色（浅底上白字等于看不见）。
          AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.dark,
            child: Container(
              width: double.infinity,
              color: AppTheme.background,
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_header(), _tabs()],
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: AppTheme.background,
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : AppRefresh(
                      onRefresh: _load,
                      // 每个 tab 各记一份「最后更新」，别把热门的刷新时间
                      // 显示在关注 tab 上
                      memoKey: 'discover_$_tabKey',
                      child: _posts.isEmpty ? _empty() : _grid(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 大标题 + 副标（左侧竖排，和参考图一致）
  Widget _header() {
    final place = _city ?? '附近';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                '钓友圈',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: AppTheme.textPrimary,
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(width: 8),
              // 右上角一个小圆点，让纯色标题行有节奏（不抢标题）
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '看渔获 · 找钓友 · $place',
            style: const TextStyle(
                fontSize: 12.5, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  /// 四个胶囊 tab：选中黑底 + 荧光黄绿字，未选白底 + 冷灰字
  ///
  /// 设计稿里「选中」不是加粗或变色，而是直接翻成黑胶囊 —— 一屏只有这一处
  /// 纯黑大色块，视线自然落上去；黄绿只在黑底上用，白底上它是看不见的。
  Widget _tabs() {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        itemCount: _tabDefs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final on = _tab == i;
          return GestureDetector(
            onTap: () {
              if (_tab == i) return;
              // 切 tab 和「要不要转圈」放在同一次 setState 里：
              // 否则会先按新 tab 的空缓存渲染一帧「暂无内容」，再切成转圈
              setState(() {
                _tab = i;
                _loading = (_cache[_tabDefs[i][2]] ?? const <Post>[]).isEmpty;
                _emptyHint = null;
              });
              _load();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: on ? AppTheme.primary : AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: on ? AppTheme.primary : AppTheme.border,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _tabDefs[i][0],
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: on ? AppTheme.accent : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _tabDefs[i][1],
                    style: TextStyle(
                      fontSize: 8,
                      height: 1.1,
                      letterSpacing: .6,
                      fontWeight: FontWeight.w700,
                      color: on
                          ? AppTheme.accent.withOpacity(.78)
                          : AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _grid() {
    return WaterfallGrid(
      // 每个 tab 一个独立的 element / 存储桶：来回切不会串滚动位置，
      // 同一 tab 内重建也能把位置还原回去
      key: PageStorageKey('discover_grid_$_tabKey'),
      posts: _posts,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
      onTap: (p) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PostDetailScreen(post: p)),
      ),
    );
  }

  Widget _empty() {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined,
                    size: 44, color: Colors.grey.withOpacity(0.5)),
                const SizedBox(height: 10),
                Text(
                  _emptyHint ?? '这里还没有内容，下拉刷新试试',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary),
                ),
                if (_emptyHint?.contains('登录') == true) ...[
                  const SizedBox(height: 14),
                  FilledButton(onPressed: _goLogin, child: const Text('去登录')),
                ],
                if (_tabKey == 'city' && _city != null) ...[
                  const SizedBox(height: 6),
                  Text('当前城市：$_city',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
