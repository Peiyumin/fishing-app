import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/badge.dart';
import '../models/fish.dart';
import '../models/member.dart';
import '../models/post.dart';
import '../models/profile_config.dart';
import '../models/user_profile.dart';
import '../services/api_config.dart';
import '../services/fish_service.dart';
import '../services/follow_service.dart';
import '../services/geo_place.dart';
import '../services/location_service.dart';
import '../services/post_service.dart';
import '../services/profile_service.dart';
import '../services/refresh_bus.dart';
import '../services/session_provider.dart';
import '../widgets/center_toast.dart';
import '../widgets/ui_kit.dart';
import '../widgets/fish_dex_card.dart';
import '../utils/county_label.dart';
import '../widgets/user_avatar.dart';
import 'auth_screen.dart';
import 'edit_profile_screen.dart';
import 'follow_list_screen.dart';
import 'mall_screen.dart';
import 'my_orders_screen.dart';
import 'spots_screen.dart';
import 'wallet_screen.dart';
import 'weather_screen.dart';
import 'my_posts_screen.dart';
import 'settings_screen.dart';
import '../widgets/app_refresh.dart';
import '../utils/json_num.dart';

/// 我的页
///
/// 版面顺序（都能在后台「我的页配置」里改标题/图标/跳转）：
///   资料头（头像会员框 + 昵称 + 会员标签 + 签名 + ID）
///   → 徽章行 → 五项数据（作品/喜欢/关注/粉丝/积分）→ 会员条
///   → 我的订单/卡券 → 我的服务宫格 → 智能服务条 → 两张活动卡 → 我的发布
class ProfileScreen extends StatefulWidget {
  const ProfileScreen(
      {super.key, this.debugMe, this.debugRegPlace, this.debugCover});

  /// 截图/测试用：直接给一份资料，省掉网络请求。
  /// 线上永远为 null，走的还是 `_loadMe()` 那条真实链路。
  final UserProfile? debugMe;

  /// 截图/测试用：直接给一个注册地文案（线上为 null）
  final String? debugRegPlace;

  /// 截图/测试用：直接给一张封面（线上为 null，走 CachedNetworkImage）
  final Widget? debugCover;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Post> _myPosts = [];
  UserProfile? _me;

  /// 注册地（v2.1.57）：优先后端记录，没有就按当前定位补一份
  String _regPlace = '';

  ProfilePageConfig _cfg = ProfilePageConfig.defaults;
  FishGuide _guide = FishService.fallback;
  List<BadgeItem> _myBadges = [];
  List<BadgeItem> _allBadges = [];

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.debugMe != null) _me = widget.debugMe;
    if (widget.debugMe?.badges.isNotEmpty == true) {
      _myBadges = widget.debugMe!.badges;
    }
    if (widget.debugRegPlace != null) _regPlace = widget.debugRegPlace!;
    // 积分兑换 / 发布渔获后刷新资料（积分余额要跟着变）
    RefreshBus.profileTick.addListener(_onProfileTick);
    RefreshBus.feedTick.addListener(_onFeedTick);
    _loadConfig();
    _loadBadges();
    _loadGuide();
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
      // 发布渔获可能点亮了新的鱼种，档案卡要跟着变
      _loadGuide();
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
    // 截图/测试传进来的资料自带徽章，别再让网络结果覆盖成空
    if (widget.debugMe != null) return;
    if (!ApiConfig.enabled) return;
    final r = await ProfileService.fetchBadges();
    if (!mounted) return;
    setState(() {
      _allBadges = r.all;
      _myBadges = r.mine;
    });
  }

  Future<void> _loadGuide() async {
    if (!ApiConfig.enabled) return;
    try {
      final g = await FishService.guide();
      if (mounted) setState(() => _guide = g);
    } catch (_) {
      // 图鉴接口不可用时用内置 fallback，档案卡照常显示（全未点亮）
    }
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
    await _loadRegPlace();
  }

  /// 注册地：后端的 regPlace 优先；空的话（老账号 / 未升级后端）就用当前
  /// 定位补一个，并且只显示不强行写库 —— 写库那条路在 SessionProvider 里，
  /// 服务端只在 reg_place 为空时接受。
  Future<void> _loadRegPlace() async {
    final saved = _me?.regPlace ?? '';
    if (saved.isNotEmpty) {
      if (mounted && saved != _regPlace) setState(() => _regPlace = saved);
      return;
    }
    if (_regPlace.isNotEmpty) return;
    try {
      if (!await LocationService.hasPermission()) return;
      final p = await GeoPlace.current();
      if (p == null || p.isEmpty) return;
      final place = countyLabel(
        city: p.city,
        district: p.district,
        province: p.province,
        withProvince: true,
      );
      if (mounted && place.isNotEmpty) setState(() => _regPlace = place);
    } catch (_) {
      // 定位失败就不显示这一行，不编地名
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
    await Future.wait(
        [_loadMyPosts(), _loadMe(), _loadBadges(), _loadConfig(), _loadGuide()]);
  }

  // ============================================================
  // 跳转：后台配置里的 action → 具体页面
  // ============================================================
  void _runAction(String action) {
    switch (action) {
      case 'orders':
        _openOrders();
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
      case 'notify':
        Navigator.of(context).pushNamed('/notify-settings');
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

  /// 打开设置页（退出登录在设置页底部）
  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openMyPosts() {    final sp = Provider.of<SessionProvider>(context, listen: false);
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

  /// 我的订单：跳完整订单页（状态筛选 / 商品图 / 取消 / 确认收货 / 详情）
  void _openOrders() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const MyOrdersScreen()));
  }

  // ============================================================
  // 组件
  // ============================================================

  /// 头像 + 昵称 + 会员标签 + 签名 + 定位 · ID
  ///
  /// v2.1.59 重排。旧版把「昵称 + LV + 会员胶囊 + 编辑图标」全塞在一行，
  /// 393pt 屏上昵称只剩 5 个字就被省略号吃掉；定位和 ID 又各占一整行、
  /// 都是 11.5 号灰字，四行小字堆在签名下面像说明书。
  ///
  /// 现在的几何（封面用 Stack 背景层，不占 Column 的第一行）：
  ///   封面可见高 200 → 头像 top = 200-32 = 168（压住下沿 32）
  ///   → 昵称/胶囊/签名/元信息 的 top 也是 168（与头像顶齐，不再掉到下方）
  ///   → 卡片底 = 168 + max(头像 78, 文字列) + 16
  /// 文字列左缩进 = 14 + 头像 78 + 12 = 104，昵称可用宽度 ≈ 250pt（旧版 ≈120）
  Widget _profileHeader(SessionProvider sp) {
    final vip = _me?.vip ?? MemberStyle.normal;
    final name = (sp.nickname ?? _me?.nickname ?? '钓友').trim();
    final bio = _me?.bio ?? '';
    final uid = sp.userId ?? _me?.id ?? '';
    final cover = sp.coverUrl ?? _me?.cover;
    final hasCover =
        widget.debugCover != null || (cover != null && cover.isNotEmpty);

    // v2.1.60：132 → 248。原来只是一道 132 高的窄条（宽高比 2.66:1），
    // 竖图被裁掉大半，看着「背景只显示了一半」；加高后是一整张图的量感，
    // 底部靠 130pt 长的渐变慢慢化进卡片白底。
    // v2.1.61：248 → 200。用户反馈「背景图太高、一进页面半屏都是图」，
    // 收低 48pt，头像仍然压住下沿 32，读起来还是「一张图的量感」。
    const coverH = 200.0;
    const avatarR = 36.0;
    final meta = _metaLine(uid);

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppTheme.pagePad, 10, AppTheme.pagePad, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: AppTheme.softShadow,
      ),
      child: Stack(
        children: [
          // ① 封面：只做背景，不参与高度计算
          if (hasCover)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: coverH,
              child: _coverBand(sp, height: coverH),
            ),
          // ② 正文：先让出「封面-压边量」，再从头像顶开始
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: hasCover ? coverH - 32 : 0),
              Padding(
                padding: EdgeInsets.fromLTRB(14, hasCover ? 0 : 14, 14, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 头像（白色外圈，压在封面上也有边界）
                    GestureDetector(
                      onTap: _openEdit,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: UserAvatar(
                          url: sp.avatarUrl,
                          userId: sp.isLoggedIn ? sp.userId : null,
                          radius: avatarR,
                          member: vip,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 昵称独占一行 + 编辑
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name.isEmpty ? '钓友' : name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    height: 1.25,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _editDot(),
                            ],
                          ),
                          const SizedBox(height: 9),
                          // 等级 / 会员（等高胶囊）
                          Row(
                            children: [
                              _pill(
                                'LV${_me?.level ?? 1}',
                                bg: AppTheme.primary,
                                fg: AppTheme.accent,
                              ),
                              if (vip.isVip) ...[
                                const SizedBox(width: 6),
                                _pill(
                                  '${vip.levelLabel} ${vip.name}',
                                  gradient: LinearGradient(
                                      colors: [vip.color, vip.color2]),
                                  fg: Colors.white,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 11),
                          Text(
                            bio.isNotEmpty ? bio : '这个人很低调，还没有留下签名~',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          if (meta.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(Icons.place_outlined,
                                    size: 13, color: AppTheme.textTertiary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    meta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.textTertiary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 定位 · ID 合并文案（定位拿不到就说「定位未开启」，ID 拿不到就不写）
  String _metaLine(String uid) {
    final place = _regPlace.isNotEmpty ? _regPlace : '定位未开启';
    if (_me != null && _me!.userNo > 0) return '$place · ID ${_me!.userNo}';
    if (uid.isEmpty) return place;
    return '$place · ID $uid';
  }

  /// 28×28 的浅灰圆角编辑块（比裸铅笔图标好点，也比 IconButton 省空间）
  Widget _editDot() {
    return InkWell(
      onTap: _openEdit,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.primaryLight,
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Icon(Icons.edit_outlined,
            size: 14, color: AppTheme.textSecondary),
      ),
    );
  }

  /// 等高等级胶囊：高 18、圆角 6、10 号字，保证两枚并排时基线一致
  Widget _pill(
    String text, {
    Color? bg,
    Gradient? gradient,
    required Color fg,
  }) {
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        gradient: gradient,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          height: 1.0,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: fg,
        ),
      ),
    );
  }

  /// 主页背景图（v2.1.56，v2.1.59 改胶囊描边）
  ///
  /// 没设置过就保持纯白卡面（不硬塞一张渐变图，避免所有用户长得一样）；
  /// 设置过就把图铺满这一条，底部渐隐到卡片白底，头像压在图的下沿。
  Widget _coverBand(SessionProvider sp, {required double height}) {
    final cover = sp.coverUrl ?? _me?.cover;
    final has = widget.debugCover != null || (cover != null && cover.isNotEmpty);
    if (!has || height <= 0) {
      return const SizedBox(height: 0, width: double.infinity);
    }
    // 同一张图要画两层（清晰层 + 模糊层），做成工厂避免复用同一个 widget 实例
    Widget img() =>
        widget.debugCover ??
        CachedNetworkImage(
          imageUrl: cover ?? '',
          fit: BoxFit.cover,
          placeholder: (_, __) => _coverFallback(),
          errorWidget: (_, __, ___) => _coverFallback(),
        );
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ① 原图铺满整块封面
          ClipRect(child: img()),
          // ② 下半部叠一层同源的重度虚化：越往下越糊。
          //    和清晰层同图同 fit，模糊层永远对得上，不会出现错位接缝；
          //    ShaderMask 用竖向渐变把模糊层「擦」出来，接缝是渐变的不是硬边。
          //    起点 0.42：上半张保持清晰，只在往下走的时候开始虚。
          ClipRect(
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.white],
                stops: [0.38, 0.92],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                    sigmaX: 12, sigmaY: 12, tileMode: TileMode.clamp),
                child: img(),
              ),
            ),
          ),
          // ③ 长渐变淡出到卡片白底：0 → 52% 完全透明，82% 处 62% 白，97% 起纯白。
          //    图是一路「化掉」的，不是被一刀切平；同时给压在封面上的
          //    头像、昵称、签名垫了一层白纱，浅色深色封面都读得清。
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppTheme.surface.withOpacity(0.08),
                  AppTheme.surface.withOpacity(0.66),
                  AppTheme.surface,
                ],
                stops: const [0.0, 0.58, 0.86, 0.98],
              ),
            ),
          ),
          // 「换背景」：黑 0.30 + 白 0.28 描边 —— 亮封面、暗封面都能看清边界
          Positioned(
            right: 12,
            top: 12,
            child: Material(
              color: Colors.black.withOpacity(0.30),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.28)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _openEdit,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.wallpaper, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text('换背景',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                height: 1.0,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 封面加载中 / 加载失败时的兜底：品牌深色渐变 + 两个极淡光斑
  ///
  /// 原来是 `primaryLight` 一片浅灰 ——「我的」页第一眼就是一块没加载出来的
  /// 灰。改成有意图的深色底：弱网、图挂了也像一张设计好的封面，
  /// 而且深底上白色的「换背景」胶囊和头像白圈都更清楚。
  Widget _coverFallback() {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              // 深色面板的两档现成 token（不新增色板外颜色）
              colors: [AppTheme.inkSurface, AppTheme.inkLine],
            ),
          ),
        ),
        Positioned(
          right: -34,
          top: -46,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accent.withOpacity(0.10),
            ),
          ),
        ),
        Positioned(
          left: -26,
          bottom: -64,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.05),
            ),
          ),
        ),
      ],
    );
  }

  /// 徽章条（v2.1.59）：标题 + 数量胶囊，右侧每个徽章套 28×28 浅灰底
  ///
  /// 旧版把 4 个 emoji 直接摊在白卡上 —— 大小不一、基线不齐，看着像没排过。
  /// emoji 本身不能改尺寸，所以统一给它们一个容器，靠容器对齐。
  Widget _badgeBar() {
    final show = _myBadges.take(5).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppTheme.pagePad, AppTheme.cardGap, AppTheme.pagePad, 0),
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        boxShadow: AppTheme.lightShadow,
      ),
      child: InkWell(
        onTap: _showBadgesSheet,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // 徽章入口：近黑底 + 荧光黄绿奖章（品牌唯一彩色）
                gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.inkLine]),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.military_tech,
                  size: 14, color: AppTheme.accent),
            ),
            const SizedBox(width: 8),
            const Text('所获徽章',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Container(
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_myBadges.length}',
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const Spacer(),
            if (show.isEmpty)
              const Text('还没有徽章',
                  style: TextStyle(
                      fontSize: 11.5, color: AppTheme.textTertiary))
            else
              ...show.map((b) => Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.primarySoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _badgeIcon(b, 19),
                    ),
                  )),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right,
                size: 16, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }

  /// 五项数据：作品 / 喜欢 / 关注 / 粉丝 / 积分
  ///
  /// v2.1.59：数字改**等宽数字**（tabular figures）——「1134」这种四位数
  /// 和「1」用同一套字宽，五列的数字才会落在同一条视觉线上；列间补 1pt
  /// 竖线（divider 色、22 高），五列从「五个数字漂着」变成一条数据栏。
  Widget _statsRow(SessionProvider sp) {
    final likeCount =
        _me?.likeCount ?? _myPosts.fold<int>(0, (a, p) => a + p.likeCount);
    final items = <(String, String, VoidCallback?)>[
      ('作品', '${_me?.postCount ?? _myPosts.length}', () => _openMyPosts()),
      ('喜欢', '$likeCount', null),
      ('关注', '${_me?.followingCount ?? 0}', () => _openFollowList(false)),
      ('粉丝', '${_me?.followerCount ?? 0}', () => _openFollowList(true)),
      ('${_me?.pointsName ?? '积分'}', '${_me?.points ?? 0}',
          () => _runAction('wallet')),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppTheme.pagePad, AppTheme.cardGap, AppTheme.pagePad, 0),
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        boxShadow: AppTheme.lightShadow,
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(
                  key: ValueKey('stats-sep-$i'),
                  width: 1,
                  height: 22,
                  color: AppTheme.divider),
            Expanded(
              child: InkWell(
                onTap: items[i].$3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      items[i].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      items[i].$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 会员条（v2.1.59）
  ///
  /// 会员态沿用后台下发的等级渐变（不新增色相）；非会员态改用品牌
  /// 近黑 → 石墨渐变 + 荧光黄绿文字 —— 原来那条「浅灰 → 更浅灰」的
  /// 渐变在白卡上像一块没加载出来的占位。
  ///
  /// 结构：圆形图标底 → Lv → 等级名 →（右侧）「会员中心」胶囊 + 箭头
  Widget _memberBar() {
    final vip = _me?.vip ?? MemberStyle.normal;
    final c1 = vip.isVip ? vip.color : AppTheme.primary;
    final c2 = vip.isVip ? vip.color2 : AppTheme.inkSurface;
    final fg = vip.isVip ? Colors.white : AppTheme.accent;
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppTheme.pagePad, AppTheme.cardGap, AppTheme.pagePad, 0),
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [c1, c2],
        ),
        boxShadow: vip.isVip
            ? [
                BoxShadow(
                  color: vip.color.withOpacity(0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          // 顶部一道极淡高光，让整条从「一块色」变成「一块有厚度的牌」
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.13),
                    Colors.transparent
                  ],
                  stops: const [0.0, 0.70],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: InkWell(
              onTap: () => _runAction('vip'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.workspace_premium, size: 15, color: fg),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      vip.isVip ? vip.levelLabel : 'Lv0',
                      style: TextStyle(
                          color: fg,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        vip.isVip ? vip.name : '开通会员享专属权益',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: fg.withOpacity(0.95),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 右侧 CTA 收成小胶囊，和左边的等级信息分出主次
                    Container(
                      padding:
                          const EdgeInsets.fromLTRB(10, 5, 6, 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.18)),
                      ),
                      child: Row(
                        children: [
                          Text(_cfg.memberBarText,
                              style: TextStyle(
                                  color: fg,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600)),
                          Icon(Icons.chevron_right, size: 14, color: fg),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 列表行（我的订单 / 我的卡券）
  Widget _menuCard() {
    if (_cfg.menus.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppTheme.pagePad, AppTheme.cardGap, AppTheme.pagePad, 0),
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
            InkWell(
              onTap: () => _runAction(_cfg.menus[i].action),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  children: [
                    Icon(_iconOf(_cfg.menus[i].icon),
                        size: 19, color: AppTheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_cfg.menus[i].title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 17, color: AppTheme.textTertiary),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 累计渔获（尾）：把已加载的渔获帖里的鱼条数加起来
  int get _totalCatches {
    var n = 0;
    for (final p in _myPosts) {
      if (!p.isCatch) continue;
      for (final f in p.fish) {
        n += jsonInt(f['count']) ?? 1;
      }
      // 没有记鱼种的老帖子，按 1 条算
      if (p.fish.isEmpty) n += 1;
    }
    return n;
  }

  /// 本月出钓次数：按本月渔获帖的日期去重
  int get _monthTrips {
    final now = DateTime.now();
    final days = <String>{};
    for (final p in _myPosts) {
      if (!p.isCatch) continue;
      final t = p.createdAt;
      if (t.year == now.year && t.month == now.month) {
        days.add('${t.year}-${t.month}-${t.day}');
      }
    }
    return days.length;
  }

  /// 钓鱼档案卡（图三）：图鉴进度 + 三个统计 + 拍一条投入池塘 / 我的池塘
  Widget _fishDexCard() {
    return FishDexCard(
      guide: _guide,
      totalCatches: _totalCatches,
      monthTrips: _monthTrips,
      onOpenDex: () => Navigator.of(context).pushNamed('/fish-guide'),
      onSnap: () => Navigator.of(context).pushNamed('/fish-guide'),
      onOpenTank: () => Navigator.of(context).pushNamed('/fish-tank'),
    );
  }

  /// 我的服务宫格
  Widget _servicesCard() {
    if (_cfg.services.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppTheme.pagePad, AppTheme.cardGap, AppTheme.pagePad, 0),
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
            final per = n > 5 ? 5 : n;
            final cell = (box.maxWidth - gap * (per - 1)) / per;
            final rows = <Widget>[];
            for (var i = 0; i < _cfg.services.length; i += per) {
              final end = i + per > _cfg.services.length
                  ? _cfg.services.length
                  : i + per;
              final slice = _cfg.services.sublist(i, end);
              rows.add(Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var k = 0; k < slice.length; k++) ...[
                      if (k > 0) const SizedBox(width: gap),
                      SizedBox(width: cell, child: _serviceItem(slice[k])),
                    ],
                  ],
                ),
              ));
            }
            return Column(children: rows);
          }),
        ],
      ),
    );
  }

  /// 服务宫格里的一个小格（图标 + 一行标题）
  Widget _serviceItem(ProfileItem s) {
    return InkWell(
      onTap: () => _runAction(s.action),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        children: [
          Icon(_iconOf(s.icon), size: 22, color: AppTheme.primary),
          const SizedBox(height: 6),
          Text(
            s.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }

  /// 智能服务条
  Widget _smartBar() {
    final s = _cfg.smartBar;
    if (s.title.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppTheme.pagePad, AppTheme.cardGap, AppTheme.pagePad, 0),
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
      padding: const EdgeInsets.fromLTRB(
          AppTheme.pagePad, AppTheme.cardGap, AppTheme.pagePad, 0),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    c.button,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary),
                  ),
                  const SizedBox(width: 1),
                  const Icon(Icons.chevron_right,
                      size: 13, color: AppTheme.primary),
                ],
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
        // 原来 icon 为空时兜底写死 '🎖'，设备没有彩色 emoji 字体就是方块
        child: b.icon.isEmpty
            ? Icon(Icons.military_tech,
                size: size * 0.86, color: AppTheme.textSecondary)
            : Text(
                b.icon,
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
      case 'bell':
        return Icons.notifications_active_outlined;
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
        appBar: AppBar(title: const Text('我的')),
        body: Center(
          child: UiEmptyState(
            icon: Icons.person_outline,
            title: '登录后查看你的渔获与收藏',
            desc: '渔获、徽章、关注和钓鱼档案都在这里',
            actionLabel: '登录 / 注册',
            onAction: _goLogin,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          // 顶部只留一个「设置」入口：编辑资料已经挪进「点头像/资料卡」和设置页，
          // 退出登录也挪进设置页底部（原来两个图标挤在一起容易误点）
          if (sp.isLoggedIn)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: '设置',
              onPressed: _openSettings,
            ),
        ],
      ),
      body: AppRefresh(
        onRefresh: _refreshAll,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _profileHeader(sp),
            _badgeBar(),
            _statsRow(sp),
            _memberBar(),
            _fishDexCard(),
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
