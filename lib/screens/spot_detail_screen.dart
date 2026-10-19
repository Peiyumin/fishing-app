import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/fishing_spot.dart';
import '../services/map_launcher.dart';
import '../services/spot_service.dart';
import '../widgets/center_toast.dart';

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

  @override
  void initState() {
    super.initState();
    _reportCount = widget.spot.reportCount;
  }

  @override
  void dispose() {
    _galleryCtrl.dispose();
    super.dispose();
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
                decoration: const InputDecoration(
                  labelText: '补充说明（选填）',
                  border: OutlineInputBorder(),
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
                // 标签
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: tags
                        .map((t) => Chip(
                              label: Text(t),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: AppTheme.primarySoft,
                              labelStyle: const TextStyle(fontSize: 11),
                            ))
                        .toList(),
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
                // 精确坐标
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accentLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '精确坐标（WGS84）：\n'
                    '纬度 ${s.lat.toStringAsFixed(6)}\n'
                    '经度 ${s.lng.toStringAsFixed(6)}',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.accentDark),
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
                        onPressed: () => MapLauncher.showNavSheet(
                          context,
                          lat: s.lat,
                          lng: s.lng,
                          name: s.name,
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
              ],
            ),
          ),
        ],
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
