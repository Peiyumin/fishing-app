import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/nearby_angler.dart';
import '../services/follow_service.dart';
import '../services/location_service.dart';
import '../services/nearby_service.dart';
import '../widgets/center_toast.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';
import 'user_profile_screen.dart';
import '../widgets/app_refresh.dart';

/// 附近钓友：按定位由近到远，列表含头像/名字/签名/关注/私信/距离
///
/// v2.1.61：[embedded] = true 时不再自带 Scaffold / AppBar，
/// 直接嵌进「发现」页的「钓友」Tab（那一页自己已经有顶栏和 tab 条）。
/// 逻辑（定位、关注、私信、空态）两边完全共用，不做第二份。
class NearbyAnglersScreen extends StatefulWidget {
  final bool embedded;

  const NearbyAnglersScreen({super.key, this.embedded = false});

  @override
  State<NearbyAnglersScreen> createState() => _NearbyAnglersScreenState();
}

class _NearbyAnglersScreenState extends State<NearbyAnglersScreen> {
  List<NearbyAngler> _list = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      // 已有列表时刷新不清空，避免整块消失闪白
      _loading = _list.isEmpty;
      _error = null;
    });
    try {
      final pos = await LocationService.determinePosition();
      if (!mounted) return;
      final list = await NearbyService.anglers(
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (!mounted) return;
      // 用后端返回的关注关系初始化本地关注集合
      final following = <String>{for (final a in list) if (a.followed) a.userId};
      setState(() {
        _list = list;
        _following
          ..clear()
          ..addAll(following);
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

  /// 打开对方个人主页（头像 / 昵称 / 距离处点击都走这里）
  Future<void> _openProfile(NearbyAngler a) async {
    if (a.userId.trim().isEmpty) {
      CenterToast.show(context, '这位钓友的资料暂时打不开');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UserProfileScreen(userId: a.userId),
    ));
  }

  Future<void> _chat(NearbyAngler a) async {
    // 非会员也能进聊天页：会员不限条数，非会员每个对象 6 条，
    // 发满后由聊天页弹窗引导开通（规则见 lib/messages.php: CHAT_FREE_LIMIT）
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(peerId: a.userId, nickname: a.nickname),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final content = AppRefresh(
      color: AppTheme.primary,
      onRefresh: _init,
      child: _body(),
    );
    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('附近钓友',
            style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: content,
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_error != null) {
      return _errorView();
    }
    if (_list.isEmpty) {
      return _empty();
    }
    return ListView.separated(
      // v2.1.61：跟着全站页边距收窄（12 → pagePad，间距 8 → 6）
      padding: EdgeInsets.fromLTRB(
          AppTheme.pagePad, widget.embedded ? 8 : 10, AppTheme.pagePad, 24),
      itemCount: _list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _card(_list[i]),
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
    final followed = _following.contains(a.userId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          // 头像 / 昵称 / 距离整块都可点 → 进对方主页
          // ★ 必须包一层透明 Material：卡片有白色底色，水波纹画在祖先 Material
          //   上会被这层底色盖住，按下去像没反应。
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => _openProfile(a),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
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
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                      a.nickname.isEmpty ? '钓友' : a.nickname,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                ),
                                if (a.member)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('会员',
                                        style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.primaryDark)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            if (a.bio.isNotEmpty)
                              Text(a.bio,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.textSecondary)),
                            const SizedBox(height: 4),
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
                                        fontSize: 10.5,
                                        color: AppTheme.textSecondary)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _miniBtn('私信', Icons.chat_bubble_outline, () => _chat(a)),
          const SizedBox(width: 8),
          _miniBtn(
            followed ? '已关注' : '关注',
            followed ? Icons.check : Icons.person_add_alt_outlined,
            () => _follow(a),
            filled: !followed,
          ),
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
