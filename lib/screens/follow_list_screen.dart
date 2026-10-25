import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/follow_service.dart';
import '../widgets/follow_button.dart';
import '../widgets/user_avatar.dart';
import 'user_profile_screen.dart';
import '../widgets/app_refresh.dart';

/// 粉丝 / 关注 列表页
class FollowListScreen extends StatefulWidget {
  final String userId;
  final String title; // '粉丝' 或 '关注'
  final bool followers; // true=粉丝列表 false=关注列表
  const FollowListScreen({
    super.key,
    required this.userId,
    required this.title,
    required this.followers,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  List<UserProfile> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = widget.followers
          ? await FollowService.fetchFollowers(widget.userId)
          : await FollowService.fetchFollowing(widget.userId);
      if (mounted) setState(() => _users = list);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is FollowNotAvailableException
            ? e.message
            : '加载失败：$e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _msg(_error!)
              : _users.isEmpty
                  ? _msg(widget.followers ? '还没有粉丝' : '还没有关注任何人')
                  : AppRefresh(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _users.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 72),
                        itemBuilder: (_, i) {
                          final u = _users[i];
                          return ListTile(
                            leading: UserAvatar(
                              url: u.avatar,
                              userId: u.id,
                              radius: 20,
                              member: u.vip,
                            ),
                            title: Text(u.nickname),
                            subtitle: Text('粉丝 ${u.followerCount}'),
                            trailing: FollowButton(
                              userId: u.id,
                              initialFollowing: u.isFollowing,
                              isMe: u.isMe,
                              compact: true,
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => UserProfileScreen(userId: u.id),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _msg(String s) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(s, textAlign: TextAlign.center),
        ),
      );
}
