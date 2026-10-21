import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'package:provider/provider.dart';

import '../models/post.dart';
import '../models/user_profile.dart';
import '../services/follow_service.dart';
import '../services/post_service.dart';
import '../services/refresh_bus.dart';
import '../services/session_provider.dart';
import '../services/api_config.dart';
import '../widgets/post_card.dart';
import 'auth_screen.dart';
import 'edit_profile_screen.dart';
import 'follow_list_screen.dart';

/// 我的页：未登录显示登录入口；已登录显示资料 + 我的发布
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Post> _myPosts = [];
  UserProfile? _me;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // 积分兑换 / 发布渔获后刷新资料（积分余额要跟着变）
    RefreshBus.profileTick.addListener(_onProfileTick);
    RefreshBus.feedTick.addListener(_onFeedTick);
  }

  @override
  void dispose() {
    RefreshBus.profileTick.removeListener(_onProfileTick);
    RefreshBus.feedTick.removeListener(_onFeedTick);
    super.dispose();
  }

  void _onProfileTick() => _loadMe();

  void _onFeedTick() {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (sp.isLoggedIn || !ApiConfig.enabled) _loadMyPosts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sp = Provider.of<SessionProvider>(context);
    // 已登录，或未配置后端（演示模式）都加载「我的发布」
    if (sp.isLoggedIn || !ApiConfig.enabled) _loadMyPosts();
    if (sp.isLoggedIn) _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final me = await FollowService.fetchMe();
      if (mounted) setState(() => _me = me);
    } catch (_) {
      // 关注功能未启用：忽略，计数行不显示
    }
  }

  Future<void> _loadMyPosts() async {
    setState(() => _loading = true);
    try {
      if (!ApiConfig.enabled) {
        // 演示模式：直接展示示例动态
        if (mounted) setState(() => _myPosts = PostService.demoPosts);
        return;
      }
      final posts = await PostService.fetchFeed(limit: 50);
      final uid = Provider.of<SessionProvider>(context, listen: false).userId;
      if (mounted) {
        setState(() => _myPosts = posts.where((p) => p.userId == uid).toList());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 绿色头部上的白色计数块（关注 / 粉丝 / 发布），可点击
  Widget _countTile(String label, int value, VoidCallback? onTap) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sp = Provider.of<SessionProvider>(context);

    if (!sp.isLoggedIn && ApiConfig.enabled) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('我的'),
          flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_outline, size: 80, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('登录后查看你的渔获与收藏'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                ),
                child: const Text('登录 / 注册'),
              ),
            ],
          ),
        ),
      );
    }

    final isDemo = !ApiConfig.enabled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        actions: [
          if (sp.isLoggedIn)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑资料',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const EditProfileScreen()),
                );
                // 资料可能已改：刷新计数与发布列表
                _loadMe();
                _loadMyPosts();
              },
            ),
          if (sp.isLoggedIn)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await sp.signOut();
                setState(() => _myPosts = []);
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadMyPosts,
        child: ListView(
          children: [
            // 资料头
            Container(
              padding: const EdgeInsets.all(20),
              color: AppTheme.primary,
              child: Column(
                children: [
                  Row(
                    children: [
                      // 头像（已设置则显示图片，点击可编辑资料）
                      GestureDetector(
                        onTap: sp.isLoggedIn
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const EditProfileScreen()),
                                )
                            : null,
                        child: CircleAvatar(
                          radius: 32,
                          backgroundColor: Colors.white,
                          // 必须用 avatarUrl（内部走 ApiConfig.mediaUrl）：
                          // 后台返回的地址常会丢掉 :8801 端口，直接用原始
                          // avatar 会 404 → 头像显示成一个白圆。
                          backgroundImage: (sp.avatarUrl != null &&
                                  sp.avatarUrl!.isNotEmpty)
                              ? NetworkImage(sp.avatarUrl!)
                              : null,
                          child: (sp.avatarUrl == null || sp.avatarUrl!.isEmpty)
                              ? const Icon(Icons.person,
                                  size: 36, color: AppTheme.primary)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                isDemo
                                    ? '演示用户（未配置后端）'
                                    : (sp.nickname ?? '钓友'),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text('我的发布：${_myPosts.length}',
                                style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // 关注 / 粉丝 / 发布 计数（关注后端可用时才显示）
                  if (_me != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _countTile('关注', _me!.followingCount, () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => FollowListScreen(
                              userId: sp.userId ?? '',
                              title: '关注',
                              followers: false,
                            ),
                          ));
                        }),
                        _countTile('粉丝', _me!.followerCount, () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => FollowListScreen(
                              userId: sp.userId ?? '',
                              title: '粉丝',
                              followers: true,
                            ),
                          ));
                        }),
                        _countTile('发布', _me!.postCount, null),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // 积分余额（名称由后台「积分设置」控制，发布渔获自动增加）
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.stars_rounded,
                              color: Color(0xFFFFD65C), size: 18),
                          const SizedBox(width: 6),
                          Text(_me!.pointsName,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          const SizedBox(width: 8),
                          Text('${_me!.points}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('我的发布',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _myPosts.isEmpty
                    ? const Center(child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('还没有发布，去首页点「+」发布吧'),
                      ))
                    : Column(
                        children:
                            _myPosts.map((p) => PostCard(post: p)).toList(),
                      ),
          ],
        ),
      ),
    );
  }
}
