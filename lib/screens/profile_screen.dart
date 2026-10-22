import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/badge.dart';
import '../models/member.dart';
import '../models/post.dart';
import '../models/profile_config.dart';
import '../models/user_profile.dart';
import '../services/api_config.dart';
import '../services/follow_service.dart';
import '../services/post_service.dart';
import '../services/profile_service.dart';
import '../services/refresh_bus.dart';
import '../services/session_provider.dart';
import '../services/shop_service.dart';
import '../widgets/center_toast.dart';
import '../widgets/user_avatar.dart';
import 'auth_screen.dart';
import 'edit_profile_screen.dart';
import 'follow_list_screen.dart';
import 'mall_screen.dart';
import 'spots_screen.dart';
import 'wallet_screen.dart';
import 'weather_screen.dart';
import 'my_posts_screen.dart';

/// 我的页
///
/// 版面顺序（都能在后台「我的页配置」里改标题/图标/跳转）：
///   资料头（头像会员框 + 昵称 + 会员标签 + 签名 + ID）
///   → 徽章行 → 五项数据（作品/喜欢/关注/粉丝/积分）→ 会员条
///   → 我的订单/卡券 → 我的服务宫格 → 智能服务条 → 两张活动卡 → 我的发布
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Post> _myPosts = [];
  UserProfile? _me;

  ProfilePageConfig _cfg = ProfilePageConfig.defaults;
  List<BadgeItem> _myBadges = [];
  List<BadgeItem> _allBadges = [];

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // 积分兑换 / 发布渔获后刷新资料（积分余额要跟着变）
    RefreshBus.profileTick.addListener(_onProfileTick);
    RefreshBus.feedTick.addListener(_onFeedTick);
    _loadConfig();
    _loadBadges();
  }

  @override
  void dispose() {
    RefreshBus.profileTick.removeListener(_onProfileTick);
    RefreshBus.feedTick.removeListener(_onFeedTick);
    _scroll.dispose();
    super.dispose();
  }

  void _onProfileTick() => _loadMe();

  void _onFeedTick() {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (sp.isLoggedIn || !ApiConfig.enabled) {
      _loadMyPosts();
      _loadBadges();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sp = Provider.of<SessionProvider>(context);
    // 已登录，或未配置后端（演示模式）都加载「我的发布」
    if (sp.isLoggedIn || !ApiConfig.enabled) _loadMyPosts();
    if (sp.isLoggedIn) _loadMe();
  }

  Future<void> _loadConfig() async {
    final cfg = await ProfileService.fetchConfig();
    if (mounted) setState(() => _cfg = cfg);
  }

  Future<void> _loadBadges() async {
    if (!ApiConfig.enabled) return;
    final r = await ProfileService.fetchBadges();
    if (!mounted) return;
    setState(() {
      _allBadges = r.all;
      _myBadges = r.mine;
    });
  }

  Future<void> _loadMe() async {
    try {
      final me = await FollowService.fetchMe();
      if (mounted) {
        setState(() {
          _me = me;
          if (me.badges.isNotEmpty) _myBadges = me.badges;
        });
      }
    } catch (_) {
      // 关注功能未启用：忽略，计数行不显示
    }
  }

  Future<void> _loadMyPosts() async {
    try {
      if (!ApiConfig.enabled) {
        if (mounted) setState(() => _myPosts = PostService.demoPosts);
        return;
      }
      // 直接按当前用户查询自己的全部未删除发布（带 is_me），仅用于「作品」
      // 统计项的兜底；「我的」页本身不再直接展示发布列表
      final posts = await PostService.fetchMyPosts();
      if (mounted) {
        setState(() => _myPosts = posts);
      }
    } catch (_) {
      // 统计兜底数据加载失败不影响主流程
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadMyPosts(), _loadMe(), _loadBadges(), _loadConfig()]);
  }

  // ============================================================
  // 跳转：后台配置里的 action → 具体页面
  // ============================================================
  void _runAction(String action) {
    switch (action) {
      case 'orders':
        _showOrdersSheet();
        return;
      case 'coupons':
        CenterToast.show(context, '卡券功能即将上线');
        return;
      case 'spots':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const SpotsScreen()));
        return;
      case 'mall':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const MallScreen()));
        return;
      case 'weather':
      case 'ai':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const WeatherScreen()));
        return;
      case 'badges':
        _showBadgesSheet();
        return;
      case 'vip':
        Navigator.of(context).pushNamed('/member-center');
        return;
      case 'wallet':
        // 钱包需要登录态校验，异步打开（不阻塞当前帧）
        WalletEntry.open(context);
        return;
      case 'fish':
        Navigator.of(context).pushNamed('/fish-guide');
        return;
      case 'nearby':
        Navigator.of(context).pushNamed('/nearby-anglers');
        return;
      case 'messages':
        Navigator.of(context).pushNamed('/message-center');
        return;
      case 'signin':
        Navigator.of(context).pushNamed('/signin');
        return;
      case 'following':
        _openFollowList(false);
        return;
      case 'followers':
        _openFollowList(true);
        return;
      case 'editProfile':
        _openEdit();
        return;
      case 'favorites':
        CenterToast.show(context, '收藏功能即将上线');
        return;
      case 'events':
        CenterToast.show(context, '活动中心即将上线');
        return;
      case 'notice':
        CenterToast.show(context, '暂无新消息');
        return;
      case 'settings':
        _openEdit();
        return;
      case 'help':
        CenterToast.show(context, '如遇问题请在「设置 → 帮助反馈」联系我们');
        return;
      default:
        return;
    }
  }

  void _openFollowList(bool followers) {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (!sp.isLoggedIn) {
      _goLogin();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FollowListScreen(
        userId: sp.userId ?? '',
        title: followers ? '粉丝' : '关注',
        followers: followers,
      ),
    ));
  }

  Future<void> _openEdit() async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (!sp.isLoggedIn) {
      _goLogin();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
    );
    _loadMe();
    _loadMyPosts();
  }

  void _openMyPosts() {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (!sp.isLoggedIn) {
      _goLogin();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyPostsScreen()),
    );
  }

  void _goLogin() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
  }

  /// 我的徽章：全部徽章 + 已获得高亮
  void _showBadgesSheet() {
    final badges = _allBadges.isNotEmpty ? _allBadges : _myBadges;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        final owned = _myBadges.map((e) => e.id).toSet();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('我的徽章',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    Text('已获得 ${_myBadges.length}/${badges.length}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
                const SizedBox(height: 14),
                if (badges.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 26),
                    child: Center(
                      child: Text('还没有配置徽章，去后台「徽章管理」添加吧',
                          style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                  )
                else
                  Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: badges.length,
                      itemBuilder: (_, i) {
                        final b = badges[i];
                        return _badgeTile(b, owned.contains(b.id));
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 我的订单（积分兑换 / 现金登记都在这）
  Future<void> _showOrdersSheet() async {
    final orders = await ShopService.fetchMyOrders();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('我的订单',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (orders.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text('暂无订单',
                        style: TextStyle(color: AppTheme.textSecondary)),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const Divider(height: 14),
                    itemBuilder: (_, i) {
                      final o = orders[i];
                      final isPoints = (o['type'] ?? '') == 'points';
                      final amount = (o['amount'] ?? '').toString();
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text((o['product_name'] ?? '商品').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 3),
                                Text(
                                  '${isPoints ? '积分兑换' : '现金购买'} · x${(o['quantity'] ?? 1)}'
                                  ' · ${(o['status_label'] ?? '').toString()}',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            isPoints ? '$amount 积分' : '¥$amount',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 组件
  // ============================================================

  /// 头像 + 昵称 + 会员标签 + 签名 + ID
  Widget _profileHeader(SessionProvider sp) {
    final vip = _me?.vip ?? MemberStyle.normal;
    final name = (sp.nickname ?? _me?.nickname ?? '钓友').trim();
    final bio = _me?.bio ?? '';
    final uid = sp.userId ?? _me?.id ?? '';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: AppTheme.lightShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _openEdit,
            child: UserAvatar(
              url: sp.avatarUrl,
              userId: sp.isLoggedIn ? sp.userId : null,
              radius: 34,
              member: vip,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name.isEmpty ? '钓友' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (vip.isVip) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          gradient:
                              LinearGradient(colors: [vip.color, vip.color2]),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${vip.levelLabel} ${vip.name}',
                          style: const TextStyle(
                              fontSize: 10,
                              height: 1.4,
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: _openEdit,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 26, minHeight: 26),
                      icon: const Icon(Icons.edit_outlined,
                          size: 15, color: AppTheme.textSecondary),
                      tooltip: '编辑资料',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  bio.isNotEmpty ? bio : '这个人很低调，还没有留下签名~',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.badge_outlined,
                        size: 12, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _me != null && _me!.userNo > 0
                            ? '我的ID：${_me!.userNo}'
                            : 'ID：${uid.isEmpty ? '—' : uid}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 徽章行：所获徽章 (n) + 图标
  Widget _badgeBar() {
    final show = _myBadges.take(6).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        boxShadow: AppTheme.lightShadow,
      ),
      child: InkWell(
        onTap: _showBadgesSheet,
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF8E7CF0), Color(0xFFB7A6FF)]),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.military_tech,
                  size: 13, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Text('所获徽章 (${_myBadges.length})',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (show.isEmpty)
              const Text('还没有徽章',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary))
            else
              ...show.map((b) => Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _badgeIcon(b, 20),
                  )),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 16, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  /// 五项数据：作品 / 喜欢 / 关注 / 粉丝 / 积分
  Widget _statsRow(SessionProvider sp) {
    final likeCount = _me?.likeCount ??
        _myPosts.fold<int>(0, (a, p) => a + p.likeCount);
    final items = <(String, String, VoidCallback?)>[
      ('作品', '${_me?.postCount ?? _myPosts.length}', () => _openMyPosts()),
      ('喜欢', '$likeCount', null),
      ('关注', '${_me?.followingCount ?? 0}', () => _openFollowList(false)),
      ('粉丝', '${_me?.followerCount ?? 0}', () => _openFollowList(true)),
      ('${_me?.pointsName ?? '积分'}', '${_me?.points ?? 0}',
          () => _runAction('mall')),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        boxShadow: AppTheme.lightShadow,
      ),
      child: Row(
        children: items.map((it) {
          return Expanded(
            child: InkWell(
              onTap: it.$3,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(it.$2,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 3),
                  Text(it.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppTheme.textSecondary)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 会员条：Lv + 等级名 + 会员中心
  Widget _memberBar() {
    final vip = _me?.vip ?? MemberStyle.normal;
    final c1 = vip.isVip ? vip.color : const Color(0xFF6E7F8D);
    final c2 = vip.isVip ? vip.color2 : const Color(0xFF9AA9B5);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [c1, c2],
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: () => _runAction('vip'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Text(
                vip.isVip ? vip.levelLabel : 'Lv0',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 6),
              Icon(Icons.workspace_premium,
                  size: 15, color: Colors.white.withOpacity(0.95)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  vip.isVip ? vip.name : '开通会员享专属权益',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Text(_cfg.memberBarText,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              const Icon(Icons.chevron_right, size: 16, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  /// 列表行（我的订单 / 我的卡券）
  Widget _menuCard() {
    if (_cfg.menus.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        boxShadow: AppTheme.lightShadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < _cfg.menus.length; i++) ...[
            if (i > 0)
              const Divider(
                  height: 1, thickness: 1, indent: 14, endIndent: 14,
                  color: AppTheme.divider),
            ListTile(
              dense: true,
              onTap: () => _runAction(_cfg.menus[i].action),
              leading: Icon(_iconOf(_cfg.menus[i].icon),
                  size: 19, color: AppTheme.primary),
              title: Text(_cfg.menus[i].title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right,
                  size: 18, color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  /// 我的服务宫格
  Widget _servicesCard() {
    if (_cfg.services.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        boxShadow: AppTheme.lightShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_cfg.servicesTitle,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (ctx, box) {
            const gap = 6.0;
            final n = _cfg.services.length.clamp(3, 5);
            final cell = (box.maxWidth - gap * (n - 1)) / n;
            return Wrap(
              spacing: gap,
              runSpacing: 12,
              children: _cfg.services.map((s) {
                return SizedBox(
                  width: cell,
                  child: InkWell(
                    onTap: () => _runAction(s.action),
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      children: [
                        Icon(_iconOf(s.icon),
                            size: 22, color: AppTheme.primary),
                        const SizedBox(height: 6),
                        Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 11.5, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          }),
        ],
      ),
    );
  }

  /// 智能服务条
  Widget _smartBar() {
    final s = _cfg.smartBar;
    if (s.title.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.primaryBorder),
      ),
      child: InkWell(
        onTap: () => _runAction(s.action),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 17, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(s.title,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryDark)),
            if (s.desc.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                  width: 1,
                  height: 11,
                  color: AppTheme.primaryBorder),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.desc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.textSecondary),
                ),
              ),
            ] else
              const Spacer(),
            const Icon(Icons.chevron_right,
                size: 17, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  /// 底部两张活动卡
  Widget _cardsRow() {
    if (_cfg.cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _cfg.cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _activityCard(_cfg.cards[i])),
          ],
        ],
      ),
    );
  }

  Widget _activityCard(ProfileCardItem c) {
    return InkWell(
      onTap: () => _runAction(c.action),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          boxShadow: AppTheme.lightShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
                const Icon(Icons.chevron_right,
                    size: 16, color: AppTheme.textSecondary),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              c.desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${c.button}  »',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 徽章图标（图片 / emoji 两种后台配置都支持）
  Widget _badgeIcon(BadgeItem b, double size) {
    if (b.isImage) {
      return Image.network(
        b.icon.startsWith('/') ? ApiConfig.mediaUrl(b.icon) ?? b.icon : b.icon,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _badgeFallback(b, size),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          b.icon.isEmpty ? '🎖' : b.icon,
          style: TextStyle(fontSize: size * 0.86),
        ),
      ),
    );
  }

  Widget _badgeFallback(BadgeItem b, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.primarySoft,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Icon(Icons.military_tech,
            size: size * 0.62, color: AppTheme.primary),
      );

  /// 徽章格子（弹层里用）：未获得的置灰
  Widget _badgeTile(BadgeItem b, bool owned) {
    return Opacity(
      opacity: owned ? 1 : 0.4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _badgeIcon(b, 34),
          const SizedBox(height: 5),
          Text(
            b.shortLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 1),
          Text(
            b.conditionText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 9, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 后台配置的图标 key → Material 图标
  IconData _iconOf(String key) {
    switch (key) {
      case 'order':
        return Icons.receipt_long_outlined;
      case 'coupon':
        return Icons.confirmation_num_outlined;
      case 'fish':
        return Icons.phishing;
      case 'trophy':
        return Icons.emoji_events_outlined;
      case 'heart':
        return Icons.favorite_border;
      case 'follow':
        return Icons.person_add_alt_1_outlined;
      case 'medal':
        return Icons.military_tech_outlined;
      case 'service':
        return Icons.support_agent;
      case 'setting':
        return Icons.settings_outlined;
      case 'vip':
        return Icons.workspace_premium_outlined;
      case 'spot':
        return Icons.place_outlined;
      case 'weather':
        return Icons.wb_sunny_outlined;
      case 'mall':
        return Icons.storefront_outlined;
      case 'ai':
        return Icons.auto_awesome_outlined;
      case 'event':
        return Icons.event_outlined;
      case 'map':
        return Icons.map_outlined;
      case 'shield':
        return Icons.verified_user_outlined;
      case 'camera':
        return Icons.photo_camera_outlined;
      case 'notice':
        return Icons.notifications_none;
      case 'help':
        return Icons.help_outline;
      case 'wallet':
        return Icons.account_balance_wallet_outlined;
      default:
        return Icons.star_border;
    }
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
                onPressed: _goLogin,
                child: const Text('登录 / 注册'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
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
              onPressed: _openEdit,
            ),
          if (sp.isLoggedIn)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: '退出登录',
              onPressed: () async {
                await sp.signOut();
                setState(() {
                  _myPosts = [];
                  _myBadges = [];
                  _me = null;
                });
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _profileHeader(sp),
            _badgeBar(),
            _statsRow(sp),
            _memberBar(),
            _menuCard(),
            _servicesCard(),
            _smartBar(),
            _cardsRow(),
          ],
        ),
      ),
    );
  }
}
