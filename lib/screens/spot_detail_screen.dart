import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../widgets/emoji_panel.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/fishing_spot.dart';
import '../models/spot_comment.dart';
import '../services/ai_spot_service.dart';
import '../services/api_config.dart';
import '../services/geo_place.dart';
import '../services/location_service.dart';
import '../services/map_launcher.dart';
import '../services/session_provider.dart';
import '../models/weather_forecast.dart';
import '../services/spot_conditions.dart';
import '../services/spot_service.dart';
import '../services/weather_service.dart';
import '../widgets/center_toast.dart';
import '../widgets/login_gate.dart';
import '../widgets/spot_conditions_card.dart';
import '../widgets/user_avatar.dart';
import 'auth_screen.dart';
import 'publish_catch_screen.dart';

/// 钓点详情页
/// 顶部为「环境展示图」图集（钓友上传的实拍环境照片），
/// 下方依次是类型/星级、标签、地址/收费/鱼种/电话、描述、精确坐标，
/// 并提供「导航前往」（跳转高德/腾讯/百度地图）与「报错」。
class SpotDetailScreen extends StatefulWidget {
  final FishingSpot spot;

  /// 仅测试 / 截图用：直接喂一份钓点天气，跳过网络请求
  ///
  /// （和 AiSpotDetailScreen 的 debugBundle 同一套做法：
  ///  详情页的分数全靠天气算，没有天气就断言不了「推荐指数/最佳时段」到底对不对）
  final WeatherBundle? debugBundle;

  /// 仅测试 / 截图用：直接喂一份「我当前位置」的实时天气
  final FishingWeather? debugMyWeather;

  const SpotDetailScreen({
    super.key,
    required this.spot,
    this.debugBundle,
    this.debugMyWeather,
  });

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen> {
  late int _reportCount;
  final PageController _galleryCtrl = PageController();
  int _galleryIndex = 0;

  // —— 评论区（v16：提交后需后台审核才显示）——
  List<SpotComment> _comments = [];
  bool _loadingComments = true;
  bool _sending = false;
  final TextEditingController _commentCtrl = TextEditingController();

  /// 逆地理反查到的中文地址（钓点自身没填地址时兜底显示）
  String _geoAddress = '';

  // ── v2.1.83：AI 分析 / 现在去合不合适 ──
  //
  // 天气分两份，别混：
  //   _bundle   = **这个钓点坐标**的逐时天气 → 算推荐指数、24 小时色条
  //   _myWeather = **我当前位置**的实时天气 → 卡片最上面那行「你所在位置」
  // 判断「去那里合不合适」当然用钓点的天气，用户自己的天气只作参考。
  WeatherBundle? _bundle;
  SpotConditions? _conditions;
  FishingWeather? _myWeather;
  bool _wxLoading = true;
  bool _myLocating = false;
  double? _myLat;
  double? _myLng;

  final ScrollController _scroll = ScrollController();
  final FocusNode _commentFocus = FocusNode();
  final GlobalKey _commentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _reportCount = widget.spot.reportCount;
    _loadComments();
    _resolveAddress();
    if (widget.debugBundle != null) {
      _bundle = widget.debugBundle;
      _wxLoading = false;
      _recomputeConditions();
    } else {
      _loadSpotWeather();
    }
    if (widget.debugMyWeather != null) {
      _myWeather = widget.debugMyWeather;
    } else {
      // 不主动弹定位权限框：只有已经授权过的才顺手取一下
      _loadMyWeather();
    }
  }

  @override
  void dispose() {
    _galleryCtrl.dispose();
    _commentCtrl.dispose();
    _scroll.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  // ───────────────────── 天气 / 指数 ─────────────────────

  /// 拉这个钓点坐标的逐时天气，算出推荐指数与最佳时段
  Future<void> _loadSpotWeather() async {
    try {
      final b = await AiSpotService.weatherAt(widget.spot.lat, widget.spot.lng);
      if (!mounted) return;
      setState(() {
        _bundle = b;
        _wxLoading = false;
        _recomputeConditions();
      });
    } catch (_) {
      if (mounted) setState(() => _wxLoading = false);
    }
  }

  /// 取「我当前位置」的实时天气
  ///
  /// [ask] 为 true 表示是用户主动点的：这时才允许弹系统定位授权框。
  /// 页面打开时不弹（HIG：不在启动路径上要权限）。
  Future<void> _loadMyWeather({bool ask = false}) async {
    if (_myLocating) return;
    setState(() => _myLocating = true);
    try {
      // ① 先用系统缓存的位置：绝大多数情况下用户刚在首页定位过
      final cached = await WeatherService.readCachedLocation();
      double? lat = cached?.$1;
      double? lng = cached?.$2;

      // ② 没缓存才真正取一次定位（ask=false 且没授权就直接放弃，不打扰）
      if (lat == null || lng == null) {
        if (!ask && !await LocationService.hasPermission()) {
          if (mounted) setState(() => _myLocating = false);
          return;
        }
        final pos = await LocationService.determinePosition();
        lat = pos.latitude;
        lng = pos.longitude;
      }

      final w = await WeatherService.fetch(lat, lng);
      if (!mounted) return;
      setState(() {
        _myWeather = w;
        _myLat = lat;
        _myLng = lng;
        _myLocating = false;
        _recomputeConditions();
      });
    } catch (_) {
      if (mounted) setState(() => _myLocating = false);
    }
  }

  /// 重新算子（距离/方位角要等定位回来才算得准）
  void _recomputeConditions() {
    final s = widget.spot;
    var km = 0.0;
    var bearing = 0.0;
    final lat = _myLat, lng = _myLng;
    if (lat != null && lng != null) {
      km = SpotConditions.kmBetween(lat, lng, s.lat, s.lng);
      bearing = SpotConditions.bearingBetween(lat, lng, s.lat, s.lng);
    }
    _conditions = SpotConditions.of(
      bundle: _bundle,
      kind: s.kind,
      km: km,
      bearingFromMe: bearing,
    );
  }

  /// 拉取已审核通过的评论
  Future<void> _loadComments() async {
    try {
      final list = await SpotService.fetchComments(widget.spot.id);
      if (mounted) setState(() => _comments = list);
    } catch (_) {
      // 评论加载失败不影响详情展示
    } finally {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  /// 钓点没填地址时，用坐标反查一个中文地址（不显示经纬度数字）
  Future<void> _resolveAddress() async {
    if (widget.spot.address.trim().isNotEmpty) return;
    final p = await GeoPlace.reverse(widget.spot.lat, widget.spot.lng);
    if (mounted && p != null && p.display.isNotEmpty) {
      setState(() => _geoAddress = p.display);
    }
  }

  /// 页面上展示的地址：优先用户填写的地址 → 反查结果 → 空
  String get _addressText {
    final a = widget.spot.address.trim();
    if (a.isNotEmpty) return a;
    return _geoAddress;
  }

  /// 导航用的目的地关键词（地址优先，让地图导航栏显示中文地名）
  String get _navAddress => _addressText;

  /// 发表评论
  Future<void> _sendComment() async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (!sp.isLoggedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      return;
    }
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) {
      CenterToast.show(context, '先写点内容吧');
      return;
    }
    setState(() => _sending = true);
    try {
      await SpotService.addComment(widget.spot.id, text);
      _commentCtrl.clear();
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      CenterToast.show(context, '评论已提交，审核通过后显示');
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _report() async {
    final res = await showModalBottomSheet<_ReportResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ReportSheet(spotName: widget.spot.name),
    );
    if (res == null) return;

    try {
      await SpotService.reportSpot(
        spotId: widget.spot.id,
        spotName: widget.spot.name,
        reason: res.reason,
        note: res.note,
        lat: res.lat,
        lng: res.lng,
        accuracy: res.accuracy,
      );
      if (mounted) {
        setState(() => _reportCount += 1);
        CenterToast.show(
          context,
          res.hasCoord ? '已提交，你的位置也一起上报了，感谢！' : '已提交报错，感谢反馈！',
        );
      }
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, '报错失败：$e');
      }
    }
  }

  /// 拨打电话
  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        CenterToast.show(context, '无法拨打电话');
      }
    }
  }

  /// 环境展示图列表：环境图优先，其次封面图
  List<String> get _galleryImages {
    final s = widget.spot;
    final list = [...s.imageUrls];
    if (list.isEmpty && s.coverUrl != null && s.coverUrl!.isNotEmpty) {
      list.add(s.coverUrl!);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spot;
    final tags = s.tags
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final images = _galleryImages;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(s.name),
        actions: [_reportAction()],
      ),
      body: ListView(
        controller: _scroll,
        padding: EdgeInsets.zero,
        children: [
          // ① 环境展示图
          _buildGallery(images),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ② 类型 / 核实 / 星级 / 标签（轻量一行，不抢 AI 卡的视线）
                _metaRow(s, tags),
                const SizedBox(height: 10),
                // ③ AI 分析（黑卡）：推荐指数 = 天气 + 水域 + 风岸 + 距离
                SpotAiCard(data: _conditions, loading: _wxLoading),
                // ④ 现在去合不合适（白卡）：定位实时天气 + 温度/风力 + 建议 + 最佳时段
                SpotConditionsCard(
                  data: _conditions,
                  loading: _wxLoading,
                  myWeather: _myWeather,
                  myLocating: _myLocating,
                  onRefreshMyWeather: () => _loadMyWeather(ask: true),
                ),
                // ⑤ 基础信息 + 说明
                _infoCard(s),
                const SizedBox(height: 12),
                // ⑥ 位置精度提醒 / 位置不对报点
                _noticeCard(s),
                const SizedBox(height: 16),
                // ⑦ 评论
                _buildCommentsSection(),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ],
      ),
      // 底部常驻操作栏（收藏位的三个小动作 + 主按钮导航）
      bottomNavigationBar: _actionBar(s),
    );
  }

  /// 右上角「报错」：带次数角标
  Widget _reportAction() {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: _report,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.report_problem_outlined,
                  size: 18, color: AppTheme.danger),
              if (_reportCount > 0) ...[
                const SizedBox(width: 3),
                Text('$_reportCount',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.danger)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 类型胶囊 + 官方核实 + 星级 + 标签
  Widget _metaRow(FishingSpot s, List<String> tags) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: s.kind == 'wild'
                    ? AppTheme.dangerLight
                    : AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${s.kindLabel} · ${s.type}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: s.kind == 'wild' ? AppTheme.danger : AppTheme.primary,
                ),
              ),
            ),
            if (s.verified) ...[
              const SizedBox(width: 8),
              const Icon(Icons.verified, size: 15, color: AppTheme.water),
              const SizedBox(width: 3),
              const Text('官方核实',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.water)),
            ],
            const Spacer(),
            const Icon(Icons.star, size: 15, color: AppTheme.star),
            const SizedBox(width: 3),
            Text(
              s.rating.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary),
            ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: tags.map(_tagChip).toList()),
        ],
      ],
    );
  }

  /// 基础信息卡：地址 / 收费 / 鱼种 / 电话 / 说明
  Widget _infoCard(FishingSpot s) {
    final rows = <Widget>[
      if (_addressText.isNotEmpty)
        _infoRow(Icons.location_on_outlined, _addressText),
      if (s.fee.isNotEmpty) _infoRow(Icons.payments_outlined, '收费：${s.fee}'),
      if (s.fish.isNotEmpty) _infoRow(Icons.set_meal_outlined, '鱼种：${s.fish}'),
      if (s.phone.isNotEmpty)
        _infoRow(Icons.phone_outlined, s.phone, onTap: () => _call(s.phone)),
      if (s.commentCount > 0)
        _infoRow(Icons.chat_bubble_outline, '${s.commentCount} 条评论'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...rows,
          if (rows.isNotEmpty) const SizedBox(height: 6),
          Text(
            s.description.isEmpty ? '钓友暂未填写说明' : s.description,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.62,
              color: s.description.isEmpty
                  ? AppTheme.textSecondary
                  : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// 位置卡：地址精度提醒 + 「位置不对」上报入口（v2.1.76 的现场报点）
  Widget _noticeCard(FishingSpot s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: AppTheme.accentLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.place_outlined,
                  size: 15, color: AppTheme.accentDark),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _addressText.isNotEmpty
                      ? _addressText
                      : '暂无地址信息，可点「导航前往」在地图里查看',
                  style: const TextStyle(
                      fontSize: 12.5, height: 1.5, color: AppTheme.accentDark),
                ),
              ),
            ],
          ),
          if (!s.canNavigateByCoord && _addressText.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 21, top: 4),
              child: Text(
                '位置按地址定位，误差可能几十米，到附近后按岸线找一下',
                style: TextStyle(
                    fontSize: 11.5, height: 1.5, color: AppTheme.accentDark),
              ),
            ),
          if (s.lat != 0 || s.lng != 0)
            GestureDetector(
              onTap: _report,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(left: 21, top: 5),
                child: Text(
                  '位置不对？点这里把你在现场的位置发给我们 >',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.accentDark,
                    decoration: TextDecoration.underline,
                    decorationColor: AppTheme.accentDark,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 底部操作栏：分享 / 评价 / 晒渔获 + 导航前往
  ///
  /// 为什么把「导航前往」做成黑色主按钮：
  ///   这一页 90% 的用户动作是「现在就出发」，它必须是唯一的视觉重心；
  ///   报错挪到右上角（带次数角标），避免和主按钮并排时被误点。
  Widget _actionBar(FishingSpot s) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          child: Row(
            children: [
              _actionBtn(Icons.share_outlined, '分享', () => _share(s)),
              _actionBtn(Icons.rate_review_outlined, '评价', _focusComment),
              _actionBtn(Icons.camera_alt_outlined, '晒渔获', () => _publishCatch(s)),
              const SizedBox(width: 6),
              Expanded(child: _navButton(s)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: AppTheme.textPrimary),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    fontSize: 10.5, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _navButton(FishingSpot s) {
    return InkWell(
      onTap: () => MapLauncher.navigate(
        context,
        lat: s.lat,
        lng: s.lng,
        name: s.name,
        address: _navAddress,
        // v46：有坐标就按坐标导航，不再因为「坐标是地址解析来的」
        // 而退回按文字搜索 —— 解析出来的坐标本来就是这句地址的位置
      ),
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: AppTheme.inkBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 绿点：和 App 里「AI 在线」的荧光绿同一个信号色
            SizedBox(
              width: 7,
              height: 7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: AppTheme.accent, shape: BoxShape.circle),
              ),
            ),
            SizedBox(width: 8),
            Text(
              '导航前往',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 分享：把钓点关键信息复制出去（App 没接系统分享面板，
  /// 复制粘贴给钓友是最通用的路径，也不申请额外权限）
  Future<void> _share(FishingSpot s) async {
    final c = _conditions;
    final lines = <String>[
      '【${s.kindLabel}】${s.name}',
      if (_addressText.isNotEmpty) '地址：$_addressText',
      if (s.fish.isNotEmpty) '鱼种：${s.fish}',
      if (c != null) '今日推荐指数：${c.score}（${c.grade}）',
      if (c != null && c.best != null)
        '最佳时段：${c.best!.range}（${c.best!.score} 分）',
      if (s.lat != 0 || s.lng != 0)
        '坐标：${s.lat.toStringAsFixed(5)},${s.lng.toStringAsFixed(5)}',
      '—— 来自渔报',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) {
      CenterToast.show(context, '钓点信息已复制，可以发给钓友', icon: Icons.copy);
    }
  }

  /// 评价：滚到评论区并聚焦输入框
  void _focusComment() {
    final ctx = _commentKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        alignment: .05,
      );
    }
    Future.delayed(const Duration(milliseconds: 340), () {
      if (mounted) _commentFocus.requestFocus();
    });
  }

  /// 晒渔获：带上这个钓点的名字与坐标去发渔获
  Future<void> _publishCatch(FishingSpot s) async {
    final ok = await ensureLogin(context, hint: '登录后才能发布渔获');
    if (!ok || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublishCatchScreen(
          spotName: s.name,
          spotLat: s.lat == 0 ? null : s.lat,
          spotLng: s.lng == 0 ? null : s.lng,
        ),
      ),
    );
  }

  /// 单个标签：紧凑圆角小标签（一行排满自动换行）
  Widget _tagChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTheme.primaryBorder.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 11.5, height: 1.25, color: AppTheme.primary),
      ),
    );
  }

  /// 评论区：标题 + 已通过审核的评论列表
  Widget _buildCommentsSection() {
    return Column(
      key: _commentKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('钓友评论',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(width: 6),
            Text('${_comments.length}',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
            const Spacer(),
            const Text('评论审核通过后显示',
                style: TextStyle(
                    fontSize: 11.5, color: AppTheme.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingComments)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              ),
            ),
          )
        else if (_comments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 22, color: AppTheme.textSecondary),
                SizedBox(height: 6),
                Text('还没有评论，来说说这个钓点的情况吧',
                    style: TextStyle(
                        fontSize: 12.5, color: AppTheme.textSecondary)),
              ],
            ),
          )
        else
          ..._comments.map(_commentTile),
        const SizedBox(height: 10),
        // 输入框放回评论区里：底部操作栏已经常驻，
        // 再挂一条 bottomNavigationBar 会把「导航前往」顶上去
        _buildCommentInput(),
      ],
    );
  }

  /// 单条评论
  Widget _commentTile(SpotComment c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            url: ApiConfig.mediaUrl(c.avatarUrl),
            userId: c.userId,
            radius: 16,
            vipLevel: c.vipLevel,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(c.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary)),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 0.5),
                      decoration: BoxDecoration(
                        // LV 角标：和钓友圈卡片的 LV 同一套（冷灰底 + 近黑字）。
                        // 原来是支付宝蓝 #1677FF 底 #E8F3FF —— 全站唯一的蓝底小签。
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                            color: AppTheme.primaryBorder, width: 0.7),
                      ),
                      child: Text('LV${c.userLevel}',
                          style: const TextStyle(
                              fontSize: 9.5,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary)),
                    ),
                    const Spacer(),
                    Text(c.timeAgo,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(c.content,
                    style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppTheme.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 评论输入条（内联在评论区下方）
  Widget _buildCommentInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentCtrl,
              focusNode: _commentFocus,
              textInputAction: TextInputAction.send,
              maxLength: 500,
              onSubmitted: (_) => _sendComment(),
              decoration: InputDecoration(
                hintText: '说说这个钓点的情况…（审核后显示）',
                hintStyle: const TextStyle(fontSize: 13),
                isDense: true,
                counterText: '',
                filled: true,
                fillColor: AppTheme.primarySoft,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _sending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.send, color: AppTheme.primary),
                  onPressed: _sendComment,
                ),
        ],
      ),
    );
  }

  /// 顶部环境图集：有图显示轮播（带页码指示），无图显示占位
  Widget _buildGallery(List<String> images) {
    if (images.isEmpty) {
      return Container(
        height: 168,
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppTheme.brandGradient),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_outlined, color: Colors.white70, size: 40),
            const SizedBox(height: 8),
            Text('暂无环境展示图',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85), fontSize: 13)),
          ],
        ),
      );
    }
    return Stack(
      children: [
        SizedBox(
          height: 210,
          width: double.infinity,
          child: PageView.builder(
            controller: _galleryCtrl,
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _galleryIndex = i),
            itemBuilder: (_, i) => CachedNetworkImage(
              imageUrl: images[i],
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppTheme.primarySoft),
              errorWidget: (_, __, ___) => Container(
                color: AppTheme.primarySoft,
                child: const Icon(Icons.broken_image_outlined,
                    color: AppTheme.textTertiary, size: 36),
              ),
            ),
          ),
        ),
        if (images.length > 1)
          Positioned(
            right: 12,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${_galleryIndex + 1}/${images.length}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11.5)),
            ),
          ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String text, {VoidCallback? onTap}) {
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppTheme.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13.5, color: Colors.black87)),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// 报错弹窗的返回值
class _ReportResult {
  final String reason;
  final String? note;

  /// 钓友当时站的位置（WGS-84）。只有选了「坐标错误」并且真的定位成功才有值。
  final double? lat;
  final double? lng;
  final double? accuracy;

  const _ReportResult({
    required this.reason,
    this.note,
    this.lat,
    this.lng,
    this.accuracy,
  });

  bool get hasCoord => lat != null && lng != null;
}

/// 钓点报错弹窗（v2.1.76：报「坐标错误」时顺手把当前位置带上）
///
/// 为什么要带位置：
///   高德地图里「某某水库」那条 POI，坐标常常落在管理机构、大门口或水体中心，
///   不是能下竿的位置 —— 这种偏差靠坐标系换算永远修不掉（换算误差不到 1 米）。
///   到过现场的钓友手机 GPS（一般 ±5~15 米）才是金标准，后台可以一键采纳。
class _ReportSheet extends StatefulWidget {
  final String spotName;
  const _ReportSheet({required this.spotName});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  static const _reasons = ['坐标错误', '已关闭', '信息有误', '已收费', '其他'];

  String _reason = '坐标错误';
  final TextEditingController _note = TextEditingController();

  bool _locating = false;
  double? _lat;
  double? _lng;
  double? _acc;
  String _posErr = '';

  @override
  void initState() {
    super.initState();
    // 打开就开始取：用户点进来多半就是想报位置，不该让他再点一次「获取」
    _grab();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _grab() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _posErr = '';
    });
    try {
      final p = await LocationService.determinePosition();
      if (!mounted) return;
      setState(() {
        _lat = p.latitude;
        _lng = p.longitude;
        _acc = p.accuracy;
        _locating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _posErr = e is LocationException ? e.message : '定位失败，请检查定位权限';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('钓点报错',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text('选择原因', style: TextStyle(color: AppTheme.textTertiary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _reasons
                .map((r) => ChoiceChip(
                      label: Text(r),
                      selected: _reason == r,
                      onSelected: (_) => setState(() => _reason = r),
                    ))
                .toList(),
          ),

          // 只有报「坐标错误」才需要位置，别的理由问了也白问
          if (_reason == '坐标错误') ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(
                color: AppTheme.accentLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.my_location,
                          size: 16, color: AppTheme.accentDark),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _locating
                              ? '正在获取你的位置…'
                              : (_lat != null
                                  ? '${_lat!.toStringAsFixed(6)}, '
                                      '${_lng!.toStringAsFixed(6)}'
                                      '${_acc != null ? '  ·  精度 ±${_acc!.toStringAsFixed(0)} 米' : ''}'
                                  : '没有取到位置'),
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.accentDark),
                        ),
                      ),
                      TextButton(
                        onPressed: _locating ? null : _grab,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _lat == null ? '获取' : '重新获取',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                  if (_posErr.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_posErr,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.danger)),
                    ),
                  if (_lat != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        '你在钓点现场的话，这个位置会作为「建议坐标」交给管理员，'
                        '核对后可直接采纳。',
                        style: TextStyle(
                            fontSize: 11.5, color: AppTheme.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: '补充说明（选填）',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.emoji_emotions_outlined,
                    size: 20, color: AppTheme.textSecondary),
                tooltip: '表情',
                onPressed: () => showEmojiSheet(context, _note),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final note = _note.text.trim();
                Navigator.pop(
                  context,
                  _ReportResult(
                    reason: _reason,
                    note: note.isEmpty ? null : note,
                    // 只在「坐标错误」时把位置带上，别的理由带坐标没意义
                    lat: _reason == '坐标错误' ? _lat : null,
                    lng: _reason == '坐标错误' ? _lng : null,
                    accuracy: _reason == '坐标错误' ? _acc : null,
                  ),
                );
              },
              child: const Text('提交报错'),
            ),
          ),
        ],
      ),
    );
  }
}
