import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
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

/// 渔具店详情页（渔具店已从「本地钓场」里独立出来，走自己的详情页）
///
/// 页面顺序严格按用户要求：
///   ① 店内 / 店外图片（顶部图集，可左右滑）
///   ② 售卖种类（后台「经营范围」字段，用、，,/ 分隔都能拆）
///   ③ 具体位置（地址 + 距离）
///   ④ 是否外送
///   ⑤ 顾客评价（钓点评论表，审核通过才显示）
///   ⑥ 位置导航（底部主按钮 —— 先探测本机装了哪些地图 App，选中后原生唤起导航）
class ShopDetailScreen extends StatefulWidget {
  final FishingSpot spot;

  /// 列表页算好的距离文案（如「1.2km」）。为空则不显示，避免详情页再触发一次定位。
  final String? distanceText;

  const ShopDetailScreen({super.key, required this.spot, this.distanceText});

  @override
  State<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends State<ShopDetailScreen> {
  final PageController _galleryCtrl = PageController();
  int _galleryIndex = 0;

  List<SpotComment> _comments = [];
  bool _loadingComments = true;
  bool _sending = false;

  /// 逆地理反查到的中文地址（渔具店自身没填地址时兜底）
  String _geoAddress = '';

  FishingSpot get _s => widget.spot;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _resolveAddress();
  }

  @override
  void dispose() {
    _galleryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final list = await SpotService.fetchComments(_s.id);
      if (mounted) setState(() => _comments = list);
    } catch (_) {
      // 评价拉不到不影响页面其它内容
    } finally {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  Future<void> _resolveAddress() async {
    if (_s.address.trim().isNotEmpty) return;
    final p = await GeoPlace.reverse(_s.lat, _s.lng);
    if (mounted && p != null && p.display.isNotEmpty) {
      setState(() => _geoAddress = p.display);
    }
  }

  String get _addressText {
    final a = _s.address.trim();
    if (a.isNotEmpty) return a;
    return _geoAddress;
  }

  /// 店内 / 店外图：环境图优先，没有就用封面
  List<String> get _images {
    final list = <String>[..._s.imageUrls];
    final c = _s.coverUrl;
    if (c != null && c.isNotEmpty && !list.contains(c)) list.insert(0, c);
    return list;
  }

  /// 售卖种类：后台「经营范围」一个字段，逗号 / 顿号 / 斜杠都拆
  List<String> get _categories => _s.fish
      .split(RegExp(r'[,，、/|;；\s]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      CenterToast.show(context, '无法拨打电话');
    }
  }

  /// 写评价：提交后进后台审核，审核通过才出现在列表里
  Future<void> _writeReview() async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (!sp.isLoggedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      return;
    }
    final ctrl = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
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
            const Text('评价这家渔具店',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('写清楚货品、价格、老板态度，对钓友最有参考价值',
                style:
                    TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              maxLength: 500,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '例如：老板很懂路亚，饵料比网上便宜，还能现场试竿…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('提交评价'),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text('评价审核通过后才会展示',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (text == null || text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await SpotService.addComment(_s.id, text);
      if (mounted) CenterToast.show(context, '评价已提交，审核通过后显示');
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = _s.tags
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_s.name),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _gallery(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 店名 + 品类小签 + 评分
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2, right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.violetLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('渔具店',
                          style: TextStyle(
                              fontSize: 10.5, color: AppTheme.violet)),
                    ),
                    Expanded(
                      child: Text(_s.name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.star, size: 16, color: AppTheme.star),
                    const SizedBox(width: 3),
                    Text(_s.rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.star)),
                  ],
                ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: tags.map(_tagChip).toList(),
                  ),
                ],
                const SizedBox(height: 14),

                // ② 售卖种类 + ④ 是否外送
                _block(
                  icon: Icons.category_outlined,
                  title: '售卖种类',
                  child: _categories.isEmpty
                      ? const Text('店主暂未填写经营范围',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.textSecondary))
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _categories
                              .map((c) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primarySoft,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: AppTheme.primaryBorder
                                              .withOpacity(.6)),
                                    ),
                                    child: Text(c,
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            color: AppTheme.primary,
                                            fontWeight: FontWeight.w500)),
                                  ))
                              .toList(),
                        ),
                ),
                const SizedBox(height: 10),
                _block(
                  icon: Icons.delivery_dining,
                  title: '是否外送',
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: _s.delivery
                              ? AppTheme.primaryLight
                              : AppTheme.primarySoft,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _s.delivery
                                  ? Icons.check_circle
                                  : Icons.remove_circle_outline,
                              size: 13,
                              color: _s.delivery
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _s.delivery ? '支持外送' : '暂不支持外送',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _s.delivery
                                    ? AppTheme.primary
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_s.delivery && _s.fee.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_s.fee,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // ③ 具体位置
                _block(
                  icon: Icons.place_outlined,
                  title: '具体位置',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _addressText.isEmpty
                            ? '店主暂未填写地址，可点下方「导航前往」在地图里查看'
                            : _addressText,
                        style: const TextStyle(
                            fontSize: 13.5, height: 1.5, color: Colors.black87),
                      ),
                      if (widget.distanceText != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.near_me_outlined,
                                size: 13, color: AppTheme.primary),
                            const SizedBox(width: 4),
                            Text('距你约 ${widget.distanceText}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                      if (_s.phone.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _call(_s.phone),
                          child: Row(
                            children: [
                              const Icon(Icons.phone_outlined,
                                  size: 14, color: AppTheme.primary),
                              const SizedBox(width: 4),
                              Text(_s.phone,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                      if (_s.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(_s.description,
                            style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.55,
                                color: AppTheme.textSecondary)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ⑤ 顾客评价
                _reviewsSection(),
              ],
            ),
          ),
        ],
      ),
      // ⑥ 位置导航（调起本机已安装的地图 App）
      bottomNavigationBar: _bottomBar(),
    );
  }

  /// 顶部图集：店内 / 店外实拍
  Widget _gallery() {
    final images = _images;
    if (images.isEmpty) {
      return Container(
        height: 200,
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppTheme.brandGradient),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront_outlined, color: Colors.white70, size: 40),
            SizedBox(height: 8),
            // 这块就是「店内 / 店外图片」区域：即使店主没传图，
            // 标题也得在，否则用户根本不知道这里原本要放什么
            Text('店内 / 店外实拍',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            SizedBox(height: 4),
            Text('店主暂未上传店面 / 店内照片',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );
    }
    return Stack(
      children: [
        SizedBox(
          height: 220,
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
        // 左上角说明这组图是什么
        Positioned(
          left: 10,
          top: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('店内 / 店外实拍',
                style: TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ),
        if (images.length > 1)
          Positioned(
            right: 12,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.45),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${_galleryIndex + 1}/${images.length}',
                  style:
                      const TextStyle(color: Colors.white, fontSize: 11.5)),
            ),
          ),
      ],
    );
  }

  /// 统一的分块卡片（图标 + 标题 + 内容）
  Widget _block({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppTheme.primary),
              const SizedBox(width: 5),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _tagChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: text.contains('推荐')
            ? AppTheme.warningLight
            : AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              color: text.contains('推荐')
                  ? AppTheme.warning
                  : AppTheme.primary)),
    );
  }

  Widget _reviewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('顾客评价',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(width: 6),
            Text('${_comments.length}',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
            const Spacer(),
            if (_sending)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton.icon(
                onPressed: _writeReview,
                icon: const Icon(Icons.rate_review_outlined, size: 15),
                label: const Text('写评价', style: TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
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
                Icon(Icons.rate_review_outlined,
                    size: 22, color: AppTheme.textSecondary),
                SizedBox(height: 6),
                Text('还没有顾客评价，去做第一个评价的人',
                    style: TextStyle(
                        fontSize: 12.5, color: AppTheme.textSecondary)),
              ],
            ),
          )
        else
          ..._comments.map(_reviewTile),
      ],
    );
  }

  Widget _reviewTile(SpotComment c) {
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
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(3),
                        border:
                            Border.all(color: AppTheme.primaryBorder, width: .7),
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

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              if (_s.phone.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: () => _call(_s.phone),
                  icon: const Icon(Icons.phone_outlined, size: 17),
                  label: const Text('电话', style: TextStyle(fontSize: 13.5)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => MapLauncher.navigate(
                    context,
                    lat: _s.lat,
                    lng: _s.lng,
                    name: _s.name,
                    address: _addressText,
                  ),
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('导航前往',
                      style: TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
