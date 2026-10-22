import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/nearby_angler.dart';
import '../services/follow_service.dart';
import '../services/location_service.dart';
import '../services/member_service.dart';
import '../services/nearby_service.dart';
import '../widgets/center_toast.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';

/// 附近钓友（v27）：按定位由近到远，需开通会员；互相关注后可私信
class NearbyAnglersScreen extends StatefulWidget {
  const NearbyAnglersScreen({super.key});

  @override
  State<NearbyAnglersScreen> createState() => _NearbyAnglersScreenState();
}

class _NearbyAnglersScreenState extends State<NearbyAnglersScreen> {
  List<NearbyAngler> _list = const [];
  bool _loading = true;
  bool _isMember = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await MemberService.info();
      if (!mounted) return;
      if (!info.active) {
        setState(() {
          _isMember = false;
          _loading = false;
        });
        return;
      }
      setState(() => _isMember = true);

      final pos = await LocationService.determinePosition();
      if (!mounted) return;
      final list = await NearbyService.anglers(
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  /// 关注状态本地维护（附近列表不返回关注关系，用乐观切换 + 失败回滚）
  final Set<String> _following = {};

  Future<void> _follow(NearbyAngler a) async {
    final wasFollowing = _following.contains(a.userId);
    setState(() {
      if (wasFollowing) {
        _following.remove(a.userId);
      } else {
        _following.add(a.userId);
      }
    });
    try {
      final r = await FollowService.toggleFollow(a.userId, wasFollowing);
      if (!mounted) return;
      if (!r.following && _following.contains(a.userId)) {
        setState(() => _following.remove(a.userId));
      }
      CenterToast.show(context, r.following ? '已关注' : '已取消关注');
    } catch (e) {
      if (!mounted) return;
      // 失败回滚
      setState(() {
        if (wasFollowing) {
          _following.add(a.userId);
        } else {
          _following.remove(a.userId);
        }
      });
      CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _chat(NearbyAngler a) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(peerId: a.userId, nickname: a.nickname),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('附近钓友',
            style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _init,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (!_isMember) {
      return _memberGate();
    }
    if (_error != null) {
      return _errorView();
    }
    if (_list.isEmpty) {
      return _empty();
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: _list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _card(_list[i]),
    );
  }

  Widget _memberGate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.workspace_premium,
                  size: 36, color: AppTheme.primary),
            ),
            const SizedBox(height: 16),
            const Text('附近钓友是会员专属功能',
                style: TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
              '开通会员后即可发现身边的钓友，按距离由近到远排序，互相关注还能互发私信。',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSecondary,
                  height: 1.5),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 34, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22)),
              ),
              onPressed: () async {
                await Navigator.of(context).pushNamed('/member-center');
                _init();
              },
              child: const Text('去开通会员',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off_outlined,
                size: 44, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(_error ?? '定位失败',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                    height: 1.5)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _init,
              child: const Text('重试',
                  style: TextStyle(color: AppTheme.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.explore_outlined,
              size: 46, color: AppTheme.textSecondary.withOpacity(0.4)),
          const SizedBox(height: 12),
          const Text('附近 48 小时内还没有其他钓友',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          const Text('多邀请几位钓友来吧',
              style: TextStyle(
                  fontSize: 11.5, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _card(NearbyAngler a) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          UserAvatar(
            url: a.avatar,
            userId: a.userId,
            vipLevel: a.vipLevel,
            radius: 24,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.nickname.isEmpty ? '钓友' : a.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 12, color: AppTheme.primary),
                    const SizedBox(width: 2),
                    Text('距离 ${a.distanceText}',
                        style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text('Lv.${a.level}',
                        style: const TextStyle(
                            fontSize: 10.5, color: AppTheme.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          _miniBtn('私信', Icons.chat_bubble_outline, () => _chat(a)),
          const SizedBox(width: 8),
          _miniBtn('关注', Icons.person_add_alt_outlined, () => _follow(a),
              filled: true),
        ],
      ),
    );
  }

  Widget _miniBtn(String label, IconData icon, VoidCallback onTap,
      {bool filled = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? AppTheme.primary : AppTheme.primaryLight,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 13,
                color: filled ? Colors.white : AppTheme.primaryDark),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: filled ? Colors.white : AppTheme.primaryDark)),
          ],
        ),
      ),
    );
  }
}
