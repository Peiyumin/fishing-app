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
    return WaterfallGrid(
      posts: _posts,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
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
