import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/emoji_panel.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/fishing_spot.dart';
import '../models/spot_comment.dart';
import '../services/api_config.dart';
import '../services/geo_place.dart';
import '../services/map_launcher.dart';
import '../services/session_provider.dart';
import '../services/spot_service.dart';
import '../widgets/center_toast.dart';
import '../widgets/user_avatar.dart';
import 'auth_screen.dart';

/// 钓点详情页
/// 顶部为「环境展示图」图集（钓友上传的实拍环境照片），
/// 下方依次是类型/星级、标签、地址/收费/鱼种/电话、描述、精确坐标，
/// 并提供「导航前往」（跳转高德/腾讯/百度地图）与「报错」。
class SpotDetailScreen extends StatefulWidget {
  final FishingSpot spot;
  const SpotDetailScreen({super.key, required this.spot});

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

  @override
  void initState() {
    super.initState();
    _reportCount = widget.spot.reportCount;
    _loadComments();
    _resolveAddress();
  }

  @override
  void dispose() {
    _galleryCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
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
    String reason = '坐标错误';
    final noteCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('钓点报错',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('选择原因', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['坐标错误', '已关闭', '信息有误', '已收费', '其他']
                    .map((r) => ChoiceChip(
                          label: Text(r),
                          selected: reason == r,
                          onSelected: (_) => setSt(() => reason = r),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: '补充说明（选填）',
                  border: OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined,
                        size: 20, color: AppTheme.textSecondary),
                    tooltip: '表情',
                    onPressed: () => showEmojiSheet(context, noteCtrl),
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
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('提交报错'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;

    try {
      await SpotService.reportSpot(
        spotId: widget.spot.id,
        spotName: widget.spot.name,
        reason: reason,
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
      if (mounted) {
        setState(() => _reportCount += 1);
        CenterToast.show(context, '已提交报错，感谢反馈！');
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
      appBar: AppBar(title: Text(s.name)),
      body: ListView(
        children: [
          // —— 环境展示图（图集，可左右滑动） ——
          _buildGallery(images),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 类型 + 核实 + 星级
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: s.kind == 'wild'
                            ? AppTheme.dangerLight
                            : AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${s.kindLabel} · ${s.type}',
                          style: TextStyle(
                              fontSize: 13,
                              color: s.kind == 'wild'
                                  ? AppTheme.danger
                                  : AppTheme.primary)),
                    ),
                    if (s.verified) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.verified,
                          size: 16, color: AppTheme.accent),
                      const SizedBox(width: 4),
                      const Text('官方核实',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.accent)),
                    ],
                    const Spacer(),
                    const Icon(Icons.star, size: 16, color: AppTheme.star),
                    const SizedBox(width: 4),
                    Text(s.rating.toString(),
                        style: const TextStyle(fontSize: 14)),
                  ],
                ),
                // 标签：一行排满再换行（自绘小标签，间距紧凑不拉散）
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: tags.map(_tagChip).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // 地址 / 收费 / 鱼种 / 电话
                if (s.address.isNotEmpty) _infoRow(Icons.location_on_outlined, s.address),
                if (s.fee.isNotEmpty)
                  _infoRow(Icons.payments_outlined, '收费：${s.fee}'),
                if (s.fish.isNotEmpty)
                  _infoRow(Icons.set_meal_outlined, '鱼种：${s.fish}'),
                if (s.phone.isNotEmpty)
                  _infoRow(Icons.phone_outlined, s.phone, onTap: () => _call(s.phone)),
                if (s.commentCount > 0)
                  _infoRow(Icons.chat_bubble_outline, '${s.commentCount} 条评论'),
                const SizedBox(height: 8),
                // 描述
                Text(s.description.isEmpty ? '钓友暂未填写说明' : s.description,
                    style: const TextStyle(fontSize: 15, height: 1.5)),
                const SizedBox(height: 12),
                // 位置：显示中文地址（不再展示经纬度数字）
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accentLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
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
                              fontSize: 13, color: AppTheme.accentDark),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 报错数
                Row(
                  children: [
                    const Icon(Icons.report_problem_outlined,
                        size: 15, color: AppTheme.danger),
                    const SizedBox(width: 6),
                    Text('该钓点已被报错 $_reportCount 次',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.danger)),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => MapLauncher.navigate(
                          context,
                          lat: s.lat,
                          lng: s.lng,
                          name: s.name,
                          address: _navAddress,
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.navigation_outlined, size: 18),
                        label: const Text('导航前往',
                            style: TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _report,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.danger,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.report_problem_outlined,
                            size: 18),
                        label: const Text('报错', style: TextStyle(fontSize: 14)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildCommentsSection(),
              ],
            ),
          ),
        ],
      ),
      // 底部评论输入（提交后需审核，审核通过才出现在上面的列表里）
      bottomNavigationBar: _buildCommentInput(),
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
                        color: const Color(0xFFE8F3FF),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                            color: const Color(0xFFB7DBFF), width: 0.7),
                      ),
                      child: Text('LV${c.userLevel}',
                          style: const TextStyle(
                              fontSize: 9.5,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1677FF))),
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

  /// 底部评论输入条
  Widget _buildCommentInput() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusPill),
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
        ),
      ),
    );
  }

  /// 顶部环境图集：有图显示轮播（带页码指示），无图显示占位
  Widget _buildGallery(List<String> images) {
    if (images.isEmpty) {
      return Container(
        height: 210,
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
                    color: Colors.grey, size: 36),
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
          Icon(icon, size: 15, color: Colors.grey),
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
