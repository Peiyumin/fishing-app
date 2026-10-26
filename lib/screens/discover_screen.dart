import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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
import '../widgets/user_avatar.dart';
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
  List<Post> _posts = [];
  bool _loading = true;
  String? _emptyHint; // 空列表时的说明（如同城未授权）
  String? _city; // 当前定位城市（同城 Tab）

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _tabKey => _tabDefs[_tab][2];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _emptyHint = null;
    });
    try {
      final tab = _tabKey;
      String? city;
      if (tab == 'city') {
        // 同城：先取定位城市；失败则给出引导提示
        city = _city ??= await GeoNames.currentCity();
        if (city == null || city.isEmpty) {
          if (mounted) {
            setState(() {
              _posts = [];
              _loading = false;
              _emptyHint = '未能获取定位城市，请在系统设置中允许定位权限后下拉刷新';
            });
          }
          return;
        }
      }
      if (tab == 'follow' && ApiConfig.enabled) {
        final sp = Provider.of<SessionProvider>(context, listen: false);
        if (!sp.isLoggedIn) {
          if (mounted) {
            setState(() {
              _posts = [];
              _loading = false;
              _emptyHint = '登录后即可查看已关注钓友的动态';
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
              _posts = [];
              _loading = false;
              _emptyHint = '关注功能需升级后端后启用';
            });
          }
          return;
        }
      }
      if (tab == 'city' && result.isEmpty) {
        _emptyHint = '当前城市（${city ?? '未知'}）暂无动态，发布动态后会自动展示在这里';
      }
      if (mounted) setState(() => _posts = result);
    } catch (e) {
      if (mounted) CenterToast.show(context, '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
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
      backgroundColor: const Color(0xFFF6F7F7),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            _tabs(),
            Expanded(
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
                      child: _posts.isEmpty ? _empty() : _grid(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 大标题 + 副标（左侧竖排，和参考图一致）
  Widget _header() {
    final place = _city ?? '附近';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '钓友圈',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: Color(0xFF15181A),
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '看渔获 · 找钓友 · $place',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF8A9096)),
          ),
        ],
      ),
    );
  }

  /// 四个胶囊 tab：选中黑底白字，未选白底灰字，下面一行小英文
  Widget _tabs() {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: _tabDefs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final on = _tab == i;
          return GestureDetector(
            onTap: () {
              if (_tab == i) return;
              setState(() => _tab = i);
              _load();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: on ? const Color(0xFF15181A) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: on ? const Color(0xFF15181A) : const Color(0xFFE6E8EA)),
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
                      color: on ? Colors.white : const Color(0xFF2B2F33),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _tabDefs[i][1],
                    style: TextStyle(
                      fontSize: 8,
                      height: 1.1,
                      letterSpacing: .6,
                      fontWeight: FontWeight.w600,
                      color: on ? Colors.white70 : const Color(0xFFA3A9AF),
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
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: .52,
      ),
      itemCount: _posts.length,
      itemBuilder: (_, i) => WaterfallPostCard(
        post: _posts[i],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PostDetailScreen(post: _posts[i])),
        ),
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

/// 瀑布流里的一张卡片
class WaterfallPostCard extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;

  const WaterfallPostCard({required this.post, required this.onTap});

  /// 鱼种标题：前两种 + 「+N 种」
  String get _fishTitle {
    if (post.fish.isEmpty) {
      return post.category == 'post' ? '今日鱼获' : post.categoryLabel;
    }
    final names = post.fish
        .map((e) => (e['name'] ?? '').toString())
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return '今日鱼获';
    final head = names.take(2).join(' ');
    return names.length > 2 ? '$head +${names.length - 2} 种' : head;
  }

  /// 鱼获总条数（左上角标）
  int get _fishCount {
    var n = 0;
    for (final e in post.fish) {
      n += int.tryParse('${e['count'] ?? 1}') ?? 1;
    }
    return n <= 0 ? 1 : n;
  }

  /// 热度指数：浏览 + 点赞×4 + 评论×6，压到 55~99
  int get _index {
    final raw = post.viewCount + post.likeCount * 4 + post.commentCount * 6;
    if (raw <= 0) return 60;
    return math.min(99, 55 + (math.log(raw + 1) * 8.5).round());
  }

  String get _cover => post.imageUrls.isNotEmpty ? post.imageUrls.first : '';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _coverArea()),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 正文/标题两行
                    Text(
                      post.body != null && post.body!.trim().isNotEmpty
                          ? post.body!.trim()
                          : post.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.32,
                        color: Color(0xFF2B2F33),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (post.city.trim().isNotEmpty ||
                        (post.locationName ?? '').trim().isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 11, color: Color(0xFF9AA1A7)),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              post.city.trim().isNotEmpty
                                  ? post.city.trim()
                                  : post.locationName!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10, color: Color(0xFF9AA1A7)),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        UserAvatar(
                          url: post.avatarUrl,
                          userId: post.userId,
                          radius: 9,
                          vipLevel: post.authorVip,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            post.username ?? '钓友',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4A5056)),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: .5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF15181A),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'LV${post.userLevel <= 0 ? 1 : post.userLevel}',
                            style: const TextStyle(
                                fontSize: 8,
                                height: 1.3,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          post.likedByMe
                              ? Icons.thumb_up
                              : Icons.thumb_up_outlined,
                          size: 11,
                          color: post.likedByMe
                              ? AppTheme.primary
                              : const Color(0xFF9AA1A7),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${post.likeCount}',
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF9AA1A7)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 图片区：左上角标（条数）、右上评论数、底部渐变 + 鱼种名 + 指数
  Widget _coverArea() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_cover.isEmpty)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF23543F), Color(0xFF10251C)],
              ),
            ),
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _fishTitle,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
            ),
          )
        else
          CachedNetworkImage(
            imageUrl: ApiConfig.mediaUrl(_cover) ?? '',
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: const Color(0xFFE7EBE9)),
            errorWidget: (_, __, ___) =>
                Container(color: const Color(0xFFE7EBE9)),
          ),

        // 左上：鱼种标记 + 条数
        Positioned(
          left: 6,
          top: 6,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.45),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.set_meal, size: 10, color: Colors.white),
                    SizedBox(width: 2),
                    Icon(Icons.people_alt, size: 10, color: Colors.white),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.45),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$_fishCount',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),

        // 右上：评论数
        Positioned(
          right: 6,
          top: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.45),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.mode_comment_outlined,
                    size: 10, color: Colors.white),
                const SizedBox(width: 2),
                Text(
                  '${post.commentCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 9.5),
                ),
              ],
            ),
          ),
        ),

        // 底部：渐变压暗 + 鱼种名 + 指数
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(7, 16, 7, 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(.62),
                ],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    _fishTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB6F09A),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '指数 $_index',
                    style: const TextStyle(
                      fontSize: 9.5,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF17331A),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
