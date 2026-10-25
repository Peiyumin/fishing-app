import 'package:flutter/material.dart';

import '../app_theme.dart';

import '../models/post.dart';
import '../models/user_profile.dart';
import '../services/follow_service.dart';
import '../services/post_service.dart';
import '../widgets/follow_button.dart';
import '../widgets/post_card.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';
import 'follow_list_screen.dart';

/// 他人（或自己）的用户资料页：头像 + 关注/粉丝/发布 + 关注按钮 + TA 的动态
class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  UserProfile? _profile;
  bool _followUnavailable = false;
  List<Post> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 私信对方：直接进入会话页。
  /// 会员不限条数；非会员每个对象 6 条，发满后聊天页弹窗引导开通。
  Future<void> _openChat() async {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ChatScreen(peerId: widget.userId, nickname: _profile?.nickname ?? '钓友'),
    ));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    UserProfile? profile;
    var unavailable = false;
    try {
      profile = await FollowService.fetchProfile(widget.userId);
    } on FollowNotAvailableException {
      unavailable = true;
    } catch (_) {
      // 其它错误也降级：不显示计数
    }
    // TA 的动态：复用信息流按 userId 过滤（与「我的」页一致）
    List<Post> posts = [];
    try {
      final all = await PostService.fetchFeed(limit: 50);
      posts = all.where((p) => p.userId == widget.userId).toList();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _profile = profile;
        _followUnavailable = unavailable;
        _posts = posts;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return Scaffold(
      appBar: AppBar(title: Text(p?.nickname ?? '用户资料')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  _header(p),
                  if (_followUnavailable)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.warningLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 18, color: AppTheme.warning),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('关注/粉丝功能需升级后端后启用',
                                style: TextStyle(
                                    fontSize: 12, color: AppTheme.warning)),
                          ),
                        ],
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('TA 的发布',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  if (_posts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('还没有发布动态')),
                    )
                  else
                    ..._posts.map((post) => PostCard(post: post)),
                ],
              ),
            ),
    );
  }

  Widget _header(UserProfile? p) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: AppTheme.primary,
      child: Column(
        children: [
          Row(
            children: [
              UserAvatar(
                url: p?.avatar,
                userId: p?.id,
                radius: 34,
                vipLevel: p?.vip.level,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p?.nickname ?? '钓友',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    if (p != null && p.bio.trim().isNotEmpty)
                      Text(p.bio.trim(),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 8),
                    if (!(p?.isMe ?? false))
                      Row(
                        children: [
                          FollowButton(
                            userId: widget.userId,
                            initialFollowing: p?.isFollowing ?? false,
                            isMe: p?.isMe ?? false,
                            onChanged: (f) => _load(),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: _openChat,
                            icon: const Icon(Icons.chat_bubble_outline, size: 16),
                            label: const Text('私信'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white70),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 关注 / 粉丝 / 发布
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _count('关注', p?.followingCount ?? 0, () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => FollowListScreen(
                    userId: widget.userId,
                    title: '关注',
                    followers: false,
                  ),
                ));
              }),
              _count('粉丝', p?.followerCount ?? 0, () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => FollowListScreen(
                    userId: widget.userId,
                    title: '粉丝',
                    followers: true,
                  ),
                ));
              }),
              _count('发布', p?.postCount ?? _posts.length, null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _count(String label, int value, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            Text('$value',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
