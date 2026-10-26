import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_theme.dart';
import '../widgets/emoji_panel.dart';
import 'package:provider/provider.dart';

import '../models/badge.dart';
import '../models/fishing_species.dart';
import '../models/post.dart';
import '../models/weather_forecast.dart';
import '../services/api_config.dart';
import '../services/badge_hub.dart';
import '../services/post_service.dart';
import '../services/session_provider.dart';
import '../services/weather_service.dart';
import '../widgets/post_video_player.dart';
import '../widgets/user_avatar.dart';
import 'auth_screen.dart';
import 'user_profile_screen.dart';
import 'publish_catch_screen.dart';
import 'fish_guide_screen.dart';
import '../services/refresh_bus.dart';
import '../widgets/center_toast.dart';
import '../widgets/follow_button.dart';

// ─────────────────────────────────────────────────────────────
// 渔获详情页（v2.1.34 按参考稿重做）
//
// 版式：沉浸封面（图上叠鱼种/数量 + 图鉴入口）→ 图集 → 作者卡 →
// 水质气象三连 → 互动数据 → 钓友们说 → 正文 → 场景标签 →
// 钓点卡 → CATCH INDEX → 评论 → 底部快捷贴纸 + 输入框
//
// 配色一律用 App 主色（深绿 #0F7A53 / 墨绿卡片 / 亮绿高亮），
// 不照搬参考稿的黑黄配色。
// ─────────────────────────────────────────────────────────────

/// 深色卡片底：**中性近黑**（设计稿的深色只用一个色相，不再带墨绿调）
/// v2.1.36：不再自己定一套黑 —— 直接引用 [AppTheme.ink*]，
/// 否则详情页是 #0B0E13 / 天气页是 #07080C，同一部手机里两种深底。
const _ink = AppTheme.inkBg;
const _inkCell = AppTheme.inkSurface;
const _inkLine = AppTheme.inkLine;

/// 高亮：荧光黄绿（深底上唯一的彩色，用于大数字/进度）
const _hi = AppTheme.inkHi;
/// 次高亮：同色系的暗一档（和天气页刻度条的「半满」同一值）
const _hiDim = AppTheme.accentMid;

/// 动态详情：渔获详情页
class PostDetailScreen extends StatefulWidget {
  final Post post;
  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late Post _post;
  List<Map<String, dynamic>> _comments = [];
  final _ctrl = TextEditingController();
  bool _loading = true;

  /// 作者关注状态（详情页作者行右侧「关注」，交给 FollowButton 维护）
  bool _following = false;

  // ── 天气 / 水质 / 指数（和天气页、首页同一个引擎，分数保证一致）
  HourPoint? _hour;
  WaterMetrics? _wm;
  FishingWeather? _fw;
  bool _wxDone = false;

  /// 滚动位置：滚过封面后顶部要浮出「作者条」（参考稿就是这个交互）
  final _scroll = ScrollController();
  final _offVN = ValueNotifier<double>(0);
  double _coverH = 360;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _following = widget.post.isFollowing;
    _loadComments();
    _trackView();
    _loadWeather();
    _scroll.addListener(() {
      _offVN.value = _scroll.hasClients ? _scroll.offset : 0;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _offVN.dispose();
    super.dispose();
  }

  /// 拉「这个钓点」的天气包 → 水温/水氧/指数据此推导
  ///
  /// 帖子里有经纬度就按钓点拉；没有就用当前定位的缓存包（首页已经拉过）。
  /// 全程静默：拿不到就整块显示「—」，绝不编数字。
  Future<void> _loadWeather() async {
    try {
      WeatherBundle? b;
      final lat = _post.lat, lng = _post.lng;
      if (lat != null && lng != null) {
        b = await WeatherService.fetchForecast(lat, lng);
      } else {
        b = await WeatherService.readCachedForecast();
      }
      final bundle = b;
      if (bundle == null || bundle.hours.isEmpty) {
        if (mounted) setState(() => _wxDone = true);
        return;
      }
      final i = bundle.indexOfCurrentHour(DateTime.now());
      final metrics = WaterMetrics.derive(bundle.hours);
      final fw = FishingWeather.fromBundle(bundle);
      if (!mounted) return;
      setState(() {
        _hour = (i >= 0 && i < bundle.hours.length) ? bundle.hours[i] : null;
        _wm = (i >= 0 && i < metrics.length) ? metrics[i] : null;
        _fw = fw;
        _wxDone = true;
      });
    } catch (_) {
      if (mounted) setState(() => _wxDone = true);
    }
  }

  /// 编辑自己的动态：进入发布页（预填），返回 true 表示已保存，回列表刷新
  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PublishCatchScreen(existing: _post),
      ),
    );
    if (updated == true && mounted) {
      RefreshBus.bumpFeed();
      Navigator.of(context).pop(true);
    }
  }

  /// 删除自己的动态（后端二次校验作者身份）
  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除动态'),
        content: const Text('确定删除这条动态吗？删除后他人与自己的列表都不再显示，且无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await PostService.deletePost(_post.id);
      if (!mounted) return;
      RefreshBus.bumpFeed();
      CenterToast.show(context, '已删除');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) CenterToast.show(context, '删除失败：$e');
    }
  }

  /// 浏览量 +1（热门/推荐算法依据；失败静默）
  Future<void> _trackView() async {
    try {
      await PostService.trackView(_post.id);
      if (mounted) {
        setState(() => _post = _post.copyWith(viewCount: _post.viewCount + 1));
      }
    } catch (_) {
      // 埋点失败不影响阅读
    }
  }

  Future<void> _loadComments() async {
    try {
      final c = await PostService.fetchComments(_post.id);
      if (mounted) setState(() => _comments = c);
    } catch (_) {
      // 断网 / 服务端没响应时不要把异常抛到 UI 层（会红屏），
      // 评论区安静地显示「还没有评论」即可，用户下拉还能重试。
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send([String? preset]) async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (!sp.isLoggedIn) {
      // 未登录直接带去登录页，登录回来还能接着评
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      return;
    }
    final text = (preset ?? _ctrl.text).trim();
    if (text.isEmpty) return;
    try {
      await PostService.addComment(_post.id, text);
      _ctrl.clear();
      setState(
          () => _post = _post.copyWith(commentCount: _post.commentCount + 1));
      await _loadComments();
    } catch (e) {
      if (!mounted) return;
      CenterToast.show(context, '评论失败：$e');
    }
  }

  bool _likeBusy = false;

  /// 点赞 / 取消点赞（未登录先去登录）
  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (!sp.isLoggedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      return;
    }
    setState(() => _likeBusy = true);
    try {
      final nowLiked = await PostService.toggleLike(_post.id, _post.likedByMe);
      if (!mounted) return;
      setState(() {
        _post = _post.copyWith(
          likedByMe: nowLiked,
          likeCount: _post.likeCount + (nowLiked ? 1 : -1),
        );
      });
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, '操作失败：$e');
      }
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  // ══════════════════════ 数据小工具 ══════════════════════

  String get _authorName =>
      (_post.username ?? '').trim().isNotEmpty ? _post.username! : '钓友';

  /// 主鱼种：优先渔获第一条，其次标题
  String get _mainFish {
    if (_post.fish.isNotEmpty) {
      final n = (_post.fish.first['name'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    }
    final t = _post.displayTitle.trim();
    return t.isEmpty ? '渔获' : t;
  }

  /// 封面副行大字：没有长度/重量字段，就用「条数 + 鱼种数」——
  /// 结构和大字+小单位一致，但不编造 cm/kg。
  String get _bigNum => '${_post.catchTotal <= 0 ? 1 : _post.catchTotal}';
  String get _bigUnit => '尾';
  String get _bigNum2 => '${_post.fish.isEmpty ? 1 : _post.fish.length}';
  String get _bigUnit2 => '种';

  /// 时段文案（上午 / 下午 / 傍晚 / 夜里）
  String get _dayPart {
    final h = _post.createdAt.hour;
    if (h >= 5 && h < 11) return '上午';
    if (h >= 11 && h < 14) return '中午';
    if (h >= 14 && h < 18) return '下午';
    if (h >= 18 && h < 21) return '傍晚';
    return '夜里';
  }

  static const _dirs = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
  String _windDir(int deg) => _dirs[(((deg % 360) / 45).round()) % 8];

  String _tempMood(double t) {
    if (t <= 5) return '寒冷';
    if (t <= 12) return '偏冷';
    if (t <= 20) return '凉爽';
    if (t <= 27) return '温暖';
    if (t <= 32) return '偏热';
    return '炎热';
  }

  /// 指数分级文案（和天气页同一套口径）
  String get _indexLabel => _fw?.fishIndex.isNotEmpty == true
      ? _fw!.fishIndex
      : (_wxDone ? '—' : '统计中');

  // ══════════════════════ 封面 ══════════════════════

  Widget _cover() {
    final w = MediaQuery.of(context).size.width;
    final h = (w * .92).clamp(240.0, 480.0);
    _coverH = h;
    final top = MediaQuery.of(context).padding.top;
    final img = _post.imageUrls.isNotEmpty ? _post.imageUrls.first : null;
    final cover = _post.isVideo && _post.videoUrl != null;

    return SizedBox(
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover)
            PostVideoPlayer(url: _post.videoUrl!, height: h)
          else if (img != null)
            CachedNetworkImage(
              imageUrl: img,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, __) =>
                  const ColoredBox(color: AppTheme.primarySoft),
              errorWidget: (_, __, ___) => const ColoredBox(
                color: AppTheme.primarySoft,
                child: Center(
                  child: Icon(Icons.broken_image_outlined,
                      size: 32, color: AppTheme.textSecondary),
                ),
              ),
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(gradient: AppTheme.brandGradient),
            ),

          // 顶部压暗：白字压在亮照片上也读得清
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: top + 70,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
          // 底部压暗：标题/数量
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: h * .46,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC07080C)],
                ),
              ),
            ),
          ),

          // 返回 / 更多
          Positioned(
            left: 10,
            top: top + 4,
            child: Row(
              children: [
                _circleBtn(Icons.arrow_back_ios_new_rounded, () {
                  Navigator.of(context).maybePop();
                }),
                const SizedBox(width: 6),
                if (_post.isMe) ...[
                  _circleBtn(Icons.edit_outlined, _edit),
                  const SizedBox(width: 6),
                  _circleBtn(Icons.delete_outline, _delete),
                ],
              ],
            ),
          ),
          if (!_post.isMe)
            Positioned(
              right: 12,
              top: top + 4,
              child: _circleBtn(Icons.more_horiz_rounded, _showMore),
            ),

          // 标题 + 数量 + 图鉴入口
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _mainFish,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 27,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: .4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _bigStat(_bigNum, _bigUnit),
                    const SizedBox(width: 14),
                    _bigStat(_bigNum2, _bigUnit2),
                    const Spacer(),
                    _dexButton(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.black.withOpacity(.34),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  Widget _bigStat(String num, String unit) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          num,
          style: const TextStyle(
            fontSize: 26,
            height: 1,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          unit,
          style: const TextStyle(
            fontSize: 12,
            height: 1.6,
            fontWeight: FontWeight.w600,
            color: AppTheme.inkMuted,
          ),
        ),
      ],
    );
  }

  /// 右下「DEX 图鉴」胶囊（点进鱼类图鉴）
  Widget _dexButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FishGuideScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.42),
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(color: Colors.white.withOpacity(.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _hi,
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text('DEX',
                  style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.inkBg)),
            ),
            const SizedBox(width: 6),
            Text('$_mainFish图鉴',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded,
                size: 15, color: Colors.white),
          ],
        ),
      ),
    );
  }

  void _showMore() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.report_gmailerrorred_outlined),
                title: const Text('举报这条动态'),
                onTap: () {
                  Navigator.pop(context);
                  CenterToast.show(context, '已在后台记录，我们会尽快处理');
                },
              ),
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text('复制链接'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(
                      ClipboardData(text: 'fishing://post/${_post.id}'));
                  CenterToast.show(context, '链接已复制');
                },
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('取消'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════ 图集 ══════════════════════

  Widget _gallery() {
    final rest = _post.imageUrls.skip(1).toList();
    if (rest.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          for (final url in rest)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.fitWidth,
                  width: double.infinity,
                  fadeInDuration: const Duration(milliseconds: 180),
                  placeholder: (_, __) => const AspectRatio(
                    aspectRatio: 4 / 3,
                    child: ColoredBox(color: AppTheme.primarySoft),
                  ),
                  errorWidget: (_, __, ___) => const AspectRatio(
                    aspectRatio: 4 / 3,
                    child: ColoredBox(
                      color: AppTheme.primarySoft,
                      child: Center(
                        child: Icon(Icons.broken_image_outlined,
                            size: 28, color: AppTheme.textSecondary),
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

  // ══════════════════════ 通用卡片壳 ══════════════════════

  Widget _card({required Widget child, EdgeInsets? padding, Color? color}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: const Color(0x0F07080C)),
      ),
      child: child,
    );
  }

  // ══════════════════════ 作者卡 ══════════════════════

  Widget _authorCard() {
    return _card(
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => UserProfileScreen(userId: _post.userId)),
                ),
                borderRadius: BorderRadius.circular(30),
                child: UserAvatar(
                  url: ApiConfig.mediaUrl(_post.avatarUrl),
                  userId: _post.userId,
                  radius: 23,
                  vipLevel: _post.authorVip,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        _authorBadges(),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // 等级徽章 + 类别 + 时间合成一行：窄屏（320dp）下
                    // 三个 Text 并排会撑爆，这里只留一个可省略的文本。
                    Row(
                      children: [
                        _levelBadge(_post.userLevel),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${_post.isCatch ? '渔获记录' : _post.categoryLabel} · ${_post.timeAgo}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!_post.isMe && ApiConfig.enabled) ...[
                const SizedBox(width: 8),
                FollowButton(
                  userId: _post.userId,
                  tiny: true,
                  initialFollowing: _following,
                  onChanged: (v) => _following = v,
                ),
              ],
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, thickness: 1, color: AppTheme.divider),
          ),
          // 三列：这条渔获的三个事实（不编作者累计数据）
          Row(
            children: [
              _statCol('$_bigNum$_bigUnit', '本贴渔获', AppTheme.primary),
              _vline(),
              _statCol('$_bigNum2$_bigUnit2', '鱼种数', AppTheme.primary),
              _vline(),
              _statCol('${_post.viewCount}', '浏览', AppTheme.star),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vline() => Container(
      width: 1, height: 26, color: AppTheme.divider);

  Widget _statCol(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 17,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  // ══════════════════════ 水质气象三连（深色卡） ══════════════════════

  Widget _waterCard() {
    final wt = _wm?.temp;
    final ox = _wm?.oxygen;
    final desc = _fw?.description.isNotEmpty == true ? _fw!.description : '—';
    return _card(
      color: _ink,
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          _waterCell(
            icon: Icons.water_drop_outlined,
            title: '水温',
            value: wt == null ? '—' : wt.toStringAsFixed(1),
            unit: wt == null ? '' : '℃',
            note: wt == null ? '待联网' : _tempMood(wt),
            noteColor: _hi,
          ),
          _waterCell(
            icon: Icons.bubble_chart_outlined,
            title: '水氧',
            value: ox == null ? '—' : ox.toStringAsFixed(1),
            unit: ox == null ? '' : 'mg/L',
            note: ox == null
                ? '待联网'
                : (ox >= 6
                    ? '溶氧充足'
                    : ox >= 4
                        ? '一般'
                        : '偏低'),
            noteColor: ox != null && ox < 4 ? AppTheme.warning : _hi,
          ),
          _waterCell(
            icon: Icons.cloud_outlined,
            title: '天气',
            value: desc,
            unit: '',
            valueSize: desc.length > 3 ? 15 : 21,
            note: _hour == null
                ? ''
                : '${_hour!.temp.round()}℃ ${_windDir(_hour!.windDir)}风',
            noteColor: _hiDim,
          ),
        ],
      ),
    );
  }

  Widget _waterCell({
    required IconData icon,
    required String title,
    required String value,
    required String unit,
    required String note,
    required Color noteColor,
    double valueSize = 21,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
        decoration: BoxDecoration(
          color: _inkCell,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: _inkLine, width: .6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: _hiDim.withOpacity(.85)),
                const SizedBox(width: 3),
                Text(title,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white.withOpacity(.62))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: valueSize,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  Text(unit,
                      style: TextStyle(
                          fontSize: 9.5,
                          height: 1.6,
                          color: Colors.white.withOpacity(.55))),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600, color: noteColor)),
          ],
        ),
      ),
    );
  }

  // ══════════════════════ 互动数据卡（对应参考稿 REWARD 位） ══════════════════════

  Widget _statsCard() {
    return _card(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Row(
        children: [
          Expanded(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('STATS',
                    style: TextStyle(
                        fontSize: 9,
                        height: 1.2,
                        letterSpacing: .8,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary)),
              ),
              const SizedBox(height: 6),
              Text(
                _post.isCatch ? '这条渔获的互动' : '这条动态的互动',
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 2),
              const Text('实时更新',
                  style:
                      TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ),
          ),
          const SizedBox(width: 10),
          _miniStat('${_post.viewCount}', '浏览', AppTheme.primary),
          const SizedBox(width: 10),
          _miniStat('${_post.likeCount}', '点赞', AppTheme.danger),
          const SizedBox(width: 10),
          _miniStat('${_post.commentCount}', '评论', AppTheme.textPrimary),
        ],
      ),
    );
  }

  Widget _miniStat(String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 16,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: color)),
        const SizedBox(height: 2),
        Text(label,
            style:
                const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary)),
      ],
    );
  }

  // ══════════════════════ 钓友们说 ══════════════════════

  Widget _praiseBar() {
    if (_post.likeCount <= 0) return const SizedBox.shrink();
    final shown = _post.likeCount > 99 ? '99+' : '${_post.likeCount}';
    return _card(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      color: AppTheme.primarySoft,
      child: Row(
        children: [
          Text('钓友们说',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary.withOpacity(.95))),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(5, 3, 7, 3),
            decoration: BoxDecoration(
              color: _hi.withOpacity(.20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_emotions_rounded,
                    size: 14, color: AppTheme.primary),
                const SizedBox(width: 3),
                Text('×$shown',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryDark)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${_post.likeCount} 人夸过',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11.5, color: AppTheme.textSecondary)),
          ),
          const Icon(Icons.chevron_right_rounded,
              size: 16, color: AppTheme.textSecondary),
        ],
      ),
    );
  }

  // ══════════════════════ 标签行 ══════════════════════

  Widget _tagsRow() {
    final tags = <String>[
      _post.categoryLabel,
      if (_post.city.trim().isNotEmpty) _post.city.trim(),
      _dayPart,
      if (_fw != null && _fw!.description.isNotEmpty) _fw!.description,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: Text('场景',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < tags.length; i++)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      // 第一个标签是主场景：深色实心；其余浅底
                      color: i == 0 ? AppTheme.textPrimary : AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      border: i == 0
                          ? null
                          : Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      tags[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            i == 0 ? Colors.white : AppTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════ 钓点卡 ══════════════════════

  Widget _spotCard() {
    final name = (_post.locationName ?? '').trim();
    if (name.isEmpty) return const SizedBox.shrink();
    final sub = <String>[
      if (_post.city.trim().isNotEmpty) _post.city.trim(),
      if (_post.isCatch) '渔获点' else _post.categoryLabel,
    ].join(' · ');

    return _card(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // 小地图缩略：没有静态图接口，用等高线感的占位色块 + 定位针
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEFF2F7), Color(0xFFF7F9FC)],
              ),
              border: Border.all(color: AppTheme.primaryBorder),
            ),
            child: const Center(
              child: Icon(Icons.place_rounded, size: 22, color: AppTheme.primary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Material(
                color: AppTheme.textPrimary,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _openMap,
                  child: const SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(Icons.navigation_rounded,
                        size: 18, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              const Text('导航',
                  style: TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  /// 打开系统/高德地图看钓点（有经纬度才可用）
  Future<void> _openMap() async {
    final lat = _post.lat, lng = _post.lng;
    if (lat == null || lng == null) {
      CenterToast.show(context, '这条渔获没有留下坐标');
      return;
    }
    final name = Uri.encodeComponent((_post.locationName ?? '钓点').trim());
    final uri = Uri.parse(
        'https://uri.amap.com/marker?position=$lng,$lat&name=$name&src=app&coordinate=gaode&callnative=1');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) CenterToast.show(context, '没有找到可用的地图 App');
  }

  // ══════════════════════ CATCH INDEX ══════════════════════

  Widget _indexCard() {
    final score = _fw?.score;
    final idx = (score ?? 0).clamp(0, 100);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.inkBg, AppTheme.inkSurface],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: _inkLine, width: .8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CATCH INDEX',
                        style: TextStyle(
                            fontSize: 11.5,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                    const SizedBox(height: 5),
                    Text(
                      _hour == null
                          ? '捕获时指数'
                          : '捕获时指数 · ${_hour!.hhmm} 前后',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.white.withOpacity(.55)),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                score == null ? '—' : '$idx',
                style: const TextStyle(
                  fontSize: 40,
                  height: .95,
                  fontWeight: FontWeight.w900,
                  color: _hi,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _hi,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(_indexLabel,
                    style: const TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.inkBg)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _indexBar(score),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final t in const ['口差', '有口', '爆护'])
                Expanded(
                  child: Text(t,
                      textAlign: t == '口差'
                          ? TextAlign.left
                          : (t == '爆护' ? TextAlign.right : TextAlign.center),
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(.45))),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            _indexCell(Icons.thermostat_rounded, '气温',
                _hour == null ? '—' : '${_hour!.temp.toStringAsFixed(1)}',
                _hour == null ? '' : '℃',
                _hour == null ? '' : _tempMood(_hour!.temp), _hi),
            _indexCell(Icons.speed_rounded, '气压',
                _hour == null ? '—' : '${_hour!.pressure.toStringAsFixed(1)}',
                _hour == null ? '' : 'hPa',
                _hour?.pressureTrend == 'rising'
                    ? '↑ 上升'
                    : _hour?.pressureTrend == 'falling'
                        ? '↓ 下降'
                        : '→ 平稳',
                _hour?.pressureTrend == 'falling'
                    ? AppTheme.warning
                    : _hiDim),
            _indexCell(Icons.air_rounded, '风',
                _hour == null
                    ? '—'
                    : '${beaufortLevel(_hour!.windSpeed)}',
                _hour == null ? '' : '级',
                _hour == null ? '' : '${_windDir(_hour!.windDir)}风', _hi),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _indexCell(Icons.water_drop_rounded, '水温',
                _wm == null ? '—' : _wm!.temp.toStringAsFixed(1),
                _wm == null ? '' : '℃',
                _wm == null ? '' : _tempMood(_wm!.temp), _hiDim),
            _indexCell(Icons.bubble_chart_rounded, '水氧',
                _wm == null ? '—' : _wm!.oxygen.toStringAsFixed(1),
                _wm == null ? '' : 'mg/L',
                _wm == null ? '' : (_wm!.oxygen >= 6 ? '充足' : '一般'),
                _hi),
            _indexCell(Icons.cloud_rounded, '天气',
                _fw?.description.isNotEmpty == true ? _fw!.description : '—',
                '',
                _hour == null ? '' : '${_hour!.precipProb}% 降水',
                _hiDim),
          ]),
        ],
      ),
    );
  }

  /// 三段进度条：0–40 口差 / 40–72 有口 / 72–100 爆护
  Widget _indexBar(int? score) {
    Widget seg(Color a, Color b, double flex) => Expanded(
          flex: (flex * 100).round(),
          child: Container(
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [a, b]),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );

    return LayoutBuilder(
      builder: (ctx, c) {
        final pos = score == null ? 0.0 : (score / 100).clamp(0.0, 1.0);
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            Row(children: [
              // 三段是一条「越满越亮」的连续色带：石墨 → 橄榄 → 荧光黄绿。
              // 相邻两段的端点取同一个值，接缝处不断色（v2.1.36）。
              seg(AppTheme.inkLine, AppTheme.violet, .40),
              seg(AppTheme.violet, AppTheme.accentMid, .32),
              seg(AppTheme.accentMid, AppTheme.accent, .28),
            ]),
            if (score != null)
              Positioned(
                left: (c.maxWidth - 8) * pos,
                child: Container(
                  width: 8,
                  height: 13,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: const [
                      BoxShadow(color: Color(0x66000000), blurRadius: 4)
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _indexCell(IconData icon, String title, String value, String unit,
      String note, Color noteColor) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
        decoration: BoxDecoration(
          color: _inkCell,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: _inkLine, width: .6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 11, color: _hiDim.withOpacity(.8)),
              const SizedBox(width: 3),
              Text(title,
                  style: TextStyle(
                      fontSize: 10, color: Colors.white.withOpacity(.6))),
            ]),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: value.length > 4 ? 13 : 17,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  Text(unit,
                      style: TextStyle(
                          fontSize: 9,
                          height: 1.5,
                          color: Colors.white.withOpacity(.5))),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: noteColor)),
          ],
        ),
      ),
    );
  }

  // ══════════════════════ 等级 / 徽章 ══════════════════════

  Widget _levelBadge(int level) {
    final lv = level <= 0 ? 1 : level;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.primaryBorder, width: .8),
      ),
      child: Text(
        'LV$lv',
        style: const TextStyle(
          fontSize: 9.5,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: AppTheme.primary,
        ),
      ),
    );
  }

  Widget _authorBadges() {
    BadgeHub.warm([_post.userId]);
    return ValueListenableBuilder<int>(
      valueListenable: BadgeHub.revision,
      builder: (_, __, ___) {
        final badges = _post.badges.isNotEmpty
            ? _post.badges.take(3).toList()
            : BadgeHub.of(_post.userId).take(3).toList();
        if (badges.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final b in badges)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: _badgeChip(b),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _badgeChip(BadgeItem b) {
    final url = b.isImage ? ApiConfig.mediaUrl(b.icon) : null;
    final tint = _hexColor(b.color) ?? AppTheme.primary;
    return Tooltip(
      message: b.name,
      child: Container(
        width: 17,
        height: 17,
        decoration: BoxDecoration(
          color: tint.withOpacity(.12),
          borderRadius: BorderRadius.circular(5),
        ),
        alignment: Alignment.center,
        child: url != null && url.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  url,
                  width: 17,
                  height: 17,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.military_tech, size: 13, color: tint),
                ),
              )
            : (b.icon.isNotEmpty
                ? Text(b.icon, style: const TextStyle(fontSize: 11, height: 1))
                : Icon(Icons.military_tech, size: 13, color: tint)),
      ),
    );
  }

  Color? _hexColor(String s) {
    var v = s.trim().replaceAll('#', '');
    if (v.length == 3) {
      v = v.split('').map((c) => '$c$c').join();
    }
    if (v.length != 6) return null;
    final n = int.tryParse(v, radix: 16);
    if (n == null) return null;
    return Color(0xFF000000 | n);
  }

  // ══════════════════════ 评论 ══════════════════════

  Widget _commentTile(Map<String, dynamic> c) {
    final name = (c['user_nickname'] as String?) ?? '钓友';
    final avatar = c['user_avatar'] as String?;
    final content = (c['content'] as String?) ?? '';
    final createdAt = (c['created_at'] as String?) ?? '';
    final time = createdAt.isEmpty
        ? ''
        : (createdAt.length >= 16 ? createdAt.substring(5, 16) : createdAt);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            url: ApiConfig.mediaUrl(avatar),
            userId: c['user_id'] as String?,
            radius: 17,
            vipLevel: (c['user_vip'] as num?)?.toInt() ?? 0,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textSecondary
                                        .withOpacity(.95))),
                          ),
                          if (time.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(time,
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    color: AppTheme.textSecondary)),
                          ],
                        ],
                      ),
                    ),
                    const Icon(Icons.thumb_up_alt_outlined,
                        size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 10),
                    const Icon(Icons.more_horiz_rounded,
                        size: 15, color: AppTheme.textSecondary),
                  ],
                ),
                const SizedBox(height: 4),
                Text(content,
                    style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 5),
                const Text('回复',
                    style: TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════ 底部栏 ══════════════════════

  Widget _bottomBar() {
    // ★ 原来这里用 🐟🔥😱📍 当贴纸图标。emoji 依赖系统彩色字体，
    //   ROM 精简 / 老 Android 上会渲染成小方块。换成 Material 图标，
    //   图标字体随包打包（uses-material-design: true），永远有字形。
    const quick = [
      (Icons.set_meal, '好鱼！'),
      (Icons.local_fire_department, '爆护了'),
      (Icons.sentiment_very_satisfied, '这么大？'),
      (Icons.place, '求钓点'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 快捷贴纸：一点即发
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                children: [
                  for (final q in quick)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                        onTap: () => _send(q.$2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.primarySoft,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusPill),
                            border: Border.all(color: AppTheme.primaryBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(q.$1, size: 15, color: AppTheme.primaryDark),
                              const SizedBox(width: 5),
                              Text(q.$2,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primaryDark)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.only(left: 14, right: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySoft,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusPill),
                        border: Border.all(color: AppTheme.primaryBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ctrl,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              style: const TextStyle(fontSize: 13.5),
                              decoration: const InputDecoration(
                                hintText: '说点什么…',
                                hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary),
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 9),
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.emoji_emotions_outlined,
                                size: 18, color: AppTheme.textSecondary),
                            tooltip: '表情',
                            onPressed: () => showEmojiSheet(context, _ctrl),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _bottomAction(
                    icon: _post.likedByMe
                        ? Icons.thumb_up_alt_rounded
                        : Icons.thumb_up_alt_outlined,
                    label: '${_post.likeCount}',
                    active: _post.likedByMe,
                    onTap: _toggleLike,
                  ),
                  _bottomAction(
                    icon: Icons.mode_comment_outlined,
                    label: '${_post.commentCount}',
                    onTap: () => FocusScope.of(context).requestFocus(FocusNode()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final c = active ? AppTheme.primary : AppTheme.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 19, color: c),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: c)),
          ],
        ),
      ),
    );
  }

  // ══════════════════════ 吸顶作者条 ══════════════════════

  /// 滚过封面后从顶部浮出的作者条（参考稿的交互）：
  /// 返回 + 头像 + 昵称 + 关注 + 更多，白底 + 底部细线。
  Widget _stickyBar() {
    return ValueListenableBuilder<double>(
      valueListenable: _offVN,
      builder: (_, off, __) {
        // 封面下沿前 96px 开始渐显，再滚 80px 完全出现
        final t = ((off - (_coverH - 96)) / 80).clamp(0.0, 1.0);
        if (t <= 0) return const SizedBox.shrink();
        final top = MediaQuery.of(context).padding.top;
        return Opacity(
          opacity: t,
          child: Container(
            padding: EdgeInsets.only(top: top + 4, bottom: 6, left: 4, right: 6),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(t),
              border: Border(
                  bottom: BorderSide(
                      color: AppTheme.divider.withOpacity(t), width: 1)),
            ),
            child: Row(
              children: [
                IconButton(
                  iconSize: 20,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: AppTheme.textPrimary),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 2),
                UserAvatar(
                  url: ApiConfig.mediaUrl(_post.avatarUrl),
                  userId: _post.userId,
                  radius: 15,
                  vipLevel: _post.authorVip,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary),
                  ),
                ),
                if (!_post.isMe && ApiConfig.enabled) ...[
                  FollowButton(
                    userId: _post.userId,
                    tiny: true,
                    initialFollowing: _following,
                    onChanged: (v) => _following = v,
                  ),
                  const SizedBox(width: 4),
                ],
                IconButton(
                  iconSize: 20,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.more_horiz_rounded,
                      color: AppTheme.textPrimary),
                  onPressed: _showMore,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════ 组装 ══════════════════════

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          ListView(
            controller: _scroll,
            padding: EdgeInsets.zero,
            children: [
            // 封面 + 内容区上浮圆角
            Stack(
              children: [
                _cover(),
                SizedBox(height: 0),
              ],
            ),
            Transform.translate(
              offset: const Offset(0, -18),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    _gallery(),
                    _authorCard(),
                    _waterCard(),
                    _statsCard(),
                    _praiseBar(),
                    // 正文
                    if ((_post.body ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Text(
                          _post.body!,
                          style: const TextStyle(
                            fontSize: 15.5,
                            height: 1.68,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    _tagsRow(),
                    _spotCard(),
                    _indexCard(),
                    const SizedBox(height: 16),
                    // 评论
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                      child: Row(
                        children: [
                          const Text('评论',
                              style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary)),
                          const SizedBox(width: 5),
                          const Text('COMMENTS',
                              style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: .8,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textSecondary)),
                          const Spacer(),
                          Text('${_post.commentCount} 条',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary)),
                          const Icon(Icons.keyboard_arrow_down_rounded,
                              size: 18, color: AppTheme.textSecondary),
                        ],
                      ),
                    ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.primaryBorder),
                          ),
                        ),
                      )
                    else if (_comments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                          child: Text('还没有评论，来抢沙发',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary)),
                        ),
                      )
                    else
                      ..._comments.map(_commentTile),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
            ],
          ),
          // 吸顶作者条（滚过封面才出现）
          Positioned(top: 0, left: 0, right: 0, child: _stickyBar()),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );

    // 状态栏图标：封面区用白色，滚到白底后切深色
    return ValueListenableBuilder<double>(
      valueListenable: _offVN,
      child: page,
      builder: (_, off, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: off > _coverH - 90
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        child: child!,
      ),
    );
  }
}
