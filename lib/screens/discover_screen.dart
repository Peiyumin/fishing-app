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
import '../widgets/post_card.dart';
import '../widgets/center_toast.dart';
import 'auth_screen.dart';
import '../widgets/app_refresh.dart';

/// 发现页：分类 Tab + 动态瀑布流
///   推荐 —— 浏览 + 点赞×3 + 评论×5 综合热度排序
///   同城 —— 自动读取定位，只显示同一地级市的动态
///   热门 —— 浏览人数最多的前 50 条随机打乱展示
///   关注 —— 只显示已关注钓友发布的动态
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final List<String> _tabs = ['推荐', '同城', '热门', '关注'];
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

  /// Tab 下标 → 接口 tab 参数
  String? get _tabKey => switch (_tabs[_tab]) {
        '推荐' => 'recommend',
        '同城' => 'city',
        '热门' => 'hot',
        '关注' => 'follow',
        _ => null,
      };

  Future<void> _goLogin() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发现'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: Colors.white,
            child: Row(
              children: _tabs
                  .map((t) => Expanded(
                        child: InkWell(
                          onTap: () {
                            if (_tab == _tabs.indexOf(t)) return;
                            setState(() => _tab = _tabs.indexOf(t));
                            _load();
                          },
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: _tab == _tabs.indexOf(t)
                                    ? AppTheme.primaryLight
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                    AppTheme.radiusPill),
                              ),
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _tab == _tabs.indexOf(t)
                                      ? AppTheme.primary
                                      : AppTheme.textSecondary,
                                  fontWeight: _tab == _tabs.indexOf(t)
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AppRefresh(
              onRefresh: _load,
              child: _posts.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inbox_outlined,
                                    size: 44,
                                    color: Colors.grey.withOpacity(0.5)),
                                const SizedBox(height: 10),
                                Text(
                                  _emptyHint ?? '这里还没有内容，下拉刷新试试',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textSecondary),
                                ),
                                if (_emptyHint?.contains('登录') == true) ...[
                                  const SizedBox(height: 14),
                                  FilledButton(
                                    onPressed: _goLogin,
                                    child: const Text('去登录'),
                                  ),
                                ],
                                if (_tabKey == 'city' && _city != null) ...[
                                  const SizedBox(height: 6),
                                  Text('当前城市：$_city',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      children: _posts.map((p) => PostCard(post: p)).toList(),
                    ),
            ),
    );
  }
}
